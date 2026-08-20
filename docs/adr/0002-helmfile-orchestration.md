# ADR-0002: Orchestrazione dello stack via Helmfile

## Contesto

Lo stack (namespace, PostgreSQL, Keycloak, whoami, oauth2-proxy) era
orchestrato da script bash numerati (`scripts/02-06-*.sh`), eseguiti in
sequenza da `setup.sh`. Le dipendenze reali tra i componenti (Keycloak ha
bisogno di PostgreSQL pronto; oauth2-proxy ha bisogno di Keycloak e whoami
pronti) erano solo implicite nell'ordine degli script, e la readiness era
verificata da una funzione `wait_for_pod` scritta a mano attorno a
`kubectl wait`.

Durante il primo utilizzo di questo script, quella funzione ha causato due
problemi distinti in produzione (cioè eseguendo `setup.sh` da zero):

1. **Timeout troppo stretti**: su un cluster kind ricreato da zero, le
   immagini vanno scaricate a freddo. Su una rete lenta (~1MB/s osservato),
   il solo pull di PostgreSQL (~170s) e Keycloak (~250s) superava i timeout
   inizialmente scelti (120s e 5 minuti), pur non essendoci alcun problema
   con i pod stessi.
2. **Race condition reale**: `kubectl wait` non attende che un pod venga
   *creato* — se il selettore non trova ancora nulla (finestra tra
   `kubectl apply` sullo StatefulSet/Deployment e la reconciliation del
   controller), fallisce subito con `no matching resources found` invece
   di aspettare, in modo intermittente e difficile da riprodurre.

Entrambi i problemi sono sintomi dello stesso limite: la logica di
dipendenza e readiness era reimplementata a mano invece di usare un
meccanismo maturo già esistente.

## Decisione

Adottare [Helmfile](https://helmfile.readthedocs.io/) per orchestrare tutte
le release dello stack, con le dipendenze dichiarate esplicitamente
(`needs:`) e la readiness delegata a `helm upgrade --install --wait`
(nativo di Helm, gestisce Deployment/StatefulSet/Job senza i bug sopra).

### Manifest raw come micro-chart locali

PostgreSQL, whoami e il namespace non sono chart Helm "veri" (nessun
parametro, nessuna variazione tra ambienti): sono manifest Kubernetes raw,
per gli stessi motivi già validi in ADR-0001. Helmfile però orchestra
*release*, e una release richiede sempre un chart. Per portarli sotto lo
stesso grafo di dipendenze di Keycloak e oauth2-proxy (invece di lasciarli
fuori, applicati con un meccanismo diverso), sono ora wrappati in
micro-chart locali (`helm/charts/namespace`, `helm/charts/postgresql`,
`helm/charts/whoami`): solo `Chart.yaml` + `templates/`, contenuto
identico ai manifest originali, senza `values.yaml` né parametrizzazione
non necessaria.

### Grafo delle dipendenze

```
namespace
  ├─ postgresql
  │    └─ keycloak ─┐
  ├─ whoami          ├─ oauth2-proxy
  └──────────────────┘
```

`keycloak` dipende da `namespace` e `postgresql`; `oauth2-proxy` dipende da
`namespace`, `keycloak` e `whoami`. Helmfile calcola l'ordine di sync da
questo grafo (`helmfile graph` lo stampa) invece che da un array bash.

### Generazione di Secret e ConfigMap: hook `presync`

Due passaggi imperativi non hanno un chart naturale in cui vivere:

- la ConfigMap del realm, generata da `keycloak/realm-onepiece.json`
  (unica source of truth, non una copia YAML committata — motivazione
  invariata rispetto ad ADR-0001);
- il Secret di oauth2-proxy (`client-secret` estratto dal realm,
  `cookie-secret` generato casualmente), mai committato.

Restano script bash dedicati (`scripts/apply-realm-configmap.sh`,
`scripts/generate-oauth2-proxy-secret.sh`), agganciati come hook
`presync` rispettivamente sulle release `keycloak` e `oauth2-proxy`:
girano prima del sync della release che ne dipende, con lo stesso ordine
di causa-effetto di prima ma dichiarato nel grafo invece che
nell'ordinamento di uno script.

### `helmfile sync`, non `helmfile apply`

`apply` calcola un diff prima di sincronizzare (richiede il plugin
`helm-diff`) — utile per aggiornamenti incrementali mirati. Per un
ambiente locale che in pratica si ricrea spesso da zero (teardown +
setup), `sync` è sufficiente, non richiede plugin aggiuntivi, ed è quindi
il default in `setup.sh`. `apply` resta un'alternativa valida una volta
installato `helm-diff`.

## Alternative scartate

- **Kustomize + `kubectl apply -k`**: gestisce bene i manifest raw, ma non
  ha un concetto nativo di dipendenza tra risorse/release né di attesa di
  readiness — avremmo dovuto comunque reimplementare l'ordinamento a mano,
  lo stesso problema di partenza.
- **ArgoCD / Flux (GitOps)**: risolverebbero ordinamento e readiness in
  modo dichiarativo, ma introducono un controller persistente nel cluster,
  pensato per ambienti con reconciliation continua — sproporzionato per un
  cluster locale ricreato manualmente a ogni sessione di lavoro.
- **Lasciare PostgreSQL/whoami fuori da Helmfile** (applicati con
  `kubectl apply` come oggi, solo Keycloak/oauth2-proxy come release
  Helmfile): avrebbe comunque richiesto un secondo meccanismo di
  ordinamento per i componenti non-Helmfile, vanificando l'obiettivo di un
  unico grafo di dipendenze esplicito.

## Conseguenze

- Nuovo strumento nel toolchain: `helmfile` (binario Go singolo). Nessun
  pacchetto winget disponibile su questo sistema; installato scaricando il
  binario da GitHub Releases in `~/.local/bin` (stesso percorso già usato
  per `jq`, non presente in PATH via winget/choco in questo ambiente).
- `scripts/wait_for_pod` (in `lib/common.sh`) è stato rimosso: la sua unica
  ragion d'essere (attesa readiness con timeout) è ora responsabilità di
  Helm stesso via `--wait`, per ogni release.
- I timeout per-release (`timeout:` in `helmfile.yaml`) riusano gli stessi
  valori empiricamente validati risolvendo il problema (1): 240s per
  PostgreSQL, 600s per Keycloak (alzato da un iniziale 480s dopo aver
  osservato un avvio più lento del solito sotto carico di sistema
  sostenuto durante il primo test di questa nuova configurazione).
- Le versioni pinnate dei chart Helm (`codecentric/keycloakx` 7.2.3,
  `oauth2-proxy/oauth2-proxy` 10.7.0) vivono ora solo in `helmfile.yaml`,
  non più duplicate in `lib/common.sh`.
