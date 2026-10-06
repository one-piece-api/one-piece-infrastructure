# ADR-0021: HTTPS con cert-manager, Let's Encrypt e verifica DNS-01

## Contesto

Con Cloudflare davanti (ADR-0020) la connessione ha due tratti. Visitatore → Cloudflare
usa il certificato edge di Cloudflare (Universal SSL, automatico). Cloudflare → origin
deve restare cifrato con un certificato valido, modalità **Full (strict)**, come chiede
`implementation-plan-public-api.md` §3. Il dominio `.dev` è nella lista HSTS preload: i
browser lo aprono solo in HTTPS. L'origin accetta solo Cloudflare, quindi una verifica
che richieda connessioni in ingresso da Let's Encrypt è da evitare.

## Decisione

- **cert-manager** nel cluster, solo nell'ambiente `remote` (locale e CI non hanno
  dominio).
- **Let's Encrypt** come autorità, con `ClusterIssuer` staging per la messa a punto e
  production a regime.
- **Verifica DNS-01 su Cloudflare**: cert-manager prova il possesso del dominio
  scrivendo un record TXT temporaneo tramite un token API con i soli permessi Zone Read
  + DNS Edit sulla zona `onepieceapi.dev`. Non serve traffico in ingresso, e il
  certificato può essere wildcard.
- **Un certificato** per `onepieceapi.dev` + `*.onepieceapi.dev`, referenziato dal
  listener HTTPS del `Gateway` (ADR-0019), rinnovato in automatico.
- **Token**: secret GitHub Actions `CLOUDFLARE_DNS_API_TOKEN` → Secret Kubernetes nel
  namespace di cert-manager, creato da uno script presync. È lo stesso schema di
  `RESEND_API_KEY`; External Secrets Operator non è ancora in uso.
- Modalità SSL **Full (strict)** e "Always Use HTTPS" impostate su Cloudflare via
  Terraform (ADR-0020).

## Alternative considerate

- **Certificato Origin CA di Cloudflare**: gratis, fino a 15 anni, niente componenti nel
  cluster; ma valido solo per Cloudflare (inutilizzabile con un record non proxied o con
  un'altra CDN) e da caricare a mano.
- **Verifica HTTP-01**: nessun token, ma richiede che Let's Encrypt raggiunga il
  cluster e non permette certificati wildcard.
- **Modalità SSL Flexible** (Cloudflare → origin in HTTP): nessun certificato
  sull'origin, ma il secondo tratto viaggia in chiaro.

## Conseguenze

- Tre pod in più (controller, webhook, cainjector) con requests ridotte per Always Free.
- Un nuovo segreto da custodire, con permessi minimi sulla sola zona del progetto.
- L'origin presenta un certificato pubblicamente valido: togliere Cloudflare o un
  record non proxied non rompe HTTPS.
- Supera, insieme ad ADR-0020, la sezione "TLS/DNS: nessun dominio per ora" di
  ADR-0005.
