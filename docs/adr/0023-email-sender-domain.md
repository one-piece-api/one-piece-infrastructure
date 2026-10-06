# ADR-0023: Mittente email su `mail.onepieceapi.dev`

## Contesto

Keycloak invia le email di sistema (invito, verifica, reset password) tramite Resend
(ADR-0007) con mittente `onboarding@resend.dev`, l'indirizzo sandbox di Resend: le email
arrivano solo all'indirizzo del proprietario. Con un dominio proprio (ADR-0020) il
limite si può togliere verificando il dominio su Resend. Il piano gratuito di Resend
(1 dominio, 3.000 email/mese, 100/giorno) basta per l'uso attuale.

## Decisione

- **Sottodominio dedicato all'invio**: `mail.onepieceapi.dev` verificato su Resend;
  mittente `no-reply@mail.onepieceapi.dev`. La reputazione delle email automatiche
  resta separata dal dominio principale.
- **Record DNS via Terraform** (ADR-0020):
  - su `mail.`: DKIM, e MX + SPF del dominio di ritorno, generati da Resend
    (regione eu-west-1); DMARC `p=quarantine` finché il dominio di invio è nuovo.
- **Dominio principale protetto**: DMARC `p=reject`. Nessuno può spedire a nome
  di `@onepieceapi.dev`, che non invia email. L'SPF del dominio principale è
  quello richiesto da Email Routing (`include:_spf.mx.cloudflare.net`), gestito da
  Cloudflare: un nome ammette un solo SPF, quindi niente `v=spf1 -all`.
- **Email in arrivo**: Cloudflare Email Routing, `contatti@onepieceapi.dev` inoltrato
  alla casella del proprietario. È il contatto da citare nella documentazione dell'API
  pubblica.
- **Realm**: cambia solo `smtpServer.from` in `keycloak/realm-onepiece.json`, comune a
  `default` e `remote`. `ci` resta su Mailpit (ADR-0008).
- **Regola di QA**: niente inviti manuali a indirizzi `@onepiece.local`. Ora vengono
  spediti davvero, e i rimbalzi danneggiano la reputazione del dominio. Si usano
  indirizzi reali o quelli di test di Resend (`delivered@resend.dev`).

## Alternative considerate

- **Mittente sul dominio principale** (`no-reply@onepieceapi.dev`): più leggibile, ma un
  problema di reputazione colpirebbe tutto il dominio.
- **Restare sul sandbox `resend.dev`**: nessun lavoro, ma il flusso di invito resta
  verificabile solo invitando se stessi.

## Conseguenze

- Il flusso di invito è verificabile end-to-end con qualunque indirizzo reale, anche in
  locale.
- I record email vivono in Terraform insieme al resto del DNS; un cambio di provider
  email tocca solo quelli e `from`.
- Supera il "limite di importante rilievo pratico" di ADR-0007.
