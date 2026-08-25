# ADR-0007: Resend come unico canale email, Mailpit rimosso

## Contesto

Da ADR precedenti (vedi `one-piece-api/docs/implementation-plan.md`, Step 4),
il realm Keycloak inviava le email di sistema (invito utente, verifica
email, reset password - UF-IDU-01/04/12) a **Mailpit** di default (un
mail-catcher SMTP fittizio in cluster, release `mailpit`), con **Resend**
come relay reale opzionale, attivato solo impostando `RESEND_API_KEY` prima
di `helmfile sync`. La scelta di un default locale era deliberata: senza,
lo sviluppo locale avrebbe richiesto un vero account Resend solo per
esercitare il flow di invito, o avrebbe fallito silenziosamente l'invio.

Decisione presa ora di sostituire Mailpit con Resend **in ogni ambiente**,
eliminando completamente il mail-catcher locale.

## Decisione

- **Release `mailpit` rimossa** (`helm/charts/mailpit`) da ogni ambiente
  Helmfile - non solo `ci`/`remote`, anche `default` (sviluppo locale).
- **`keycloak/realm-onepiece.json`** importa direttamente l'host/porta/
  mittente/auth di Resend (`smtp.resend.com:587`, `auth: true`,
  `starttls: true`) - non più l'host interno di Mailpit. La sola credenziale
  (l'API key, un segreto) resta fuori dal file committato.
- **`scripts/configure-realm-smtp.sh`** si riduce a impostare quella
  credenziale via Admin API dopo l'import (`kcadm.sh update realms/onepiece
  -s smtpServer.password=...`) - non più host/porta/mittente/auth, già
  corretti nel realm importato. **`RESEND_API_KEY` è ora obbligatoria**:
  l'hook fallisce esplicitamente se assente, invece di ripiegare in
  silenzio su un mail-catcher che non esiste più.
- **`scripts/00-check-prerequisites.sh`** verifica `RESEND_API_KEY` prima di
  creare cluster o eseguire `helmfile sync`, per fallire subito invece che
  dopo minuti di provisioning, dentro l'hook postsync di Keycloak.
- **Workflow CI** (`test-infrastructure.yml` in questo repo,
  `e2e.yml` in `one-piece-e2e`) passano `RESEND_API_KEY` da un secret di
  organizzazione (`one-piece-api`), stesso pattern già in uso per
  `GHCR_PULL_TOKEN` (ADR-0004) - richiede che quel secret venga creato a
  livello organizzazione con policy di repository access che includa
  entrambi i repository pubblici.

## Alternative considerate

- **Mantenere Mailpit come default locale, Resend solo per `ci`/`remote`**
  (lo status quo): scartata su richiesta esplicita - un solo canale email
  in ogni ambiente è più semplice da ragionare e da mantenere (nessuna
  logica condizionale, nessun secondo chart da far girare/aggiornare) a
  fronte di un costo reale (vedi Conseguenze) giudicato accettabile.
- **Un chart email generico configurabile per provider** (Mailpit in
  `default`, Resend altrove, dietro un'unica interfaccia): scartata per
  complessità non giustificata - un solo provider in ogni ambiente non ha
  bisogno di un'astrazione per sceglierne uno.

## Conseguenze

- **`RESEND_API_KEY` è ora un prerequisito obbligatorio per qualunque
  sviluppo locale**, non solo per gli ambienti condivisi - ogni sviluppatore
  ha bisogno di un proprio account Resend (piano gratuito: 100 email/giorno,
  3.000/mese, sufficiente per lo sviluppo). Questo è il costo diretto della
  semplificazione sopra: lo sviluppo locale del flow di invito non è più
  possibile "a costo zero, senza account esterni". Per non richiedere un
  `export` manuale ad ogni sessione di shell, viene letta da un file
  `.env.local` locale (radice del repo, escluso da git) caricato
  automaticamente da `scripts/lib/load-env-local.sh` - stesso principio di
  `oauth2-proxy/secret.local.yaml` per l'altro segreto locale del repo, vedi
  la sezione "Segreti locali" del README.
- **Limite di importante rilievo pratico, accettato**: senza un dominio di
  invio verificato su Resend, l'account può inviare solo al proprio
  indirizzo email verificato - non a indirizzi arbitrari come quelli
  `@onepiece.local` usati dagli utenti seed (`realm-onepiece.json`) o
  generati dai test e2e (`uniqueEmail()` in `one-piece-e2e`). Fino a quando
  non verrà verificato un dominio reale, il flow di invito end-to-end
  (ricevere davvero l'email e cliccare il link) è verificabile solo
  invitando il proprio indirizzo Resend - non gli utenti seed. I test e2e
  esistenti non ne risentono perché non leggono mai il contenuto
  dell'email (asseriscono solo lo stato UI, non l'inbox), ma un QA umano che
  voglia vedere l'email reale deve invitare se stesso, non `usopp@onepiece.local`.
  Verificare un dominio proprio su Resend rimuove questo limite; non fatto
  in questa ADR.
- **Nessuna UI locale per ispezionare le email inviate**: Mailpit offriva
  una web UI raggiungibile via port-forward; le email inviate tramite
  Resend si consultano nella sua dashboard cloud (`resend.com/emails`), che
  mostra comunque il contenuto/HTML di ogni invio (anche se la consegna
  fallisce per il limite del punto precedente).
- Un componente in meno da mantenere/aggiornare in ogni ambiente (nessuna
  immagine `axllent/mailpit` da tracciare), e un budget di risorse liberato
  - rilevante per l'ambiente `remote` always-free pianificato in
  `docs/adr/0005-remote-dev-environment-oracle-cloud.md`, che già ipotizzava
  l'esclusione di Mailpit per vincoli di CPU/RAM.
