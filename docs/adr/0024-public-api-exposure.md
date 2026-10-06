# ADR-0024: Esposizione pubblica dell'API su `api.onepieceapi.dev`

## Contesto

L'API pubblica (`one-piece-public-api`, step P1–P5 di `implementation-plan-public-api.md`)
gira nel cluster senza rotta esterna. Il track dominio/HTTPS (ADR-0019…0023) ha messo il
remoto dietro Cloudflare. Mancano: la rotta pubblica, la protezione dagli abusi, la cache
CDN che risparmia il Load Balancer da 10 Mbps, HSTS, e un modo per i test e2e di passare
dal gateway in CI, dove non c'è dominio. La capacità misurata nello step P5 è di circa
60–65 req/s per replica, limitata dal PostgreSQL condiviso.

## Decisione

- **Host dedicato**: l'API risponde su `https://api.onepieceapi.dev/v1`, senza prefisso né
  riscrittura (il servizio espone già `/v1…`); il dominio principale rimanda a `/v1`
  (302). Il prefisso `/api/public/` previsto dalla D10 originale è abbandonato.
- **Stessa rotta in ogni ambiente**: release `api-route` con l'host da configurazione,
  `api.onepieceapi.dev` in `remote` e `api.localhost` in locale/CI. I test e2e la usano
  con `Host: api.localhost`, attraverso un port-forward al Service di Envoy.
- **Limite per IP su Cloudflare**: regola di rate limiting su `api.`, 100 richieste ogni
  10 s per IP (piano gratuito: una regola, finestra di 10 s), in Terraform. L'abuso si
  ferma prima del Load Balancer.
- **Tetto complessivo su Envoy**: limite locale di 50 req/s sulla rotta `api.`
  (`BackendTrafficPolicy`), sotto la capacità misurata: paratia che protegge il
  PostgreSQL condiviso, e con lui Keycloak e il back-office, anche da traffico distribuito
  su molti IP.
- **Cache CDN**: Cache Rule su `api.` che rende le risposte ammesse in cache (i percorsi
  dell'API non hanno estensione, Cloudflare li salterebbe) con durata in CDN e nel
  browser presa dal `Cache-Control` del servizio. La politica di cache resta solo nel
  servizio (D13); nessuno svuotamento della cache a comando (D14).
- **HSTS su Cloudflare** per tutto il dominio: 1 anno, `includeSubDomains`, senza
  `preload` (il TLD `.dev` è già nella lista preload dei browser).

## Alternative considerate

- **Limite per IP su Envoy (modalità globale)**: controllo completo nel cluster, ma due
  componenti in più (servizio di rate limit + Redis) sul budget Always Free, e il
  traffico abusivo consuma comunque la banda del Load Balancer.
- **Limite per IP in public-api** (es. Bucket4j): Problem Details e `Retry-After` esatti,
  ma il traffico arriva fino all'applicazione, ogni replica conta per conto suo e il
  limite esce dal gateway (contro la D11).
- **Durata della cache fissata su Cloudflare**: la politica si sdoppierebbe tra servizio
  e CDN, e una durata unica non distingue `200`, `404` e `301`.
- **Rotta `/api/public/` con riscrittura solo in locale/CI**: i test verificherebbero una
  rotta diversa da quella del remoto.
- **e2e direttamente sul Service di public-api**: più semplice, ma salta gateway e tetto.

## Conseguenze

- La risposta `429` per IP ha un corpo nella forma Problem Details (`errorCode`
  `RATE_LIMITED`), ma senza `traceId`/`timestamp` e con `Content-Type:
  application/json`: Cloudflare non accetta `application/problem+json` per le risposte
  personalizzate. Cloudflare aggiunge da sé `Retry-After` (secondi alla fine del
  blocco) e `Cache-Control: no-store`: verificato nel QA dello step P6 (2026-10-06).
- Il tetto di Envoy è unico per la rotta: un singolo client entro il suo limite per IP
  può comunque contribuire a raggiungerlo. Va ritarato se le repliche o la capacità del
  database cambiano.
- Cloudflare, cache e HSTS restano fuori dalla CI: li copre il QA sul remoto.
- Supera la D10 originale (prefisso `/api/public/`) e corregge l'ADR-0019 sul limite per IP.
