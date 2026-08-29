# ADR-0009: Session storage di oauth2-proxy su Redis invece che su cookie

## Contesto

Dal refactor del frontend (`one-piece-user-frontend`), alcune pagine
sparano più richieste HTTP in parallelo all'apertura (es. la vista
dettaglio utente, che carica contemporaneamente l'utente e il registro
ruoli via due `httpResource` indipendenti). Con il session storage di
default di oauth2-proxy (`sessionStorage.type: cookie`), l'intera sessione
- incluso il refresh token OIDC - vive cifrata nel cookie del browser:
non esiste alcuno stato condiviso lato server su cui richieste concorrenti
possano sincronizzarsi.

Il realm Keycloak ha `revokeRefreshToken: true` e
`refreshTokenMaxReuse: 0` (`keycloak/realm-onepiece.json`): ogni refresh
token è utilizzabile una sola volta. Quando l'access token scade (ogni
`accessTokenLifespan: 300`, 5 minuti) mentre più richieste sono in volo,
ciascuna tenta indipendentemente il redeem dello stesso refresh token
contro Keycloak: la prima riesce, le altre ricevono `invalid_grant` da
Keycloak e quindi un 401 da oauth2-proxy - anche se la sessione, nel suo
complesso, è perfettamente valida. Il frontend (`error-interceptor.ts`)
tratta quel 401 come sessione scaduta e manda l'utente sull'interstitial
`/session-expired`, che dopo un breve delay reindirizza a Keycloak: siccome
la sessione SSO è ancora viva (`ssoSessionIdleTimeout: 1800`), l'utente
viene riautenticato in automatico e riportato dove si trovava - un flash
di pagina percepito come comportamento erratico, non un vero timeout di
sessione.

## Decisione

Il session storage di oauth2-proxy passa da `cookie` a `redis`
(`sessionStorage.type: redis` in `oauth2-proxy/values-oauth2-proxy.yaml`,
supportato nativamente dal chart già in uso, versione 10.7.0 - nessun
flag custom). Il cookie nel browser diventa un ticket opaco; i token
vivono lato server in Redis, indicizzati da quel ticket. Questo dà a
oauth2-proxy uno stato condiviso su cui serializzare il refresh: quando
l'access token è scaduto, la prima richiesta esegue il redeem e aggiorna
la sessione in Redis; le richieste concorrenti trovano il refresh già in
corso e attendono il risultato invece di ripetere ciascuna il proprio
redeem con lo stesso refresh token - eliminando la causa della race, non
solo il suo sintomo lato frontend.

Redis è una singola istanza locale (`helm/charts/redis`, micro-chart che
usa direttamente l'immagine ufficiale `docker.io/library/redis`, stesso
pattern già adottato per PostgreSQL in ADR-0001) nel namespace `auth`,
senza persistenza: perdere le sessioni cache a un riavvio del pod
significa solo dover rifare il login, non una perdita di dati
applicativi, quindi non giustifica una PersistentVolumeClaim.

## Alternative considerate

- **Retry lato frontend sul primo 401**: costo di implementazione minimo,
  nessun nuovo componente infrastrutturale. Scartata come soluzione
  principale perché è un cerotto sul sintomo (il singolo client che lo
  implementa smette di mostrare il problema, ma la race lato oauth2-proxy/
  Keycloak resta) invece che sulla causa, e non protegge eventuali altri
  consumer futuri (altri frontend, script, integrazioni) che non
  implementino lo stesso retry.
- **Alzare `refreshTokenMaxReuse` da 0 a un valore piccolo**: cambio di
  configurazione minimo, ma indebolisce deliberatamente il rilevamento di
  replay del refresh token che la rotazione con riuso zero fornisce (OAuth
  2.0 Security Best Current Practice) - tollera allo stesso modo sia la
  race legittima sia un refresh token effettivamente rubato e rigiocato.
  Scartata per non allentare una protezione di sicurezza per assorbire un
  problema di concorrenza infrastrutturale.
- **Subchart `redis-ha` fornito da oauth2-proxy stesso**: eviterebbe di
  scrivere un chart proprio, ma introduce un chart di terze parti pensato
  per l'alta affidabilità (Sentinel, più repliche) non necessaria per
  un'istanza locale singola - stesso ragionamento con cui ADR-0001 aveva
  scartato un Operator per PostgreSQL.

## Conseguenze

- Nuovo componente infrastrutturale da gestire (`auth/redis`, needs di
  `auth/oauth2-proxy` in `helmfile.yaml.gotmpl`): se Redis non è
  raggiungibile, nessuno può autenticarsi - un single point of failure che
  prima non esisteva (le sessioni cookie-only non dipendevano da alcun
  servizio esterno). Accettabile per le dimensioni del progetto; da
  rivalutare se lo stack viene esposto oltre l'uso locale/dev.
- Overhead di latenza minimo ma non nullo su ogni richiesta autenticata
  (lookup in Redis invece di decifrare il cookie localmente) e, nella
  finestra di scadenza dell'access token, un'attesa bloccante pari al
  tempo di un round-trip verso l'endpoint token di Keycloak per le
  richieste che arrivano mentre il refresh è già in corso - nettamente più
  breve e invisibile all'utente rispetto al comportamento precedente
  (redirect visibile su `/session-expired` più round-trip completo
  attraverso Keycloak).
- La rotazione dei refresh token (`revokeRefreshToken`,
  `refreshTokenMaxReuse: 0`) resta invariata: la protezione di sicurezza
  non viene toccata per risolvere questo problema.
- Nessun test automatico riproduce deliberatamente la race originale (richiede
  concorrenza precisa sulla finestra di scadenza dei 5 minuti dell'access
  token, impraticabile in uno smoke test rapido); lo smoke test end-to-end
  esistente (`scripts/02-smoke-test.sh`, eseguito anche in CI) resta la
  rete di sicurezza contro regressioni sul flow di login/sessione con il
  nuovo backend Redis.
