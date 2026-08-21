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
immagini di `user-service`/`user-frontend`: `default` (locale, `kind load
docker-image`) o `ci` (immagini da GHCR, usato dalla CI di questo repo) —
vedi `docs/adr/0004-ci-images-from-ghcr.md`.

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
# poi apri http://localhost:4180
```

## Convenzioni (da definire)

- Gestione dei secret: TBD (es. Sealed Secrets / External Secrets Operator)
- Ambienti: `dev`, `staging`, `production`
- GitOps: TBD (es. ArgoCD / Flux)

## Come contribuire

Le pull request devono limitarsi a modifiche infrastrutturali. Il codice
applicativo del progetto One Piece vive in repository separati.
