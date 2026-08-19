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

Il repository è attualmente in fase di **bootstrap**: contiene solo la struttura di
directory iniziale, senza configurazioni applicative concrete. Nessun componente è
stato ancora installato o deployato su alcun cluster.

## Struttura

```
one-piece-infrastructure/
├── kubernetes/           # Manifest Kubernetes "raw" / Kustomize
│   ├── base/              # Risorse base, riutilizzabili tra ambienti
│   └── overlays/           # Override specifici per ambiente
│       ├── dev/
│       ├── staging/
│       └── production/
├── helm/                 # Helm chart custom e file di values
│   └── charts/
├── keycloak/              # Configurazione e realm export di Keycloak
├── postgresql/            # Configurazione del database PostgreSQL
├── oauth2-proxy/          # Configurazione di oauth2-proxy
├── networking/            # Ingress, network policy, DNS, TLS
└── docs/                  # Documentazione dell'infrastruttura
```

Ogni directory contiene per ora un file `.gitkeep` come segnaposto, in attesa dei
contenuti reali.

## Convenzioni (da definire)

- Gestione dei secret: TBD (es. Sealed Secrets / External Secrets Operator)
- Ambienti: `dev`, `staging`, `production`
- GitOps: TBD (es. ArgoCD / Flux)

## Come contribuire

Le pull request devono limitarsi a modifiche infrastrutturali. Il codice
applicativo del progetto One Piece vive in repository separati.
