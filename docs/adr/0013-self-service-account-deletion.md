# ADR-0013: Cancellazione self-service dell'account, senza codice backend

## Contesto

Serviva dare agli utenti la possibilita' di cancellare il proprio account
(GDPR art. 17, diritto alla cancellazione). Il pattern gia' stabilito nel
progetto per azioni self-service distruttive (Change Password, Enable/Disable
OTP - vedi `docs/implementation-plan.md`, Step 8-9) e' "hosted, non custom":
mai una chiamata backend con credenziali Admin API per agire per conto
dell'utente autenticato, sempre le Application Initiated Actions (`kc_action`)
di Keycloak. Quel pattern pero' era documentato solo come design, mai
effettivamente implementato in questo checkout (nessun `AccountSelfServicePort`,
nessun `grantAccountViewProfileRole`, nessuna ADR di supporto in
`one-piece-user-service`) - verificato a fondo prima di questa decisione,
perche' cambia quanto ci si puo' fidare del pattern citato.

Il meccanismo che la documentazione presupponeva - redirect tramite il flow
OIDC dell'app (`onepiece-proxy`, dietro oauth2-proxy) - si e' rivelato
inaffidabile: oauth2-proxy possiede lo `state`/CSRF di quel flow, non
documenta un modo per inoltrare un `kc_action` custom fino a Keycloak, e con
una sessione oauth2-proxy gia' valida potrebbe non contattare affatto
Keycloak. La citazione originale del design (CVE-2023-3597, come motivo per
evitare un `DELETE` backend) verificata direttamente: riguarda un bypass
dello step-up authentication di Keycloak, non e' in realta' pertinente alla
scelta fra backend e hosted qui.

## Decisione

Redirect diretto all'endpoint di autorizzazione del client Keycloak
**built-in "account"** (non `onepiece-proxy`, non tramite oauth2-proxy) con
`kc_action=delete_account`. Il browser porta gia' il cookie di sessione SSO
di Keycloak (separato da quello di oauth2-proxy) dal login iniziale, quindi
non serve un secondo login: Keycloak riconosce la sessione, ma per
`delete_account` richiede comunque una re-autenticazione fresca (step-up
nativo di Keycloak per questa azione, verificato empiricamente contro il
cluster locale) prima di mostrare la propria pagina di conferma. Keycloak
esegue l'intera cancellazione sulla propria pagina hosted; `user-service` non
e' mai coinvolto.

Il ruolo built-in `delete-account` del client `account` (mai dichiarato
prima in `realm-onepiece.json`, solo auto-creato da Keycloak) e' concesso
esplicitamente a ogni ruolo prodotto (`ADMIN`, `REVIEWER`, `EDITOR`) come
composite client-role, stesso meccanismo dichiarativo gia' in uso per
`roles:manage` (Step 21). **Non** concesso tramite `default-roles-onepiece`:
quel composite resta deliberatamente vuoto per ADR-0012, proprio per evitare
concessioni implicite a ogni utente - i composite per-ruolo, espliciti, sono
il pattern gia' stabilito li'. Nessun backfill necessario per gli utenti
esistenti: i composite sono valutati dinamicamente da Keycloak, e la
riconciliazione di `keycloak-config-cli` (ADR-0011) si applica ai ruoli gia'
assegnati al prossimo sync.

La required action `delete_account` (gia' registrata da Keycloak per
default, solo disabilitata) viene abilitata con una singola entry
nell'array `requiredActions` di `realm-onepiece.json` - verificato
empiricamente che `keycloak-config-cli` fa merge, non replace, di
quell'array: ogni altra required action mantiene il proprio stato invariato
dopo il sync.

Nessun evento di audit per l'azione di cancellazione stessa: Keycloak non da'
a `user-service` alcun callback per osservarla (stesso limite gia' accettato
per Change Password/OTP), e - a differenza di quel caso - qui non e' nemmeno
un limite da compensare: la cancellazione di un account e' un evento di
lifecycle dell'identita' con un equivalente diretto in Keycloak stesso, per
cui non e' dato applicativo secondo lo stesso confine gia' tracciato da
ADR-0001 ("audit metadata e' dato applicativo senza equivalente
nell'identity provider" - qui l'equivalente c'e', quindi non e' audit
applicativo).

**Nessuna modale di conferma lato app** (revisione dopo il primo giro di
review manuale): la prima versione aggiungeva una modale in "Mio Profilo"
con un secondo passaggio di conferma (digitare la propria email). Rimossa -
Keycloak richiede gia' una re-autenticazione fresca *e* un proprio passo
esplicito Conferma/Annulla sulla propria pagina hosted: un'ulteriore
conferma lato app sarebbe ridondante, non un secondo livello di sicurezza
reale. Il link "Elimina il mio account" in "Mio Profilo" ora punta
direttamente all'URL Keycloak (nessun `(click)`, nessuno stato applicativo).

**Tre correzioni al tema Keycloak** (`one-piece-keycloak-theme`), tutte
CSS/messaggi, coerenti con ADR-0010 (nessun `.ftl`):
- `restartLoginTooltip` in `messages_it.properties` usava un apostrofo
  singolo non escapato (`Ricomincia l'accesso` invece di
  `Ricomincia l''accesso`) - Keycloak usa `MessageFormat`, che tratta un
  apostrofo singolo come delimitatore di quoting e lo inghiotte insieme al
  testo seguente, rendendo `Ricomincia laccesso`. Bug preesistente nel tema,
  scoperto e corretto qui.
- Il messaggio generico di re-autenticazione (chiave `reauthenticate`,
  condivisa da Keycloak per qualunque azione a step-up, non solo
  `delete_account`) e' stato reso piu' chiaro
  ("Reinserisci la password per confermare questa azione" /
  "Re-enter your password to confirm this action") invece del testo
  ereditato dal tema base ("Effettuare nuovamente l'autenticazione per
  continuare"). Restare generico (non nominare "cancellazione") e' stata una
  scelta esplicita: renderlo specifico per azione richiederebbe un
  override `.ftl`, la prima eccezione al principio di ADR-0010 - scartata.
- L'icona di warning sulla pagina di conferma cancellazione
  (`delete-account-confirm.ftl`, tema base) usa una classe glyph
  (`.pficon-warning-triangle-o`) che questo tema non carica mai (niente
  FontAwesome/PatternFly, vedi header di `onepiece.css`), quindi renderizzava
  vuota. Disegnata in puro CSS (`clip-path` piu' uno pseudo-elemento "!"),
  scoperto lo `href` reale della pagina renderizzata (markup PatternFly 4,
  non PatternFly 5/`keycloak.v2` come inizialmente ipotizzato leggendo solo i
  `.ftl` senza verificare live) tramite ispezione diretta del DOM.

**Bug di specificita' CSS sui due bottoni della pagina di conferma**
(scoperto da segnalazione utente: "i bottoni reagiscono diversamente
all'hover"): il bottone "Annulla" e' comunque `type="submit"` (deve POSTare
`cancel-aia`), quindi il selettore generico `input[type="submit"],
button[type="submit"]` (specificita' 0,1,1 - un selettore di tipo piu' un
attributo) batteva `.btn-default` (specificita' 0,1,0, un solo selettore di
classe) a riposo nonostante quest'ultimo comparisse dopo nel file - un
bottone "secondario" restava dorato/primario finche' non veniva "salvato"
solo in hover da `.btn-default:hover` (specificita' piu' alta grazie alla
pseudo-classe), risultando in un lampo oro→bianco invece di una transizione
coerente, e senza alcuna animazione di pressione (solo `.pf-m-primary:active`
esisteva). Corretto escludendo esplicitamente `.btn-default`/`.pf-m-default`
dal selettore generico (`:not(.btn-default):not(.pf-m-default)`) e dando al
bottone default il proprio stato `:active` in tinta neutra, cosi' entrambi
i bottoni hanno una risposta hover/pressione coerente, solo in palette
diversa (oro per l'azione primaria, bianco/bordo per quella secondaria).

**Link "Password dimenticata?" nascosto sulla pagina di ri-autenticazione**
(altra segnalazione utente: "clicco e non succede niente"): verificato dal
vivo che il link naviga davvero (`login-actions/reset-credentials`) ma
Keycloak si limita a ri-renderizzare la stessa schermata password invece del
modulo di reset - comportamento di Keycloak in questo contesto specifico
(ri-autenticazione infra-flusso, non login dall'inizio), non risolvibile via
CSS/messaggi. Nascosto invece di lasciare un'azione che sembra funzionare ma
non fa nulla, scoped con `body:has(#kc-attempted-username)` - quella label
compare solo quando Keycloak conosce gia' lo username e chiede di
riprovarlo (`auth.showUsername()`), mai sul login combinato normale, quindi
non puo' nascondere per errore un "password dimenticata" funzionante
altrove. Verificato che il markup reale (`.login-pf-settings a`) differisce
da quello ipotizzabile leggendo `login-password.ftl` dal jar del tema -
Keycloak risolve qui una variante di template diversa da quella attesa,
scoperta solo tramite ispezione diretta del DOM (stessa lezione del punto
sopra sull'icona di warning: non fidarsi della sola lettura dei `.ftl`).

**`redirect_uri` punta all'app, non alla Account Console di Keycloak**
(revisione successiva): la prima versione usava `${keycloakOrigin}/realms/onepiece/account/`
come `redirect_uri` - innocuo per il percorso di successo (nessuna sessione
sopravvive a una cancellazione riuscita, quindi Keycloak mostra comunque una
propria pagina statica "fatto", non un vero redirect), ma per il percorso
"Annulla" (l'utente ripensa alla cancellazione, l'account resta vivo)
significava atterrare sulla dashboard self-service di Keycloak - esattamente
cio' che questa stessa ADR aveva gia' escluso altrove (vedi "Alternative
considerate"). Corretto dichiarando esplicitamente il client `account` in
`realm-onepiece.json` (altrimenti implicito/auto-creato) con
`http://localhost:4180/*` aggiunto a `redirectUris`, e cambiando
`deleteAccountUrl()` per puntare li'. Verificato live: "Annulla" ora
atterra sull'app (`kc_action_status=cancelled` nella query string, mai
consumata dall'app). Sulla pagina statica di successo ("Rimozione
dell'utente riuscita") il link "Torna all'app" atterrava invece
sull'Account Console di Keycloak (segnalato dall'utente, non colto nella
verifica iniziale): nessuna sessione sopravvive a una cancellazione
riuscita per completare un vero redirect OAuth verso `redirect_uri`, quindi
quella pagina non e' un `.ftl` nostro ma il template base `info.ftl`, che
in questo caso usa `client.baseUrl` del client che ha avviato l'azione
(`account`) come link di fallback - e quel client, ridichiarato qui solo
per estendere `redirectUris`, aveva ancora il `baseUrl` di default di
Keycloak (`/realms/onepiece/account/`, mai cambiato). Corretto impostando
`baseUrl` sull'origine dell'app (`http://localhost:4180/` nel JSON,
`http://$OCI_LB_IP/` su `remote` via `configure-remote-redirect-uris.sh`,
stesso motivo per cui gia' patcha `redirectUris` li') - nessun override
`.ftl` necessario, il template base gia' supporta questo caso. Verificato
localmente ricreando il flusso con un utente usa-e-getta: il link ora porta
dritto all'app.

**Nessun link "torna all'app" sulla pagina di ri-autenticazione** (prima
del passo Conferma/Annulla): quella pagina (`login-password.ftl`, tema
base) e' generica - Keycloak la riusa per qualunque step-up, non solo
`delete_account` - e non ha alcun meccanismo di cancellazione integrato
(niente `cancel-aia`, solo "Ricomincia l'accesso", che riavvia il login,
non torna all'app). Aggiungerlo richiederebbe un override `.ftl` di quel
template, la stessa eccezione ad ADR-0010 gia' scartata per il messaggio di
ri-autenticazione. Decisione esplicita: si accetta il limite - il tasto
"indietro" del browser resta la via d'uscita da quella pagina intermedia.

**Nota operativa**: le risorse statiche del tema (CSS) vengono servite da
Keycloak con `Cache-Control: max-age=2592000` (30 giorni, comportamento di
default in modalita' produzione). Dopo una modifica al tema, un browser che
ha gia' visitato una pagina Keycloak in precedenza non vede il CSS
aggiornato finche' non fa un hard-refresh (o i 30 giorni scadono) - scoperto
durante la verifica manuale del fix dell'icona qui sopra, non un bug del
tema ma un comportamento di Keycloak da tenere presente durante lo sviluppo
locale.

## Alternative considerate

- **Endpoint backend `DELETE /api/me`** che cancella l'utente via Admin API
  sul proprio userId (risolto dal JWT validato, mai passato dal client):
  scartata - si discosta dal principio "mai Admin API per self-service" gia'
  stabilito nel progetto per questa classe di azioni, ed e' stata
  riconsiderata solo perche' il percorso oauth2-proxy sembrava inizialmente
  rotto. Avrebbe pero' permesso un vero audit event.
- **Redirect tramite il client `onepiece-proxy`** (dietro oauth2-proxy),
  come la documentazione originale presupponeva: scartata - conflitto sullo
  `state`/CSRF di oauth2-proxy, nessun `kc_action` passthrough documentato
  (vedi Contesto).
- **Reindirizzare alla Account Console completa di Keycloak** (dashboard
  multi-tab): scartata - il progetto ha gia' escluso di mostrare all'utente
  finale l'interfaccia self-service nativa di Keycloak, preferendo pagine
  singole e mirate per una sola azione.

**La sessione oauth2-proxy resta valida dopo una cancellazione riuscita**
(bug segnalato dall'utente: "se vado sull'app riesco ancora a navigare come
l'utente appena cancellato"). Causa: la sessione di `oauth2-proxy` (un
cookie separato dalla sessione SSO di Keycloak) non viene mai toccata da
questo flusso, e il suo access token gia' emesso resta valido - `SecurityConfig`
in `one-piece-user-service` valida i JWT solo per firma/scadenza, senza
controllo di revoca per-richiesta (stesso limite gia' accettato per UF-IDU-13,
la revoca admin) - fino alla sua scadenza naturale (`accessTokenLifespan`,
~5 minuti). Un fix "reattivo" (reagire al redirect di ritorno su
`redirect_uri`) non basta: su cancellazione **riuscita** Keycloak mostra una
propria pagina statica di successo e non esegue affatto un redirect OAuth
verso `redirect_uri` (vedi il limite residuo qui sopra) - quindi non c'e'
alcun momento affidabile in cui l'app possa intercettare l'esito per pulire
la sessione dopo il fatto. Risolto invece incatenando `/oauth2/sign_out`
*prima* di raggiungere Keycloak (`startAccountDeletionUrl()` in
`auth-urls.ts`, stesso meccanismo gia' usato da `logoutUrl()`): pulisce la
sessione oauth2-proxy immediatamente e incondizionatamente, prima ancora
che l'utente veda la pagina di ri-autenticazione - corretto sia che l'utente
confermi, sia che annulli, sia che abbandoni il flusso. Un annullamento non
costa un secondo login manuale: la sessione SSO di Keycloak resta viva, quindi
la richiesta successiva la ri-autentica in modo invisibile.

## Conseguenze

- Zero codice nuovo in `user-service`: l'intera funzionalita' e' realm-config
  (`realm-onepiece.json`) piu' un redirect nel frontend.
- Nessun record di audit per la cancellazione account, per scelta
  architetturale esplicita, non per limite tecnico da compensare in futuro.
- Un utente che cancella il proprio account puo' re-invitare/re-registrare la
  stessa email in seguito senza conflitti: verificato empiricamente contro il
  cluster locale.
- Se in futuro serve un audit trail dell'evento di cancellazione, l'unica via
  e' un Keycloak Event Listener SPI (osservare l'evento `DELETE_ACCOUNT` lato
  Keycloak) - non un `DELETE` backend, che riaprirebbe la scelta scartata
  sopra.
