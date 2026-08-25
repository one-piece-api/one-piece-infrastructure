# ADR-0008: Mailpit come SMTP in "ci", Resend resta reale altrove

## Contesto

ADR-0007 ha sostituito Mailpit con Resend come unico relay SMTP, in ogni
ambiente incluso "ci" (usato da `one-piece-e2e`). Il primo run CI completo
dopo quel cambio ha mostrato il limite già previsto in quella ADR - "senza
un dominio verificato su Resend, l'account può inviare solo al proprio
indirizzo verificato" - avere un impatto più ampio di quanto stimato: la
chiamata SMTP reale verso indirizzi arbitrari `@onepiece.local` (seed
utenti e `uniqueEmail()` dei test e2e) non falliva a vuoto in modo
innocuo, restava appesa abbastanza a lungo da far scadere in timeout non
solo i test che invitano utenti (`invite-user.spec.ts`,
`resend-invitation.spec.ts`), ma anche test indipendenti eseguiti in
parallelo (es. `login.spec.ts`, sul semplice logout).

## Decisione

- **Mailpit torna, ma solo nell'ambiente "ci"** (`helmfile.yaml.gotmpl`,
  blocco condizionato a `{{ if eq .Environment.Name "ci" }}`) - non in
  "default" (sviluppo locale) né "remote", che restano su Resend reale
  come deciso in ADR-0007.
- **`scripts/configure-realm-smtp.sh`** ramifica su `HELMFILE_ENVIRONMENT`:
  in "ci" punta `smtpServer` del realm a Mailpit (`mailpit.auth.svc.cluster.local:1025`,
  senza auth/TLS) via Admin API; altrove imposta la sola password
  (`RESEND_API_KEY`) come già faceva, sul realm che importa già l'host
  Resend committato in `keycloak/realm-onepiece.json` (invariato).
- **`scripts/00-check-prerequisites.sh`** non richiede più `RESEND_API_KEY`
  quando `HELMFILE_ENVIRONMENT=ci`.
- **Workflow CI** (`test-infrastructure.yml` in questo repo, `e2e.yml` in
  `one-piece-e2e`) non passano più `RESEND_API_KEY`: non serve in "ci".

## Alternative considerate

- **Verificare un dominio proprio su Resend**: rimuoverebbe il limite alla
  radice (consegna a qualunque indirizzo), ma richiede un dominio reale e
  la sua verifica DNS - fuori scope per sbloccare la CI ora.
- **Rendere l'invio email non bloccante lato Keycloak/user-service**:
  risolverebbe anche il rallentamento a cascata su test non correlati, ma
  è una modifica di comportamento applicativo (non solo di config
  dell'ambiente "ci"), con superficie e rischio maggiori.
- **Un solo canale email in ogni ambiente** (lo status quo di ADR-0007):
  scartata qui - i test e2e sono risultati sensibili al limite del
  sandbox Resend, contraddicendo l'assunzione con cui quell'ADR l'aveva
  giudicato accettabile.

## Conseguenze

- **"ci" e "default"/"remote" tornano ad avere comportamenti diversi** sul
  canale email - la semplificazione "un solo provider ovunque" di
  ADR-0007 resta valida solo per gli ambienti non-CI.
- I test e2e possono continuare ad asserire solo lo stato UI (nessuna
  lettura di inbox, invariato), ma senza più dipendere dalla
  raggiungibilità/esito di un servizio esterno reale - stesso beneficio di
  isolamento che Mailpit dava prima di ADR-0007.
- `RESEND_API_KEY` non è più richiesta per contribuire test e2e o
  eseguire la CI di questo repo - resta obbligatoria solo per sviluppo
  locale (`default`) e per l'ambiente `remote` pianificato in
  docs/adr/0005-remote-dev-environment-oracle-cloud.md.
