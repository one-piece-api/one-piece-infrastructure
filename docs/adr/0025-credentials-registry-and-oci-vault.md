# ADR-0025: Registro delle credenziali e External Secrets con OCI Vault

## Contesto

Il remoto passa da ambiente di sviluppo a produzione (piano `implementation-plan-production-remote.md`):
nessuna credenziale in git, valori casuali e fuori da Terraform state. Prima, ogni Secret nasceva in un
punto diverso: template dei chart (password dei ruoli, Redis), script `presync` (client secret estratti
da `realm-onepiece.json`, GHCR, Cloudflare), valori in chiaro nei values (admin Keycloak). Locale e CI
devono restare invariati (placeholder, ADR-0001).

## Decisione

- **Un solo chart `credentials`** (`helm/charts/credentials/values.yaml` è il registro): ogni Secret ha
  nome, namespace e chiavi. Locale/CI: `Secret` con il `placeholder`. Remote: `ExternalSecret` verso il
  `ClusterSecretStore` `oci-vault` (ESO), che legge per `vaultKey`. `remoteOnly` limita un Secret a remote.
- **Nessun Secret nei chart dei consumatori** (`postgresql`, `redis`): referenziano il Secret per nome.
- **Chiavi del Vault**: `onepiece-<componente>-<valore>`, un secret per valore (es. `onepiece-redis-password`).
  Il Vault resta fuori da Terraform; `scripts/seed-vault-secrets.sh` genera i valori casuali e carica
  quelli di `.env.local` (GHCR, Resend), senza mai sovrascrivere né stampare. Il token Cloudflare è stato
  copiato dal Secret di cert-manager.
- **Realm**: i client secret sono `$(env:…)` in `realm-onepiece.json`, risolti da keycloak-config-cli
  (`IMPORT_VARSUBSTITUTION_ENABLED`) dal Secret `one-piece-realm-secrets`. Gli script che parlano con
  Keycloak leggono la password admin dal Secret (`scripts/lib/keycloak-admin-password.sh`).
- **Remote**: la CI tiene solo le credenziali OCI; GHCR, Resend e Cloudflare arrivano dal Vault.

## Alternative

- **Un chart `ExternalSecret` per componente**: duplica il template tre volte senza un chart libreria.
- **Sealed Secrets / SOPS**: i valori cifrati vivrebbero in git; il Vault OCI è già nell'Always Free.
- **Un secret JSON per componente nel Vault**: meno oggetti, ma più parsing e rotazione meno granulare.

## Conseguenze

- Un ExternalSecret non adotta un Secret esistente (`creationPolicy: Owner`): prima del primo sync di
  `remote` vanno eliminati quelli creati a mano (`ghcr-pull-secret`, `cloudflare-dns-api-token`, ecc.).
- Cambiare password al volume Postgres esistente non basta: `POSTGRES_PASSWORD` vale solo al primo
  `initdb`. Il primo sync con i nuovi segreti va fatto con la pagina bianca (PR5).
- **Migrazione di un cluster locale già in uso**: helm rifiuta di adottare i vecchi Secret, e l'upgrade di
  `postgresql` cancella quelli con lo stesso nome che stavano nel suo manifest. Procedura: eliminare i
  Secret di `data`, `auth` e `app` elencati nel registro, poi
  `helm upgrade postgresql helm/charts/postgresql -n data --reuse-values --no-hooks`, poi `helmfile sync`.
  Un cluster nuovo non ne ha bisogno.
- La rotazione di un valore è manuale (nuova versione nel Vault, `refreshInterval` 1h); i pod che lo
  leggono da variabile d'ambiente vanno riavviati.
