# ADR-0011: Reconciliazione del realm Keycloak con keycloak-config-cli

## Contesto

`keycloak/realm-onepiece.json` e' la unica source of truth dichiarativa del
realm (ADR-0001), importata all'avvio da `--import-realm`. Quel comando pero'
crea solo le entita' mancanti: non aggiorna quelle gia' presenti in un realm
gia' esistente (bug noto keycloak/keycloak#14884). Il sintomo si e' ripetuto
ad ogni modifica strutturale del realm dopo il primo deploy: SMTP (ADR-0007),
redirect URI del client in "remote", permessi del catalogo ruoli - ognuno
risolto con un hook `postsync` dedicato che ri-applica quel singolo campo via
Admin API (`configure-realm-smtp.sh`, `configure-remote-redirect-uris.sh`,
`configure-role-catalog-permissions.sh`). L'ultimo caso, `loginTheme`/
internazionalizzazione (ADR-0010), non era ancora coperto: il tema custom non
si e' propagato al cluster remoto gia' avviato finche' non e' stato aggiunto
questo meccanismo generale.

Il pattern "un hook ad-hoc per ogni campo che scopriamo driftare" non scala:
richiede di ricordarsi, per ogni futura modifica a `realm-onepiece.json`, se
il campo toccato e' fra quelli gia' coperti da un hook - altrimenti resta
silenziosamente senza effetto su un cluster gia' avviato, come appena
successo.

## Decisione

Un Job Kubernetes one-shot esegue `keycloak-config-cli` (adorsys, OSS) come
hook `postsync` della release Helmfile `keycloak`, dopo ogni sync: legge
`realm-onepiece.json` (stessa ConfigMap gia' montata per `--import-realm`) e
lo applica come stato desiderato via Admin API con un diff/patch reale, non
solo "crea se manca" - lo stesso principio di `terraform apply` gia' in uso
per l'infrastruttura OCI (ADR-0005), qui applicato al realm.

Il Job va eliminato e riapplicato esplicitamente ad ogni sync
(`scripts/sync-realm-config.sh`): un Job e' immutabile, quindi non basta un
semplice `kubectl apply` per farlo rieseguire quando cambia solo il contenuto
della ConfigMap montata. Rieseguirlo sempre, non solo quando il file cambia,
corregge anche il drift introdotto da una modifica manuale via Admin Console,
coerente con lo spirito dichiarativo del resto dello stack.

Immagine `adorsys/keycloak-config-cli:6.5.1-26`: v6.5.1 e' l'ultima release
stabile del tool; il tag `-26` segue lo schema di versioning per major
Keycloak di upstream (nessun tag per la patch esatta 26.6.4 pubblicato) - la
compatibilita' entro lo stesso major e' l'assunzione esplicita di upstream,
verificata qui contro un realm locale gia' driftato prima di fidarsene sul
cluster remoto.

Gli hook ad-hoc esistenti (SMTP, redirect URI remoti, permessi ruoli)
**restano invariati**: il primo imposta un segreto non presente nel JSON
committato, il secondo un valore specifico dell'ambiente `remote`
(`OCI_LB_IP`, noto solo a deploy-time) - nessuno dei due e' esprimibile in
`realm-onepiece.json` senza introdurre variabile-substitution nel file
dichiarativo, fuori scope qui. Il terzo (permessi ruoli) e' ridondante con
questo nuovo meccanismo generale ma non ritirato in questo cambio, per
tenerlo minimale e verificabile - consolidamento futuro possibile.

## Alternative considerate

- **Generalizzare lo script kcadm esistente** (iterare sui campi scalari di
  primo livello di `realm-onepiece.json` e riapplicarli via `kcadm update`):
  zero nuove dipendenze, ma resta un meccanismo custom che aggira il limite
  di Keycloak invece di usare uno strumento pensato per questo, e non copre
  bene strutture annidate (client, ruoli) - gia' gestite separatamente dagli
  hook esistenti con la stessa fragilita' che si vuole eliminare.
- **Mantenere il rimedio manuale** (eliminare il realm via Admin API/Console
  prima del prossimo riavvio, documentato finora in ADR-0010): scartata -
  non riproducibile ne' automatica, esattamente il tipo di passo manuale che
  questo repo evita ovunque altrove (Terraform, Helmfile, realm JSON).
- **Nuova release Helmfile separata** (invece di un hook `postsync` sulla
  release `keycloak` esistente) con `needs: [auth/keycloak]`: scartata -
  richiederebbe propagare la stessa dipendenza a ogni release a valle che
  oggi si affida implicitamente al completamento degli hook `postsync` di
  `auth/keycloak`; un hook sulla release esistente eredita quella garanzia
  senza modificare il grafo delle dipendenze.

## Conseguenze

- Un nuovo componente nello stack (Job one-shot, non un controller
  persistente): impatto contenuto sul budget Always Free del nodo remoto
  (ADR-0005), da riverificare dopo la prima esecuzione reale.
- Le modifiche future a `realm-onepiece.json` (campi scalari, client, ruoli)
  si propagano automaticamente al prossimo deploy, locale o remoto, senza
  passi manuali - risolve anche il drift immediato del tema (ADR-0010) sul
  cluster remoto gia' avviato.
- Gli hook ad-hoc esistenti restano, con overlap parziale (permessi ruoli):
  consolidarli e' un'opportunita' futura, non necessaria per chiudere questo
  gap.
