# ADR-0001: Stack di autenticazione locale (kind + Keycloak + oauth2-proxy)

## Contesto

Serve un ambiente Kubernetes locale, riproducibile, per validare il flow
OAuth 2.0 Authorization Code + PKCE che proteggerà i servizi One Piece API,
senza ancora introdurre UserService, OnePieceService, Ingress o DNS.

## Decisioni

### Cluster: kind

Un singolo cluster kind (`onepiece`, un nodo control-plane) fornisce un
ambiente Kubernetes reale via Docker, senza costi cloud né dipendenze da un
provider. Nessuna `extraPortMapping`: l'accesso è esclusivamente tramite
`kubectl port-forward`, come richiesto — nessuna esposizione del nodo.

### Keycloak: codecentric/keycloakx invece di bitnami/keycloak

La scelta iniziale (`bitnami/keycloak`, con PostgreSQL come subchart) non è
più praticabile: dal 28 agosto 2025 Broadcom ha spostato la quasi totalità
delle immagini Bitnami dietro un abbonamento a pagamento ("Bitnami Secure
Images"), svuotando i tag gratuiti su `docker.io/bitnami/*`
(`docker.io/bitnami/keycloak` risulta oggi senza alcun tag pubblico).

Si è scelto `codecentric/keycloakx`: chart community mantenuto attivamente
(release allineate alle versioni Keycloak, ultima a poche settimane da
questa configurazione) che usa direttamente l'immagine ufficiale del
progetto Keycloak (`quay.io/keycloak/keycloak`), senza rebuild di terze
parti. Alternativa scartata: il Keycloak Operator ufficiale (CRD `Keycloak`
+ `KeycloakRealmImport`) — più "ufficiale" in senso stretto, ma introduce
un Operator e CRD aggiuntivi non necessari per un singolo ambiente locale;
il chart Helm classico (Deployment/StatefulSet + ConfigMap) è sufficiente e
più semplice da ispezionare.

### PostgreSQL: immagine ufficiale, manifest raw invece di un chart

Con `keycloakx` non c'è più un subchart PostgreSQL incluso. Anziché cercare
un altro chart Helm di terze parti, si usa direttamente l'immagine ufficiale
Docker (`postgres`, Docker Official Image, mantenuta attivamente) in uno
StatefulSet dichiarativo (`postgresql/postgresql.yaml`). Per una singola
istanza locale, un Operator (es. CloudNativePG) aggiungerebbe complessità
(CRD, controller) senza benefici concreti in questa fase — scartato per
`Non introdurre tecnologie o componenti non necessari al presente
obiettivo`.

### Issuer stabile: KC_HOSTNAME fisso su localhost

Il browser raggiunge Keycloak solo via `localhost:8080` (port-forward),
mentre oauth2-proxy lo raggiunge via DNS interno del cluster
(`keycloak-http.auth.svc.cluster.local:8080`). Se l'issuer nei token variasse in
base a chi effettua la richiesta, la validazione dei token fallirebbe
(mismatch tra issuer atteso e issuer nel JWT). Impostando
`--hostname=localhost --hostname-port=8080 --hostname-strict=false`,
Keycloak emette sempre lo stesso issuer
(`http://localhost:8080/realms/onepiece`), indipendentemente da come viene
raggiunto internamente. Trade-off: in un ambiente non locale, l'hostname
andrebbe reso configurabile per dominio invece che fissato.

### Realm import dichiarativo

Il realm (`realm-onepiece.json`) è montato via ConfigMap e importato
automaticamente all'avvio (`--import-realm`), invece di essere configurato
manualmente dall'Admin Console. Questo rende la configurazione IAM
versionabile e riproducibile — coerente con la preferenza del progetto per
configurazione dichiarativa.

### ROPC temporaneo per lo smoke test

Il client `onepiece-proxy` abilita `directAccessGrantsEnabled` solo per
eseguire uno smoke test rapido (username/password → token) senza dover
guidare un browser reale attraverso l'Authorization Code flow durante lo
scripting. Non è l'architettura di autenticazione effettiva (che resta
Authorization Code + PKCE via oauth2-proxy) e va disabilitato subito dopo
la verifica.

### Scripting: ConfigMap del realm generata a runtime, non committata

L'orchestrazione (`scripts/`) genera la ConfigMap `one-piece-realm-config`
al volo da `realm-onepiece.json` (`kubectl create configmap ...
--dry-run=client -o yaml | kubectl apply -f -`) invece di leggere una copia
YAML committata nel repository. La copia era un file derivato che andava
rigenerato a mano dopo ogni modifica al realm — un rischio di
disallineamento silenzioso. `realm-onepiece.json` resta l'unica source of
truth; la ConfigMap è un dettaglio implementativo del deploy.

Per lo stesso motivo, lo smoke test automatico (`scripts/07-smoke-test.sh`)
non usa più il grant ROPC descritto sopra — che resta disabilitato di
default sul client — ma simula l'intero flow Authorization Code + PKCE via
`curl` con un cookie jar: verifica così l'architettura realmente in uso,
senza dover riabilitare a ogni run una grant type sconsigliata in
produzione.

### Attributi utente custom: User Profile dichiarativo esplicito

Il modello di identità applicativa (vedi
`one-piece-api/docs/user-flows/application-user-identity-management.md` §2)
richiede che l'account Keycloak di ogni utente referenzi lo `userId`
generato dall'applicazione, esposto come claim del token tramite un
protocol mapper `oidc-usermodel-attribute-mapper` su un attributo utente
Keycloak custom (`userId`).

Da Keycloak 24 in poi, la gestione degli attributi utente è dichiarativa
("User Profile"): un realm senza una configurazione esplicita usa uno
schema built-in che include solo `username`/`email`/`firstName`/`lastName`
e scarta silenziosamente qualunque attributo non dichiarato
(`unmanagedAttributePolicy` non impostato) — un `userId` messo in
`users[].attributes` nel realm JSON viene quindi importato senza errori ma
non risulta mai leggibile né dall'Admin API né, di conseguenza, nel token.
Il realm dichiara perciò esplicitamente il proprio User Profile
(`components["org.keycloak.userprofile.UserProfileProvider"]`,
`kc.user.profile.config`), replicando i 4 attributi built-in di default e
aggiungendo `userId` come attributo gestito, sola lettura/scrittura per
`admin` (mai per `user`, essendo generato dall'applicazione e immutabile).

Alternativa scartata: abilitare `unmanagedAttributePolicy` (`ADMIN_EDIT`
o `ENABLED`) invece di dichiarare lo schema per esteso — più corto da
scrivere, ma rende *qualunque* attributo scritto da un chiamante con
permessi sufficienti "gestito" implicitamente, senza validazione né
visibilità esplicita nell'Admin Console; scartato per coerenza con la
preferenza del progetto per configurazione dichiarativa ed esplicita
piuttosto che comportamento implicito.

### Aggiornamento: attributo `userId` rimosso, si usa il `sub` standard

La decisione sopra è superata. Con il refactor della lettura utenti in
`user-service` (Step 3, UF-IDU-17), l'identità del chiamante non ha più
bisogno di un identificatore generato dall'applicazione: sia la risoluzione
dell'utente autenticato (`ApplicationUserJwtAuthenticationConverter`) sia
l'admin listing (`AdminUserQueryService`) usano ora l'id nativo dell'account
Keycloak — rispettivamente il claim standard `sub` del token OIDC e
`UserRepresentation.getId()` dell'Admin REST API — invece dell'attributo
custom `userId`.

Di conseguenza, dal realm sono stati rimossi: l'attributo `userId` dal User
Profile dichiarativo (essendo rimasti solo i 4 attributi built-in di
default, l'intero override `components` non serve più — il realm torna
allo schema built-in implicito di Keycloak), il client scope
`application-user` con il relativo protocol mapper, e il riferimento ad
esso in `defaultClientScopes` di `onepiece-proxy`. L'utente seed `luffy`
fissa ora il proprio `id` Keycloak nativo
(`446fbe79-5cc4-458d-925d-9934334b6dcf`, lo stesso valore già usato prima
come attributo custom) invece di dichiararlo come attributo applicativo, per
continuità con test/documentazione esistenti.

Conseguenza per il modello di identità applicativo: `userId` (§2 di
`application-user-identity-management.md`) non è più generato
dall'applicazione prima della creazione dell'account Keycloak, ma coincide
con l'id che Keycloak stesso assegna all'account al momento della
creazione — quel documento va aggiornato di conseguenza (fuori dallo scope
di questo ADR, che riguarda solo la configurazione del realm).

## Conseguenze

- Nessuna dipendenza da immagini Bitnami: minor rischio di rotture future
  legate a un catalogo che si sta restringendo.
- Un componente in più da gestire manualmente (PostgreSQL) rispetto a un
  subchart integrato, ma con un manifest più semplice da leggere e capire.
- Le credenziali (admin Keycloak, password PostgreSQL, client secret) sono
  placeholder locali committati nel repository, chiaramente marcati "da
  sostituire" — non sono segreti reali. Il cookie secret di oauth2-proxy,
  invece, è generato casualmente e tenuto fuori da git.
