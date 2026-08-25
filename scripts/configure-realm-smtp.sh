#!/usr/bin/env bash
# Imposta la password SMTP (RESEND_API_KEY) del realm "onepiece" dopo
# l'import - l'unico pezzo di keycloak/realm-onepiece.json che non può
# essere committato in chiaro. Host/porta/mittente/auth puntano già al
# relay Resend nel realm importato (nessun mail-catcher locale - vedi
# docs/adr/0007-resend-only-email-delivery.md): questo script non li
# tocca più, si limita alla credenziale.
#
# Keycloak gestisce da sé l'invio delle email di sistema (invito, verifica
# email, reset password - UF-IDU-01/04/12, Step 4 in docs/implementation-plan.md
# nel repo one-piece-api), non user-service: niente client SMTP applicativo,
# niente token custom.
#
# Hook postsync della release "keycloak" in helmfile.yaml.gotmpl, in ogni
# ambiente (a differenza degli altri hook, tutti presync: qui serve l'Admin
# API di Keycloak già in ascolto). Usa kcadm.sh via "kubectl exec" invece di
# curl: l'immagine ufficiale quay.io/keycloak/keycloak non include curl
# (keycloak/keycloak#17438), ma include bash e kcadm.sh.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck disable=SC1091
source scripts/lib/load-env-local.sh

if [ -z "${RESEND_API_KEY:-}" ]; then
  echo "[configure-realm-smtp] RESEND_API_KEY non impostata - obbligatoria in ogni ambiente" \
    "da quando Mailpit è stato rimosso (docs/adr/0007-resend-only-email-delivery.md)." >&2
  exit 1
fi

# Placeholder locale (KC_BOOTSTRAP_ADMIN_PASSWORD in keycloak/values-keycloakx.yaml),
# non un segreto reale - stesso pattern di duplicazione già usato per le
# credenziali placeholder altrove nel repo (es. keycloak.admin.client-secret
# in application-local.properties di one-piece-user-service).
kc_admin_password="admin-change-me-locally"

# Passata come argomento posizionale allo script remoto, non interpolata
# nella stringa di comando: evita che compaia nella process list del
# container.
kubectl exec -n auth statefulset/keycloak -- bash -c '
  set -euo pipefail
  /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user admin --password "$1"
  /opt/keycloak/bin/kcadm.sh update realms/onepiece -s smtpServer.password="$2"
' bash "$kc_admin_password" "$RESEND_API_KEY"

echo "[configure-realm-smtp] Credenziale Resend impostata sul realm 'onepiece'."
