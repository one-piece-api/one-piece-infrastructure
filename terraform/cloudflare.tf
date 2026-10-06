# Dominio pubblico su Cloudflare (ADR-0020): un sottodominio per pubblico,
# tutti proxied (CDN, protezione, IP dell'origin nascosto) verso l'IP
# riservato del Load Balancer del Gateway.

data "cloudflare_zone" "public" {
  filter = {
    name = var.public_domain
  }
}

locals {
  app_host  = "app.${var.public_domain}"
  auth_host = "auth.${var.public_domain}"

  # Dominio principale (redirect verso api., poi vetrina), API pubblica,
  # back-office, login.
  proxied_hosts = toset([
    var.public_domain,
    "api.${var.public_domain}",
    local.app_host,
    local.auth_host,
  ])
}

resource "cloudflare_dns_record" "origin" {
  for_each = local.proxied_hosts

  zone_id = data.cloudflare_zone.public.zone_id
  name    = each.value
  type    = "A"
  content = oci_core_public_ip.lb.ip_address
  proxied = true
  # 1 = "automatico", obbligatorio per i record proxied.
  ttl     = 1
  comment = "Origin: Load Balancer OCI del Gateway (ADR-0020)"
}

# Cloudflare -> origin cifrato con verifica del certificato (ADR-0021:
# Let's Encrypt via cert-manager); visitatori sempre su HTTPS.
resource "cloudflare_zone_setting" "ssl" {
  zone_id    = data.cloudflare_zone.public.zone_id
  setting_id = "ssl"
  value      = "strict"
}

resource "cloudflare_zone_setting" "always_use_https" {
  zone_id    = data.cloudflare_zone.public.zone_id
  setting_id = "always_use_https"
  value      = "on"
}

resource "cloudflare_zone_setting" "min_tls_version" {
  zone_id    = data.cloudflare_zone.public.zone_id
  setting_id = "min_tls_version"
  value      = "1.2"
}

# Back-office raggiungibile solo dall'IP del proprietario (ADR-0020): stessa
# esposizione di prima del dominio, finché console admin e utenti seed hanno
# password note. API pubblica e dominio principale restano aperti.
resource "cloudflare_ruleset" "firewall_custom" {
  zone_id = data.cloudflare_zone.public.zone_id
  name    = "onepiece custom rules"
  kind    = "zone"
  phase   = "http_request_firewall_custom"

  rules = [
    {
      ref         = "back_office_owner_only"
      description = "app./auth. solo dall'IP del proprietario"
      expression  = "(http.host in {\"${local.app_host}\" \"${local.auth_host}\"} and not ip.src in {${var.allowed_client_cidr} ${var.allowed_client_ipv6_cidr}})"
      action      = "block"
    },
  ]
}

# Intervalli IP da cui Cloudflare contatta l'origin: la security list li usa
# per aprire la 443 solo a Cloudflare (network.tf).
data "cloudflare_ip_ranges" "current" {}
