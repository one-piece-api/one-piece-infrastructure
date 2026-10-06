# ADR-0019: Gateway API con Envoy Gateway al posto di ingress-nginx

## Contesto

Tutto il traffico dell'ambiente remoto entra da ingress-nginx (ADR-0005). Il progetto
ingress-nginx è stato dismesso da Kubernetes a marzo 2026: niente più release, nemmeno
di sicurezza. Il successore standard è la Gateway API, che però richiede un
implementatore. L'esposizione dell'API pubblica (`implementation-plan-public-api.md` §3)
gli chiede:

- riscrittura del prefisso (`URLRewrite`): `/api/public/…` → `/…`;
- limite di richieste per IP reale del client, con `429`;
- IP reale preso da un header (`CF-Connecting-IP`, ADR-0020);
- integrazione con cert-manager (ADR-0021);
- immagini ARM64 (nodi Ampere A1) e consumi compatibili con Always Free.

## Decisione

- **Envoy Gateway** come implementazione della Gateway API.
  - Routing con `Gateway` + `HTTPRoute`, risorse standard.
  - IP reale (`ClientTrafficPolicy`) e limite di richieste (`BackendTrafficPolicy`,
    modalità locale: nessun Redis) sono policy dichiarative dedicate, non annotazioni.
    **Corretto (2026-10-06, ADR-0024):** il limite locale non conta per singolo IP
    (solo un tetto per rotta) e il suo `429` non porta `Retry-After`; il conteggio
    per IP richiede la modalità globale (servizio di rate limit + Redis). Il limite
    per IP è quindi su Cloudflare, Envoy tiene solo un tetto complessivo.
  - Le annotazioni OCI del Load Balancer (shape flexible 10 Mbps, subnet, IP riservato,
    security list non gestita dal CCM) passano al Service generato tramite la risorsa
    `EnvoyProxy`.
- **Migrazione da sola, prima di dominio e HTTPS** (step I1): stesso IP, HTTP, stessi
  percorsi di oggi (`/` → oauth2-proxy, `/realms` e `/resources` → Keycloak). Host e TLS
  arrivano negli step successivi, direttamente sul gateway nuovo.
- ingress-nginx e il chart `ingress` vengono rimossi.
- Da verificare sulla documentazione corrente in I1, non assunti qui: passaggio delle
  annotazioni al Service, immagini ARM64, `Retry-After` sui `429` del limite locale,
  convivenza delle CRD Gateway API con quelle eventualmente preinstallate su OKE.

## Alternative considerate

- **Traefik**: un solo componente, leggero; ma il limite di richieste passa da
  estensioni proprietarie (`ExtensionRef`), non dalla Gateway API.
- **NGINX Gateway Fabric**: il più vicino a ingress-nginx; copertura minore delle
  esigenze avanzate (limiti, IP reale).
- **Istio / Cilium**: completi, ma troppo pesanti per Always Free; Cilium sostituirebbe
  anche il CNI del cluster.
- **Dominio e HTTPS prima, su ingress-nginx**: dominio attivo prima, ma host e TLS
  configurati su un componente da rimuovere subito dopo.

## Conseguenze

- Due componenti al posto di uno (controller + proxy Envoy): requests/limits da tarare
  sul budget Always Free (ADR-0005).
- Le rotte diventano `HTTPRoute`; un nuovo servizio esposto richiede una rotta, non più
  un path nel chart `ingress`.
- Lo step I1 si verifica a comportamento invariato: qualunque differenza è un errore
  della migrazione.
