# ADR-0014: Ridichiarare esplicitamente i ruoli di default di un client built-in redeclared

## Contesto

ADR-0013 (cancellazione self-service dell'account) dichiara esplicitamente
il client built-in `account` in `realm-onepiece.json` per estendere i suoi
`redirectUris` oltre a quelli di default. Da quel momento, ogni avvio di
Keycloak sull'ambiente `remote` e su un cluster locale ricreato da zero
andava in crash immediato:

```
ERROR: Unable to find composite client role: delete-account
```

Causa: Keycloak crea normalmente i ruoli di default di un client built-in
(`account`, `account-console`, `broker`, `realm-management`,
`security-admin-console`) durante il proprio bootstrap del realm, prima di
processare `roles.realm[]`. Ridichiarare esplicitamente `account` in
`clients[]` (per personalizzarne i `redirectUris`) fa si' che Keycloak tratti
quella nostra dichiarazione come autoritativa per quel client - i suoi ruoli
di default (incluso `delete-account`) non vengono piu' seminati
automaticamente, a meno di dichiararli esplicitamente anche noi. I composite
di ADMIN/REVIEWER/EDITOR (ADR-0013) referenziano proprio `account:delete-account`,
che a quel punto dell'import non esiste ancora - da cui il crash.

Il sintomo si manifestava su ogni ambiente con un realm creato da zero
(cluster locale ricreato, CI `test-infrastructure`, primo bootstrap di
`remote`), ma non su un cluster gia' esistente con quel ruolo gia' presente
dal composite gia' applicato in precedenza da `keycloak-config-cli` - da qui
il ritardo nello scoprirlo.

## Decisione

Dichiarare esplicitamente `delete-account` sotto `roles.client.account` in
`realm-onepiece.json`, accanto ai ruoli/permessi custom di `onepiece-proxy` -
lo stesso principio dichiarativo gia' in uso li', applicato qui a un ruolo
built-in invece che custom. Nessun'altra modifica: i composite di
ADMIN/REVIEWER/EDITOR restano invariati, ora risolvono correttamente il ruolo
gia' dichiarato prima di loro nello stesso file.

Un primo tentativo con una descrizione lunga (spiegava il motivo della
ridichiarazione nel testo stesso) ha prodotto un secondo crash distinto:
`value too long for type character varying(255)` - `KEYCLOAK_ROLE.DESCRIPTION`
e' limitato a 255 caratteri lato schema Postgres di Keycloak, non validato
prima dell'insert/update durante l'import. Descrizione accorciata di
conseguenza; nessun limite di lunghezza analogo sui `name` di ruolo incontrato
finora.

## Alternative considerate

- **Non ridichiarare il client `account`** (tornare a `redirectUris` solo di
  default, gestire l'estensione via hook postsync kcadm come
  `configure-remote-redirect-uris.sh`): scartata - il client `account` va
  comunque dichiarato per aggiungere `redirectUris` in modo dichiarativo
  (ADR-0013 lo preferisce esplicitamente a un hook ad-hoc), il problema reale
  e' la mancata dichiarazione dei suoi ruoli di default, non la sua stessa
  dichiarazione.
- **Rimuovere `--import-realm` e affidarsi solo a `keycloak-config-cli`**
  (ADR-0011) anche per il bootstrap iniziale: scartata per questo problema
  specifico - non e' `--import-realm` in se' il difetto, e' un'assunzione
  implicita di Keycloak su quali ruoli esistono gia' quando un client built-in
  viene ridichiarato; lo stesso comando kcadm di `keycloak-config-cli`
  avrebbe probabilmente lo stesso problema se applicato a un realm ancora
  privo del ruolo.

## Conseguenze

- Ridichiarare un altro client built-in in futuro (o aggiungere un altro
  ruolo di default a un composite) richiede lo stesso trattamento: dichiarare
  esplicitamente qui il ruolo di default referenziato, non solo il composite
  che lo usa.
- Nessun impatto sugli utenti/ruoli esistenti su un realm gia' sincronizzato
  correttamente: `keycloak-config-cli` (ADR-0011) riconcilia comunque
  `roles.client.account` come qualunque altro campo ad ogni sync.
