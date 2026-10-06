# Email del progetto (ADR-0023): invio da mail.<dominio> tramite Resend,
# ricezione di contatti@<dominio> tramite Cloudflare Email Routing.

locals {
  mail_domain = "mail.${var.public_domain}"

  # Record del dominio di invio, come li ha generati Resend alla creazione
  # del dominio (regione eu-west-1, 2026-10-06). La chiave DKIM è pubblica:
  # sta nel DNS di chiunque la interroghi. Ricreare il dominio su Resend
  # genera una chiave nuova, da copiare qui.
  resend_records = {
    dkim = {
      name    = "resend._domainkey.${local.mail_domain}"
      type    = "TXT"
      content = "p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCinptutU+6SBVI3tXzQvY1OtiFotbeE71JDoMOTKqCfAmPXk4aesGnZjL8HUynHtMHORv5zNpJhJqNn+nsku8jlA4WBg0jwTZqfIPg+CqFg4KWgrhF0m+2O6JrCxkJqv35ZEI2soTYhWvEZmD0zqiWYVLv4XMI1bY4i5eM6ZqRAwIDAQAB"
    }
    # Dominio di ritorno (MAIL FROM): rimbalzi e reclami tornano a Resend.
    bounce_mx = {
      name     = "send.${local.mail_domain}"
      type     = "MX"
      content  = "feedback-smtp.eu-west-1.amazonses.com"
      priority = 10
    }
    bounce_spf = {
      name    = "send.${local.mail_domain}"
      type    = "TXT"
      content = "v=spf1 include:amazonses.com ~all"
    }
    return_path = {
      name    = "rsend.${local.mail_domain}"
      type    = "CNAME"
      content = "send.forge.rmta.net"
    }
  }
}

resource "cloudflare_dns_record" "resend" {
  for_each = local.resend_records

  zone_id  = data.cloudflare_zone.public.zone_id
  name     = each.value.name
  type     = each.value.type
  content  = each.value.content
  priority = lookup(each.value, "priority", null)
  # Record per i server di posta: mai proxied, TTL automatico.
  proxied = false
  ttl     = 1
  comment = "Resend, invio email (ADR-0023)"
}

# DMARC: cosa fare delle email che si spacciano per noi. Dominio principale
# "reject": non invia email. mail. "quarantine" (spam, non rifiuto) finché il
# dominio di invio è nuovo: DKIM di Resend è allineato, quindi le email vere
# passano comunque.
resource "cloudflare_dns_record" "dmarc" {
  for_each = {
    (var.public_domain) = "v=DMARC1; p=reject"
    (local.mail_domain) = "v=DMARC1; p=quarantine"
  }

  zone_id = data.cloudflare_zone.public.zone_id
  name    = "_dmarc.${each.key}"
  type    = "TXT"
  content = each.value
  proxied = false
  ttl     = 1
  comment = "DMARC (ADR-0023)"
}

# Ricezione: Email Routing attivo sul dominio principale. Cloudflare crea e
# gestisce da sé MX e SPF del dominio (l'SPF richiesto dall'inoltro, motivo
# per cui il dominio principale non ha un "v=spf1 -all": ADR-0023).
resource "cloudflare_email_routing_dns" "public" {
  zone_id = data.cloudflare_zone.public.zone_id
}

# Casella di destinazione: Cloudflare invia un'email di conferma, l'inoltro
# parte solo dopo il clic.
resource "cloudflare_email_routing_address" "owner" {
  account_id = var.cloudflare_account_id
  email      = var.email_routing_destination
}

resource "cloudflare_email_routing_rule" "contatti" {
  zone_id = data.cloudflare_zone.public.zone_id
  name    = "contatti -> proprietario"
  enabled = true

  matchers = [
    {
      type  = "literal"
      field = "to"
      value = "contatti@${var.public_domain}"
    },
  ]

  actions = [
    {
      type  = "forward"
      value = [cloudflare_email_routing_address.owner.email]
    },
  ]

  depends_on = [cloudflare_email_routing_dns.public]
}
