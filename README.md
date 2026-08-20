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
`kubectl port-forward`. Dettagli e motivazioni delle scelte in
`docs/adr/0001-local-auth-stack.md`.

## Struttura

```
one-piece-infrastructure/
├── scripts/                # Setup/teardown dell'ambiente locale (vedi sotto)
├── kubernetes/             # Config cluster kind, namespace "auth"
├── keycloak/                # values Helm, realm dichiarativo (unica source of truth)
├── postgresql/              # StatefulSet Postgres (immagine ufficiale)
├── oauth2-proxy/            # values Helm, credenziali locali (non committate)
├── whoami/                  # upstream temporaneo per verifica end-to-end
├── helm/                   # Helm chart custom e file di values (futuri)
├── networking/              # Ingress, network policy, DNS, TLS (futuro)
└── docs/
    └── adr/                 # Architecture Decision Records
```

## Ambiente locale di autenticazione

Vedi `docs/adr/0001-local-auth-stack.md` per il contesto e le scelte
architetturali. Per crearlo o distruggerlo:

```bash
./scripts/setup.sh       # crea tutto da zero: cluster, Postgres, Keycloak,
                          # whoami, oauth2-proxy, e uno smoke test end-to-end
./scripts/teardown.sh    # elimina il cluster kind (chiede conferma)
```

`setup.sh` esegue in sequenza gli script numerati in `scripts/`, ciascuno
eseguibile anche da solo per iterare su un singolo componente:

| Script | Cosa fa |
|---|---|
| `00-check-prerequisites.sh` | verifica docker/kind/kubectl/helm/jq/openssl/curl |
| `01-create-cluster.sh` | crea il cluster kind `onepiece` (idempotente) |
| `02-create-namespace.sh` | applica il namespace `auth` |
| `03-deploy-postgresql.sh` | deploya PostgreSQL e attende che sia pronto |
| `04-deploy-keycloak.sh` | genera la ConfigMap del realm da `realm-onepiece.json` e deploya Keycloak |
| `05-deploy-whoami.sh` | deploya l'upstream di test |
| `06-deploy-oauth2-proxy.sh` | genera le credenziali locali (se assenti) e deploya oauth2-proxy |
| `07-smoke-test.sh` | verifica l'intero flow Authorization Code + PKCE via curl |

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
