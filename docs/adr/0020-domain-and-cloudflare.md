# ADR-0020: Dominio `onepieceapi.dev` dietro Cloudflare

## Contesto

Il 2026-10-06 è stato acquistato `onepieceapi.dev` su Cloudflare Registrar, che impone
il DNS su Cloudflare. Il nome serve a rendere l'API pubblica riconoscibile come
riferimento per One Piece. Oggi l'ambiente remoto risponde solo su IP, in HTTP, e solo
dall'IP del proprietario (`allowed_client_cidr`, ADR-0005). Il Load Balancer Always Free
è fisso a 10 Mbps: troppo poco per traffico pubblico senza una CDN davanti.

## Decisione

- **Un sottodominio per pubblico**:
  - `api.onepieceapi.dev` → public-api (aperto a tutti);
  - `app.onepieceapi.dev` → oauth2-proxy (frontend + API del back-office);
  - `auth.onepieceapi.dev` → Keycloak;
  - `onepieceapi.dev` → redirect verso `api.` (in futuro vetrina e documentazione).
  - Nessun prefisso `dev.`: il remoto è l'unico ambiente ed è quello che pubblica
    l'API. Una futura produzione sposterebbe lo sviluppo su `*.dev.onepieceapi.dev`.
- **Tutti i record proxied da Cloudflare** (CDN, protezione, IP di origine nascosto).
- **Origin aperto solo a Cloudflare**: nella security list OCI, 80/443 accettano solo
  gli intervalli IP pubblicati da Cloudflare, al posto dell'IP del proprietario.
- **Regola custom su Cloudflare**: `app.` e `auth.` raggiungibili solo dall'IP del
  proprietario (stessa esposizione di oggi: console admin e utenti seed hanno password
  note, ambiente dev); `api.` e dominio principale aperti.
- **IP reale del client** da `CF-Connecting-IP`. È affidabile perché l'origin non è
  raggiungibile se non attraverso Cloudflare: la fiducia è garantita dalla rete, dato che
  il Load Balancer OCI non conserva l'indirizzo sorgente di Cloudflare.
- **Cloudflare come codice**: provider Terraform ufficiale nel modulo `terraform/`
  esistente (record DNS, modalità SSL, regola custom, record email, Email Routing),
  applicato a mano come OCI. Lo stesso provider fornisce gli intervalli IP di Cloudflare
  alla security list: nessun elenco copiato a mano.
- **Redirect del dominio principale** fatto dal gateway (`HTTPRoute`, filtro di
  redirect), non da una regola Cloudflare: resta insieme al resto del routing.

## Alternative considerate

- **Un solo host con routing per percorso** (come oggi): più semplice, ma cookie di
  login e API pubblica sullo stesso host, e cache e limiti diventano regole per percorso.
- **Solo `api.` proxied, gli altri diretti**: l'origin resta aperto a tutti, l'IP OCI è
  visibile e Cloudflare aggirabile.
- **Configurazione Cloudflare dalla dashboard**: più rapida all'inizio, ma non
  riproducibile né versionata, contro l'approccio scelto per OCI (ADR-0005).

## Conseguenze

- Ogni `terraform apply` richiede anche il token Cloudflare (owner, in locale).
- Se l'IP del proprietario cambia, si aggiorna la variabile e si rilancia Terraform: la
  regola ora vive su Cloudflare, non nella security list.
- Il certificato edge gratuito di Cloudflare copre solo il primo livello: un futuro
  `*.dev.onepieceapi.dev` richiede di rivedere la scelta.
- Il back-office resta privato finché la regola custom non viene rimossa, decisione
  rimandata a quando ci saranno altri redattori.
- Supera la sezione "TLS/DNS: nessun dominio per ora" di ADR-0005, insieme ad ADR-0021.
