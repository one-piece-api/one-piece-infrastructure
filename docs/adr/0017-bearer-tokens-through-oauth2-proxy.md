# ADR-0017: Bearer token attraverso oauth2-proxy per le chiamate manuali (Bruno)

## Contesto

user-service e content-service pubblicano ora un contratto OpenAPI e una collection
Bruno nel proprio repo (ADR-0014 in `one-piece-user-service`), da usare sia in locale sia
sull'ambiente `remote`. oauth2-proxy (ADR-0001) accettava solo il cookie di sessione:
una richiesta con `Authorization: Bearer` veniva rediretta al login. Per chiamare le API
da un client non-browser restavano due strade: il `kubectl port-forward` diretto al
servizio (solo locale) oppure il riuso del client confidenziale `onepiece-proxy` e del
suo secret (sconsigliato, e impossibile in remoto, dove il secret non è noto).

## Decisione

- **Client Keycloak pubblico `bruno`** in `keycloak/realm-onepiece.json`: authorization
  code + PKCE S256, senza secret e senza direct access grant. Il redirect URI è fisso
  (`http://127.0.0.1/bruno/callback`): Bruno intercetta il redirect da sé, quindi lo
  stesso valore vale per ogni ambiente e non serve un hook `remote` come per
  `onepiece-proxy`. Due mapper sull'access token: l'audience `onepiece-proxy` (verificata
  da oauth2-proxy) e `sub`, che i servizi usano per identificare il chiamante. Questo realm
  non ha lo scope `basic` di Keycloak 25+, che di solito lo aggiunge. Il flusso browser non
  ne risente perché oauth2-proxy inoltra l'ID token, che contiene sempre `sub`.
- **`skip-jwt-bearer-tokens: "true"`** su oauth2-proxy: una richiesta con un bearer JWT
  valido passa senza cookie. oauth2-proxy ne verifica firma (`oidc-jwks-url`), issuer e
  audience (il suo client-id, `onepiece-proxy`); con `pass-authorization-header`
  l'header arriva invariato ai servizi, che lo rivalidano come resource server.
- I permessi non cambiano: i servizi li leggono da `resource_access.onepiece-proxy.roles`
  qualunque sia il client che ha emesso il token.

## Alternative considerate

- **Solo `kubectl port-forward` verso i servizi**: nessuna modifica alla sicurezza, ma in
  `remote` richiede l'accesso al cluster (kubeconfig OCI), e ogni servizio ha la sua porta
  e il suo URL.
- **Riusare `onepiece-proxy` in Bruno**: mette un secret confidenziale in un client
  desktop, e in `remote` quel secret non è disponibile.
- **Ingress separato per le API senza oauth2-proxy**: seconda superficie pubblica da
  mantenere, per lo stesso risultato.

## Conseguenze

- Si accetta un bearer valido per questo realm e per questa app, non più solo il cookie.
  I token che non vengono dal realm `onepiece` o non hanno audience `onepiece-proxy`
  restano respinti da oauth2-proxy, e i servizi li rivalidano comunque.
- Chiunque abbia credenziali utente valide può chiamare le API da Bruno esattamente come
  dal browser: stessi utenti, stessi permessi, nessun privilegio aggiuntivo.
- Il nuovo client arriva sui cluster già avviati tramite keycloak-config-cli (ADR-0011).
