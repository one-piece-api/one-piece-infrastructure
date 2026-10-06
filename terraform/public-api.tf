# Esposizione dell'API pubblica su Cloudflare (ADR-0024): limite per IP,
# cache CDN e HSTS. La rotta e il tetto complessivo stanno nel gateway
# (release "api-route" in helmfile.yaml.gotmpl).

locals {
  api_host = "api.${var.public_domain}"
}

# Limite per IP sull'API (piano gratuito: una regola, finestra di 10 s).
# Cloudflare conta per data center: cf.colo.id è obbligatorio tra le
# caratteristiche. Il traffico bloccato non arriva al Load Balancer da 10 Mbps.
resource "cloudflare_ruleset" "rate_limit" {
  zone_id = data.cloudflare_zone.public.zone_id
  name    = "onepiece rate limits"
  kind    = "zone"
  phase   = "http_ratelimit"

  rules = [
    {
      ref         = "public_api_per_ip"
      description = "API pubblica: 100 richieste ogni 10 s per IP"
      expression  = "(http.host eq \"${local.api_host}\")"
      action      = "block"
      ratelimit = {
        characteristics     = ["ip.src", "cf.colo.id"]
        period              = 10
        requests_per_period = 100
        mitigation_timeout  = 10
      }
      # Stessa forma degli errori del servizio (Problem Details, plan D9);
      # Content-Type application/json: Cloudflare non accetta
      # application/problem+json per le risposte personalizzate.
      action_parameters = {
        response = {
          status_code  = 429
          content_type = "application/json"
          content = jsonencode({
            type      = "about:blank"
            title     = "Too Many Requests"
            status    = 429
            detail    = "More than 100 requests in 10 seconds from this address: retry in a few seconds."
            errorCode = "RATE_LIMITED"
          })
        }
      }
    },
  ]
}

# Cache CDN sull'API: i percorsi non hanno estensione, quindi Cloudflare non li
# metterebbe in cache da solo. Durata in CDN e nel browser presa dal
# Cache-Control del servizio: la politica resta solo lì (plan D13).
resource "cloudflare_ruleset" "cache" {
  zone_id = data.cloudflare_zone.public.zone_id
  name    = "onepiece cache rules"
  kind    = "zone"
  phase   = "http_request_cache_settings"

  rules = [
    {
      ref         = "public_api_cache"
      description = "API pubblica in cache secondo il Cache-Control del servizio"
      expression  = "(http.host eq \"${local.api_host}\")"
      action      = "set_cache_settings"
      action_parameters = {
        cache = true
        edge_ttl = {
          mode = "respect_origin"
        }
        browser_ttl = {
          mode = "respect_origin"
        }
      }
    },
  ]
}

# HSTS per tutto il dominio: 1 anno, sottodomini inclusi. Niente preload: il
# TLD .dev è già nella lista preload dei browser.
resource "cloudflare_zone_setting" "hsts" {
  zone_id    = data.cloudflare_zone.public.zone_id
  setting_id = "security_header"
  value = {
    strict_transport_security = {
      enabled            = true
      max_age            = 31536000
      include_subdomains = true
      preload            = false
      nosniff            = true
    }
  }
}
