# ADR-0022: Indirizzi pubblici dell'ambiente remoto da un unico valore

## Contesto

Nell'ambiente `remote` gli indirizzi pubblici sono costruiti come `http://<OCI_LB_IP>`
in una decina di punti di `helmfile.yaml.gotmpl` (`--hostname` di Keycloak; issuer,
login, redirect e whitelist di oauth2-proxy; `jwtIssuerUri` dei servizi; `keycloakOrigin`
del frontend; redirect di fine invito) e in `scripts/configure-remote-redirect-uris.sh`.
Con il dominio (ADR-0020) e HTTPS (ADR-0021) diventano `https://app.…` e
`https://auth.…`.

Dentro il cluster, la verifica dei token usa già l'indirizzo interno di Keycloak:
oauth2-proxy (`redeem-url`, `oidc-jwks-url`) e user-/content-service (`jwk-set-uri` in
`application-dev.properties`). Solo l'issuer atteso segue l'host pubblico. Resta così:
`auth.` è filtrato da Cloudflare (ADR-0020), e le chiamate interne non devono uscire
dal cluster.

## Decisione

- **Un valore** `publicDomain: onepieceapi.dev` nell'ambiente `remote`; le origin di
  `app`, `auth` e `api` sono ricavate una volta sola nel template. `OCI_LB_IP` resta solo
  per l'annotazione dell'IP riservato sul Load Balancer.
- **Keycloak**:
  - `--hostname=https://auth.onepieceapi.dev`;
  - `--proxy-headers=xforwarded`, con indirizzi fidati limitati al gateway: Keycloak
    sa che la richiesta originale era HTTPS.
- **oauth2-proxy**: `cookie-secure: true`; issuer, login, redirect e whitelist sui nuovi
  host; URL server-to-server invariati (interni).
- **Servizi**: cambia solo `jwtIssuerUri`; JWKS resta interno.
- **Frontend, inviti, redirect URI dei client Keycloak**: `https://app.…` e
  `https://auth.…`.
- **Locale e CI invariati** (`localhost`).

## Alternative considerate

- **Sostituire l'IP con il nome punto per punto**: meno lavoro subito, ma la duplicazione
  resta, e un cambio di dominio o l'introduzione di `dev.` tocca di nuovo dieci punti.
- **Chiavi JWKS dall'host pubblico**: nessun indirizzo interno da conoscere, ma ogni
  verifica passerebbe da internet e da Cloudflare, e l'IP del cluster dovrebbe entrare
  nella regola di `auth.`.

## Conseguenze

- `app.` e `auth.` sono lo stesso sito per il browser (stesso dominio registrabile): i
  cookie `SameSite=Lax` attuali funzionano tra login e logout.
- Un futuro ambiente di produzione o un cambio di dominio si riduce a un valore diverso.
- Supera la parte di ADR-0005 che fissa gli URL pubblici sull'IP riservato.
