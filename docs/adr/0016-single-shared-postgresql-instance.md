# ADR-0016: Istanza PostgreSQL unica condivisa, un database per servizio

## Contesto

Ogni servizio aveva la propria istanza PostgreSQL (Keycloak in `auth`,
user-service e content-service in `app`: ADR-0001, ADR-0003,
`implementation-plan-content.md` §2). Su OKE (ADR-0005) ogni PVC diventa un
block volume OCI, e un block volume occupa **almeno 50 GB** anche se il PVC ne
chiede 2 Gi. Con 2 nodi A1 (2 boot volume da 50 GB) e 3 istanze il totale era
250 GB, contro i **200 GB** della quota Always Free (boot + block insieme):
il quinto volume (content-service) veniva fatturato, circa €0,064 al giorno,
e alla scadenza del free trial sarebbe stato recuperato da Oracle.

## Decisione

- **Una sola istanza PostgreSQL** (release `postgresql`) in un namespace
  dedicato `data`, neutro rispetto a `auth` e `app`.
- **Database-per-service su istanza condivisa**: ogni servizio ha il proprio
  database e un ruolo proprietario con password propria. `REVOKE ALL ON
  DATABASE ... FROM PUBLIC` impedisce a un ruolo di collegarsi ai database
  degli altri. Il superuser `postgres` è usato solo dall'istanza e dal Job di
  bootstrap.
- **Bootstrap tramite Job idempotente** (hook Helm `post-install,post-upgrade`):
  crea ruolo e database solo se mancano e riallinea sempre la password. Gli
  script `/docker-entrypoint-initdb.d` dell'immagine non bastano: girano solo
  su un volume vuoto, quindi un database aggiunto in seguito non verrebbe mai
  creato su un'istanza già esistente.
- **Secret per consumatore**: il chart crea il Secret delle credenziali nel
  namespace di ciascun servizio (un `secretKeyRef` non attraversa i
  namespace). I servizi sono elencati in `databases` nel helmfile.
- **Stessa topologia in tutti gli ambienti** (`default`, `ci`, `remote`): la CI
  verifica la stessa forma che gira in remoto, senza rami per ambiente.
- Migrazione su `remote` senza preservare i dati (scelta esplicita: ambiente
  dev). Il realm viene ricreato da keycloak-config-cli (ADR-0011).

Risultato su OKE: 2 boot + 1 volume = 150 GB, sotto la quota.

## Alternative considerate

- **Un'istanza per servizio (stato precedente)**: isolamento fisico, ma su OCI
  sfora la quota gratuita.
- **Unire solo content-service nell'istanza di user-service**: sarebbe
  arrivato a 200 GB esatti, cioè nessun margine per un servizio futuro.
- **Riusare l'istanza di Keycloak in `auth`**: nessuna migrazione dei dati di
  Keycloak, ma i servizi applicativi sarebbero dipesi dal namespace
  dell'identity provider.
- **Passare a Pay As You Go**: nessuna modifica, ma costo mensile, contrario al
  vincolo di costo zero del progetto.
- **Operator PostgreSQL (CloudNativePG, ...)**: gestione dichiarativa di
  database e ruoli, ma un controller permanente sul budget A1 già stretto non
  è giustificato per un ambiente dev.

## Conseguenze

- L'istanza è un punto di guasto unico: se cade, cadono Keycloak e tutti i
  servizi. Accettabile per un ambiente dev senza requisiti di alta
  disponibilità (ADR-0005).
- Le risorse (CPU, memoria, connessioni) sono condivise: request/limit
  dell'istanza alzati rispetto a una singola istanza precedente.
- Un nuovo servizio con database richiede una voce in `databases` nel
  helmfile, non una nuova release.
- L'host JDBC dei servizi diventa `one-piece-postgresql.data.svc.cluster.local`
  (`application-dev.properties` nei rispettivi repository); in locale basta
  un solo port-forward per tutti i servizi.
- La migrazione da un cluster esistente richiede di disinstallare a mano le
  vecchie release (`auth/postgresql`, `app/app-postgresql`,
  `app/content-postgresql`) ed eliminarne i PVC: `helm uninstall` non
  cancella i PVC di uno StatefulSet, e su OKE il block volume resterebbe
  fatturato.
