#!/usr/bin/env bash
# Sostituisce l'SMTP del realm "onepiece" committato in realm-onepiece.json
# (Mailpit locale, senza autenticazione) con il vero relay Resend, quando
# RESEND_API_KEY è impostata.
#
# Keycloak gestisce da sé l'invio delle email di sistema (invito, verifica
# email, reset password - UF-IDU-01/04/12, Step 4 in docs/implementation-plan.md
# nel repo one-piece-api), non user-service: niente client SMTP applicativo,
# niente token custom.
#
# Hook postsync della release "keycloak" in helmfile.yaml.gotmpl (a
# differenza degli altri hook, tutti presync: qui serve l'Admin API di
# Keycloak già in ascolto). Usa kcadm.sh via "kubectl exec" invece di curl:
# l'immagine ufficiale quay.io/keycloak/keycloak non include curl
# (keycloak/keycloak#17438), ma include bash e kcadm.sh.
#
# RESEND_API_KEY assente non è un errore: il realm resta su Mailpit (che
# funziona già di suo, a differenza del vecchio placeholder Resend non
# funzionante) - stesso pattern "skip silenzioso" di create-ghcr-pull-secret.sh.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [ -z "${RESEND_API_KEY:-}" ]; then
  echo "[configure-realm-smtp] RESEND_API_KEY non impostata, salto (realm resta su Mailpit)."
  exit 0
fi

# Placeholder locale (KC_BOOTSTRAP_ADMIN_PASSWORD in keycloak/values-keycloakx.yaml),
# non un segreto reale - stesso pattern di duplicazione già usato per le
# credenziali placeholder altrove nel repo (es. keycloak.admin.client-secret
# in application-local.properties di one-piece-user-service).
kc_admin_password="admin-change-me-locally"

# Passati come argomenti posizionali allo script remoto, non interpolati
# nella stringa di comando: evita che compaiano nella process list del
# container.
kubectl exec -n auth statefulset/keycloak -- bash -c '
  set -euo pipefail
  /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user admin --password "$1"
  /opt/keycloak/bin/kcadm.sh update realms/onepiece \
    -s smtpServer.host=smtp.resend.com \
    -s smtpServer.port=587 \
    -s smtpServer.from="onboarding@resend.dev" \
    -s smtpServer.auth=true \
    -s smtpServer.user=resend \
    -s smtpServer.starttls=true \
    -s smtpServer.password="$2"
' bash "$kc_admin_password" "$RESEND_API_KEY"

echo "[configure-realm-smtp] realm 'onepiece' passato al relay SMTP Resend."
