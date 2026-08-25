# one-piece-infrastructure

Repository dedicato esclusivamente all'infrastruttura del progetto **One Piece**.

Contiene (e conterrà in futuro) tutto ciò che riguarda il deployment e la gestione
dell'infrastruttura, mantenuto separato dal codice applicativo:

- **Kubernetes** — manifest e configurazioni del cluster
- **Helm** — chart per il deployment dei componenti
- **Keycloak** — configurazione Identity & Access Management
- **PostgreSQL** — configurazione del database
- **oauth2-proxy** — proxy di autenticazione
- Configurazioni di **deployment** e **networking**

## Stato del repository

Ambiente locale di autenticazione funzionante su kind: Keycloak (realm
`onepiece` importato dichiarativamente) + PostgreSQL + oauth2-proxy, con un
upstream temporaneo (`whoami`) per validare il flow OAuth 2.0 Authorization
Code + PKCE. Nessun Ingress/DNS: accesso esclusivamente via
`kubectl port-forward`. Lo stack è orchestrato da Helmfile (dipendenze tra
componenti dichiarate esplicitamente). Dettagli e motivazioni delle scelte
in `docs/adr/0001-local-auth-stack.md` e
`docs/adr/0002-helmfile-orchestration.md`.

## Struttura

```
one-piece-infrastructure/
├── helmfile.yaml.gotmpl      # Orchestrazione dello stack: dipendenze tra
│                              # componenti (needs:), ambienti local/ci
│                              # (vedi ADR-0002, ADR-0004)
├── scripts/                  # Setup/teardown dell'ambiente locale (vedi sotto)
├── kubernetes/                # Config cluster kind
├── keycloak/                  # values Helm, realm dichiarativo (unica source of truth)
├── oauth2-proxy/               # values Helm, credenziali locali (non committate)
├── helm/charts/                 # Micro-chart locali: namespace, postgresql, whoami
│                                 # (manifest raw wrappati per Helmfile, vedi ADR-0002)
├── networking/                  # Ingress, network policy, DNS, TLS (futuro)
└── docs/
    └── adr/                      # Architecture Decision Records
```

## Ambiente locale di autenticazione

Vedi `docs/adr/0001-local-auth-stack.md` e
`docs/adr/0002-helmfile-orchestration.md` per il contesto e le scelte
architetturali. Per crearlo o distruggerlo:

```bash
cp .env.local.example .env.local   # una tantum: valorizza RESEND_API_KEY
./scripts/setup.sh       # crea tutto da zero: cluster, stack via Helmfile,
                          # e uno smoke test end-to-end
./scripts/teardown.sh    # elimina il cluster kind (chiede conferma)
```

`setup.sh` esegue prerequisiti → cluster → `helmfile sync` → smoke test:

| Passo | Cosa fa |
|---|---|
| `scripts/00-check-prerequisites.sh` | verifica docker/kind/kubectl/helm/helmfile/jq/openssl/curl |
| `scripts/01-create-cluster.sh` | crea il cluster kind `onepiece` (idempotente) |
| `helmfile sync` (da `helmfile.yaml.gotmpl`) | applica namespace, PostgreSQL, Keycloak, whoami, oauth2-proxy nell'ordine dettato dalle loro dipendenze (`needs:`) |
| `scripts/02-smoke-test.sh` | verifica l'intero flow Authorization Code + PKCE via curl |

`HELMFILE_ENVIRONMENT` (env var, default `default`) sceglie l'origine delle
immagini di `user-service`/`user-frontend`: `default` (locale) o `ci`
(immagini da GHCR, usato dalla CI di questo repo) — vedi
`docs/adr/0004-ci-images-from-ghcr.md`.

Le email di sistema (invito utente, verifica email, reset password —
UF-IDU-01/04/12) a livello di realm Keycloak vanno al vero relay **Resend**
in `default`/`remote` — nessun mail-catcher locale (`RESEND_API_KEY`, env
var **obbligatoria** in questi ambienti, verificata da
`00-check-prerequisites.sh` prima di creare qualunque cosa; la credenziale
viene impostata sul realm da `scripts/configure-realm-smtp.sh`, hook
postsync della release "keycloak" — vedi
`docs/adr/0007-resend-only-email-delivery.md`). In `ci` vanno invece a
**Mailpit** (mock SMTP in-cluster, nessuna chiave richiesta): il sandbox
Resend consegna solo al proprio indirizzo verificato, non agli indirizzi
arbitrari `@onepiece.local` che seed e test e2e usano — vedi
`docs/adr/0008-mock-smtp-in-ci.md`.

### Segreti locali

`.env.local` (radice del repo, escluso da git) raccoglie i segreti che gli
script locali leggono da env var - copiare da `.env.local.example` una
tantum e valorizzare; `scripts/lib/load-env-local.sh` lo carica
automaticamente in ogni script che ne ha bisogno (compresi gli hook
Helmfile invocati direttamente, es. `helmfile sync -l name=keycloak`), così
non serve `export` manuale ad ogni sessione di shell. Stesso spirito di
`oauth2-proxy/secret.local.yaml` per l'altro segreto locale di questo repo
(quello, a differenza di questi, non richiede un account esterno: viene
letto/generato da `realm-onepiece.json` e da un valore casuale, vedi
`scripts/generate-oauth2-proxy-secret.sh`).

Il realm ha `adminEventsEnabled: true` (dettagli disattivati,
`adminEventsDetailsEnabled: false`; retention 7 giorni, `eventsExpiration:
604800`): `user-service` lo interroga (Step 5, UF-IDU-03) per sapere quando è
stato inviato l'ultimo invito/resend a un utente, invece di tenerne traccia
autonomamente — vedi `docs/adr/0004-invitation-expiry-gating.md` nel repo
`one-piece-user-service`.

Nell'ambiente `default`, un hook presync (`scripts/build-and-load-local-image.sh`,
eseguito automaticamente da Helmfile prima di ciascuna delle due release)
costruisce l'immagine `:local` se non esiste ancora nel Docker daemon locale
(cercando i repository sibling `../one-piece-user-frontend`/
`../one-piece-user-service`, presuppone quindi il layout multi-repo con le
cartelle allo stesso livello di questa) e la carica sempre nel cluster kind
con `kind load docker-image` — anche quando l'immagine non è cambiata, per
restare resiliente a un cluster che l'ha persa (es. dopo un riavvio di
Docker Desktop). Se i repository sibling non sono presenti, l'hook stampa un
avviso e salta: il deploy fallirà se l'immagine non è già nel cluster.

Per iterare su un singolo componente senza rieseguire tutto:

```bash
helmfile sync -l name=keycloak    # solo la release "keycloak" (e i suoi hook)
helmfile diff                     # richiede il plugin helm-diff
helmfile graph                    # stampa il grafo delle dipendenze
```

Accesso ai servizi (solo `kubectl port-forward`, mai esposizione diretta):

```bash
kubectl port-forward svc/keycloak-http -n auth 8080:8080 &
kubectl port-forward svc/oauth2-proxy  -n auth 4180:4180 &
# poi apri http://localhost:4180 (app) - le email inviate da Keycloak si
# consultano nella dashboard Resend (resend.com/emails), non più in locale
```

Per eseguire `user-service` fuori dal cluster (es. da IntelliJ, per debugging — profilo Spring `local`, vedi `application-local.properties` nel repo `one-piece-user-service`), oltre al port-forward di Keycloak sopra serve anche quello del suo datasource — il solo dato che il servizio persiste davvero, l'audit trail delle azioni admin (Step 4, §13 di `application-user-identity-management.md`; Keycloak resta l'unico identity store, vedi §2 dello stesso documento):

```bash
kubectl port-forward svc/one-piece-app-postgresql -n app 5433:5432 &
```

## Ambiente remoto (Oracle Cloud)

Ambiente di sviluppo always-on su OKE (Oracle Kubernetes Engine), piano
Always Free. Decisioni architetturali e motivazioni in
`docs/adr/0005-remote-dev-environment-oracle-cloud.md`. Non ancora
provisionato — l'ADR ne definisce l'architettura, il provisioning
(Terraform + nuovo ambiente Helmfile `remote`) è un passo successivo.

## Convenzioni (da definire)

- Ambienti: `dev` (locale, `kind`), `remote` (Oracle Cloud, vedi sopra),
  `production`: TBD

## Come contribuire

Le pull request devono limitarsi a modifiche infrastrutturali. Il codice
applicativo del progetto One Piece vive in repository separati.
