# ADR-0026: Client `ai-editor` con service account per l'AI editor

## Contesto

Il proprietario vuole chiedere a Claude, in una sessione locale di Claude Code, di caricare contenuti
editoriali (es. "carica la prima saga") sul remoto: Claude scrive le bozze e le invia in revisione, il
proprietario le revisiona e pubblica dal back-office. Serve un'identità con cui Claude chiami l'API
editoriale senza la password di un umano e senza login dal browser. oauth2-proxy accetta già un bearer
JWT del realm con audience `onepiece-proxy` (ADR-0017); content-service legge i permessi da
`resource_access.onepiece-proxy.roles` e l'utente da `sub`, `preferred_username` ed `email`
(`author_email` e `actor_email` sono `NOT NULL`). Piano: `../docs/implementation-plan-ai-editor/`.

## Decisione

- **Client confidenziale `ai-editor`** in `realm-onepiece.json`, solo service account (OAuth 2.0 client
  credentials, RFC 6749 §4.4), ogni altro flusso disattivato. Secret `$(env:AI_EDITOR_CLIENT_SECRET)` dal
  registro delle credenziali (ADR-0025, Vault `onepiece-ai-editor-client-secret`).
- **Permessi per ruolo, non per prompt**: l'utente `service-account-ai-editor` ha solo il ruolo realm
  `EDITOR` (`content:read`, `content:write`). Il flusso editoriale vieta già all'autore di decidere sulle
  proprie versioni: l'AI non può approvare né pubblicare.
- **Nome visibile `ai-editor`**: mapper hardcoded sul client `preferred_username = ai-editor`; il client
  non ha lo scope `profile`, così nessun altro mapper scrive quel claim. Email
  `ai-editor@onepieceapi.dev` sull'utente del service account. Mapper `sub` e audience `onepiece-proxy`
  come per `bruno`.
- **Secret sulla macchina del proprietario** fuori da ogni repo: `~/.config/onepiece/ai-editor.<env>.env`.
- **Test**: `scripts/06-ai-editor-client-test.sh` (anche in CI) verifica token, claim e accettazione del
  bearer da parte di oauth2-proxy.

## Alternative considerate

- **Utente reale + device authorization grant (RFC 8628)**: nessun secret persistente, ma ogni sessione
  richiede l'approvazione del proprietario dal browser.
- **Utente reale + password grant**: deprecato in OAuth 2.1, password riutilizzabile in un file.
- **Nome nativo `service-account-ai-editor` senza mapper**: nessuna personalizzazione, ma nome tecnico
  nella UI e negli audit log.
- **Riusare `bruno`**: richiede un login interattivo; e non distingue il lavoro dell'AI da quello umano.

## Conseguenze

- Ogni bozza e ogni voce di audit dell'AI riporta `ai-editor`; la console e gli eventi di Keycloak
  mostrano `service-account-ai-editor`. Il collegamento tra i due è `sub`.
- `ai-editor` è uno username riservato: non invitare un umano con quel nome (Keycloak non lo impedisce,
  e la UI non distinguerebbe i due).
- Revoca immediata: disattivare il client o rigenerarne il secret.
- Il token non contiene `email_verified` (lo scope `email` del realm mappa solo `email`): oauth2-proxy
  accetta comunque il bearer, verificato dal test.
- Il ruolo `EDITOR` porta anche `account/delete-account` (composite del realm): irrilevante per un
  service account, che non usa l'Account Console.
- Il client esiste anche in locale e in CI, con il secret placeholder.
