# ADR-0003: Namespace applicativo e primi servizi reali dietro oauth2-proxy

## Contesto

ADR-0001 aveva deliberatamente introdotto lo stack di identity (kind +
Keycloak + oauth2-proxy) **senza** UserService/frontend reali, usando
`traefik/whoami` come upstream temporaneo solo per validare il flow
Authorization Code + PKCE. Con l'inizio della Fase 0 del piano di
implementazione (`docs/implementation-plan.md` nel repo `one-piece-api`),
quei servizi reali esistono ora e whoami ha esaurito il suo scopo.

## Decisione

### Namespace "app", separato da "auth"

I servizi di dominio vivono in un nuovo namespace `app`, distinto da
`auth` (identity provider). Stessa motivazione di separazione già
implicita in ADR-0001: `auth` resta infrastruttura trasversale,
riutilizzabile indipendentemente dal dominio applicativo.

### Repository separati, chart Helm centralizzati

Backend (`one-piece-api/one-piece-user-service`, Spring Boot) e frontend
(`one-piece-api/one-piece-user-frontend`, Angular) vivono in repository
propri (multi-repo, non monorepo — preferenza di progetto), ma i loro
manifest di deploy restano in questo repo infrastrutturale
(`helm/charts/user-service`, `helm/charts/user-frontend`), non nei
rispettivi repo applicativi: stessa convenzione già in uso per whoami, e
coerente con il fatto che `helmfile.yaml` (qui) è l'unico punto che
orchestra l'intero stack. Le immagini, per ora, sono costruite localmente
e caricate nel cluster kind (`kind load docker-image`): nessun registry
ancora, non necessario per l'ambiente locale.

### Micro-chart "namespace" e "postgresql" parametrizzati

Servono ora due istanze di ciascuno (namespace `auth`/`app`, PostgreSQL
per Keycloak/per l'applicazione). Invece di duplicare i manifest
(~10 e ~80 righe), entrambi i micro-chart introdotti in ADR-0002
guadagnano un `values.yaml` con default che riproducono esattamente il
comportamento originale (zero diff per le release "auth" esistenti) — la
generalizzazione minima per evitare la duplicazione, non parametrizzazione
speculativa.

### whoami rimosso, routing path-based su oauth2-proxy

Il chart `helm/charts/whoami` e la sua release sono rimossi. oauth2-proxy
instrada ora due upstream reali (`config.upstreams`, formato nativo del
flag `--upstream`, dove il path della URI stessa è la chiave di routing,
non riscritto):

```
"/"     → one-piece-user-frontend.app.svc.cluster.local
"/api/" → one-piece-user-service.app.svc.cluster.local
```

Poiché oauth2-proxy inoltra il path originale invariato, il backend è
configurato con `server.servlet.context-path=/api` (Spring Boot) in modo
che i suoi percorsi reali coincidano con quanto il proxy inoltra, senza
riscrittura lato proxy.

### Un solo percorso pubblico, deliberatamente

Fino allo Step 1 del piano di implementazione (login/identità applicativa
non ancora costruiti), l'unico percorso escluso dall'autenticazione è
l'health check del backend (`--skip-auth-route=GET=^/api/actuator/health`),
necessario per verificare il deploy e per i probe Kubernetes stessi. Tutto
il resto — incluso il frontend — resta dietro il login Keycloak per
default: comportamento di sicurezza corretto fin da ora, anche prima che
l'applicazione sappia cosa farne di un token.

## Conseguenze

- Il grafo di dipendenze di Helmfile si allarga:
  `app-namespace → app-postgresql → user-service`,
  `app-namespace → user-frontend`; `oauth2-proxy` dipende ora da
  `app/user-service` e `app/user-frontend` invece che da `auth/whoami`.
- `kubectl rollout restart` da solo **non** basta dopo una modifica al
  chart Helm (probe path, env, ecc.) — va rieseguito `helmfile sync`
  (o `helm upgrade`) sulla release, altrimenti si riavvia il pod con la
  spec *precedente* invariata. Causa di un primo giro di CrashLoopBackOff
  durante il bootstrap di questa configurazione (probe puntavano ancora a
  `/actuator/health/*` invece di `/api/actuator/health/*`).
- Verificato end-to-end (port-forward su `oauth2-proxy:4180`): l'health
  check del backend risponde `200 {"status":"UP"}` senza autenticazione;
  la root del frontend risponde `302` verso l'URL di autorizzazione
  Keycloak con `code_challenge`/`code_challenge_method=S256` valorizzati
  (PKCE reale, non solo configurato).
