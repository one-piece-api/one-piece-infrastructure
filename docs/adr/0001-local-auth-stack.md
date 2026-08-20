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

## Conseguenze

- Nessuna dipendenza da immagini Bitnami: minor rischio di rotture future
  legate a un catalogo che si sta restringendo.
- Un componente in più da gestire manualmente (PostgreSQL) rispetto a un
  subchart integrato, ma con un manifest più semplice da leggere e capire.
- Le credenziali (admin Keycloak, password PostgreSQL, client secret) sono
  placeholder locali committati nel repository, chiaramente marcati "da
  sostituire" — non sono segreti reali. Il cookie secret di oauth2-proxy,
  invece, è generato casualmente e tenuto fuori da git.
