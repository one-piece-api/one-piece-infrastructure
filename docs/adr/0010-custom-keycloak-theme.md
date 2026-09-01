# ADR-0010: Tema Keycloak custom via immagine dedicata (repo `one-piece-keycloak-theme`)

## Contesto

Login, verifica email, aggiornamento password e aggiornamento profilo
usavano finora il tema di default di Keycloak (`docs/implementation-plan.md`,
Step 4: "deferred, not blocking"). Il repo `one-piece-api` (app) ha nel
frattempo consolidato una direzione visiva propria, "Sunny Deck"
(`docs/UI di riferimento/direzione-c-sunny-deck-v2.dc.html`), gia' adottata
dal frontend Angular: mostrare la UI grezza di Keycloak in mezzo a quel
flow rompe la continuita' visiva proprio nei momenti piu' sensibili
(credenziali, password).

Un tema Keycloak e' un albero di file statici multi-cartella (template
`.ftl`, CSS, immagini, bundle di messaggi per lingua), non un singolo file
di configurazione dichiarativa come il realm JSON gia' gestito da questo
repo (`keycloak/realm-onepiece.json`, montato via ConfigMap da
`scripts/apply-realm-configmap.sh`).

## Decisione

Nuovo repo dedicato, `one-piece-keycloak-theme` (pattern repo-per-componente
gia' in uso per `user-service`/`user-frontend`), che contiene:

- il tema `onepiece` (`theme/onepiece/login/`): **nessun template `.ftl`
  copiato o modificato**. Il tema eredita da `parent=keycloak` e si limita a
  sostituire `theme.properties` (CSS proprio al posto di PatternFly/
  FontAwesome), `messages/messages_it.properties` (copy delle sole schermate
  in scope) e le risorse (CSS/immagini) - i template restano quelli
  ufficiali, aggiornati automaticamente con ogni patch di Keycloak 26.x;
- un `Dockerfile` che parte da `quay.io/keycloak/keycloak:26.6.4` (stessa
  versione di `keycloak/values-keycloakx.yaml`) e copia solo il tema sotto
  `/opt/keycloak/themes/onepiece` - nessun rebuild della base;
  `scripts/build-image.sh` per l'immagine locale (`:local`);
- una CI (`.github/workflows/ci.yml`) che pubblica l'immagine multi-arch su
  GHCR (`ghcr.io/one-piece-api/keycloak-theme`), identica nella forma a
  quella di `user-frontend` (ADR-0004: build per-piattaforma via digest,
  merge del manifest, notifica a `onepiece-infrastructure` per il deploy
  remoto, pulizia delle versioni non taggate).

In questo repo: `keycloak/values-keycloakx.yaml` punta di default a
`one-piece-keycloak-theme:local`; `helmfile.yaml.gotmpl` override
l'immagine con quella GHCR negli ambienti `ci`/`remote` (stesso schema di
`userServiceImage`/`userFrontendImage`) e aggiunge alla release `keycloak`
gli stessi due hook presync di `user-service`/`user-frontend`:
`create-ghcr-pull-secret.sh` (ora parametrizzato per namespace, i Secret
sono namespace-scoped e Keycloak vive in `auth`, non in `app`) e
`build-and-load-local-image.sh`. Il realm (`realm-onepiece.json`) guadagna
`loginTheme: onepiece` e l'internazionalizzazione abilitata con `it` come
unica locale supportata/di default, condizione necessaria perche'
`messages_it.properties` venga effettivamente servito.

## Alternative considerate

- **ConfigMap montata in `/opt/keycloak/themes/onepiece`** (stesso hook
  idiomatico di `apply-realm-configmap.sh`): zero repo/CI nuovi. Scartata:
  il realm-config e' un singolo file JSON, un tema e' un albero con
  sottocartelle (`resources/css`, `resources/img`, `messages`) che
  richiederebbe piu' ConfigMap montate su `subPath` diversi - piu'
  macchinoso e senza precedenti nel repo per asset multi-file, mentre il
  pattern immagine-dedicata-per-componente e' gia' quello usato per
  qualunque altro artefatto non puramente dichiarativo in questo stack.
- **Copiare e modificare i template `.ftl`** per ottenere l'esatta struttura
  del mockup (card col logo dentro l'header, sottotitolo descrittivo sotto
  il titolo): scartata a favore di restare sui template ufficiali
  (`parent=keycloak`, solo CSS/`theme.properties`/messaggi) - il markup di
  Keycloak e' interamente pilotato da classi lette da `theme.properties`
  (`${properties.kcXxxClass!}`) o da id/classi stabili (`.card-pf`,
  `.alert-error`, `#kc-page-title`), quindi la stessa identita' visiva si
  ottiene senza divergere dalla logica applicativa dei template (CSRF,
  validazione per campo, required actions) e senza doverla riallineare ad
  ogni patch release.
- **Tradurre in italiano l'intero bundle messaggi di Keycloak**: il codice
  sorgente del tema base (`theme/base/login/messages/`, tag `26.6.4`)
  contiene solo `messages_en.properties`; l'immagine ufficiale sembra
  comunque risolvere in italiano anche alcune chiavi non presenti nel
  nostro `messages_it.properties` (osservato nello smoke test, es. il
  `<title>` della pagina) - probabile pacchetto community aggiuntivo
  incluso nella distribuzione, non nel repository sorgente. Tradurre a
  mano l'intero bundle (centinaia di chiavi, molte per flow non abilitati
  su questo realm - WebAuthn, OTP, identity brokering, SAML) resta
  comunque un rischio concreto di traduzioni incomplete o incoerenti;
  scartata a favore di tradurre esplicitamente solo le chiavi delle
  schermate in scope, lasciando alla risoluzione automatica di Keycloak
  (community pack se disponibile, altrimenti inglese) tutto il resto.

## Conseguenze

- Nuovo repository da mantenere, con la propria pipeline CI (stesso costo
  operativo gia' accettato per `user-service`/`user-frontend`).
- `create-ghcr-pull-secret.sh` non e' piu' specifico al namespace `app`:
  accetta un namespace come primo argomento (default invariato). I
  chiamanti esistenti (`user-service`, `user-frontend`) non cambiano
  comportamento.
- Un aggiornamento del tema (CSS, copy, immagini) richiede una nuova
  immagine e quindi un redeploy di Keycloak, non un semplice refresh di
  ConfigMap - stesso ciclo di rilascio di `user-service`/`user-frontend`,
  coerente con come questo stack gestisce gia' ogni altro componente non
  puramente dichiarativo.
- Su un realm gia' esistente, `loginTheme`/`internationalizationEnabled`
  aggiunti a `realm-onepiece.json` non vengono applicati in automatico da
  `--import-realm` (limite noto, vedi il commento in testa a
  `scripts/apply-realm-configmap.sh`) - propagati invece automaticamente
  dall'hook postsync `scripts/sync-realm-config.sh` (keycloak-config-cli),
  introdotto proprio per questo caso - vedi
  `docs/adr/0011-keycloak-config-cli-realm-sync.md`.
