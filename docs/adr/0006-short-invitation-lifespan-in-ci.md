# ADR-0006: Token di invito a vita breve nell'ambiente "ci"

## Contesto

Step 5 di `one-piece-api/docs/implementation-plan.md` (UF-IDU-03, resend
invito) introduce `AccountStatus.INVITATION_EXPIRED`, derivato confrontando
l'ultimo invio registrato da Keycloak (admin-events) con
`keycloak.invitation.token-lifespan` — `PT12H`, identico in ogni ambiente,
definito in `application.properties` di `one-piece-user-service` (vedi
`user-service/docs/adr/0004-invitation-expiry-gating.md`).

`one-piece-e2e` deve esercitare il resend reale (bottone "Resend Invitation",
visibile solo su righe `INVITATION_EXPIRED`) contro un Keycloak vero, non
mockato. Con `PT12H` fisso questo non è raggiungibile in un run di CI di
pochi minuti — né esiste un utente seedato in quello stato: gli admin-events
sono generati solo da una vera chiamata `execute-actions-email`, non
importabili dichiarativamente nel realm come gli utenti in
`realm-onepiece.json`.

## Decisione

`KeycloakInvitationProperties.tokenLifespan` resta l'unica fonte di verità
(nessun cambiamento in `one-piece-user-service`), ma diventa overridabile
dall'ambiente: essendo un `@ConfigurationProperties` Spring, il binding
"rilassato" su `KEYCLOAK_INVITATION_TOKEN_LIFESPAN` funziona già oggi, senza
alcuna modifica al codice Java.

Il chart `helm/charts/user-service` guadagna un valore
`invitationTokenLifespan` (stringa vuota di default = nessun override,
resta `PT12H`), che il template inietta come quella env var solo se
valorizzato. `helmfile.yaml.gotmpl` lo imposta a `"PT5S"` solo per
l'ambiente `ci` (lo stesso già usato per le immagini GHCR, ADR-0004) —
l'ambiente `default` (sviluppo locale) resta a `PT12H`, invariato.

## Alternative considerate

- **Endpoint di test-only per forzare lo stato**: scartata — introdurrebbe
  nel codice applicativo un varco pensato solo per i test, in contrasto con
  "non introdurre meccanismi custom quando uno standard esiste" e con la
  scelta già presa in Step 5 di non aggiungere alcun endpoint pubblico
  dedicato all'attivazione/gestione degli inviti.
- **Nessun test e2e sulla scadenza, solo sugli scenari di rifiuto
  immediati** (409 su invito ancora valido, 404 su utente ignoto): scartata
  come unica soluzione — avrebbe lasciato l'unico percorso "successo" del
  resend (quello che il flusso UF-IDU-03 esiste per servire) coperto solo
  da un test con `Clock`/mock, mai contro un Keycloak reale.
- **Accorciare `PT12H` anche in produzione/sviluppo locale**: scartata —
  peggiorerebbe l'esperienza reale (link di invito validi per soli
  secondi) per un bisogno che riguarda solo la CI.

## Conseguenze

- Un solo ambiente (`ci`) ha un comportamento di sicurezza-rilevante
  diverso da produzione (token di invito valido 5s anziché 12h): accettabile
  perché quell'ambiente è effimero (cluster kind ricreato e distrutto ad
  ogni run, mai esposto) e mai promosso.
- Se in futuro comparirà un ambiente "staging" persistente, questo valore
  andrà rivisto esplicitamente per quell'ambiente — non erediterà
  l'override `ci` per errore, dato che ogni ambiente Helmfile lo imposta
  esplicitamente (nessun default implicito diverso da `""`).
- `one-piece-e2e` può ora esercitare l'intero ciclo invito → scadenza →
  resend → nuovo invito valido contro lo stack reale, non solo i rami
  raggiungibili senza attendere.
