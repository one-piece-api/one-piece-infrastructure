#!/usr/bin/env bash
# Punta l'SMTP del realm "onepiece" dopo l'import: al vero relay Resend in
# "default"/"remote" (ADR-0007), a Mailpit (mock, in-cluster) in "ci"
# (ADR-0008) - senza un dominio verificato su Resend, l'account può
# consegnare solo al proprio indirizzo verificato, non agli indirizzi
# arbitrari @onepiece.local usati dai test e2e; la chiamata SMTP reale
# restava appesa abbastanza da far scadere anche test non legati alle email.
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

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib/keycloak-admin-password.sh"

if [ "${HELMFILE_ENVIRONMENT:-default}" = "ci" ]; then
  kubectl exec -n auth statefulset/keycloak -- bash -c '
    set -euo pipefail
    /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user admin --password "$1"
    /opt/keycloak/bin/kcadm.sh update realms/onepiece \
      -s smtpServer.host=mailpit.auth.svc.cluster.local \
      -s smtpServer.port=1025 \
      -s smtpServer.auth=false \
      -s smtpServer.starttls=false \
      -s smtpServer.ssl=false
  ' bash "$kc_admin_password"

  echo "[configure-realm-smtp] ci: realm 'onepiece' passato a Mailpit (mock SMTP)."
  exit 0
fi

if [ "${HELMFILE_ENVIRONMENT:-default}" = "remote" ]; then
  # In "remote" la chiave arriva dal Vault tramite il chart "credentials" (PR1).
  RESEND_API_KEY="$(kubectl get secret one-piece-resend-credentials -n auth -o jsonpath='{.data.api-key}' | base64 -d)"
fi

if [ -z "${RESEND_API_KEY:-}" ]; then
  echo "[configure-realm-smtp] RESEND_API_KEY non impostata - obbligatoria in \"default\"/\"remote\"" \
    "(vedi docs/adr/0007-resend-only-email-delivery.md)." >&2
  exit 1
fi

# Passata come argomento posizionale allo script remoto, non interpolata
# nella stringa di comando: evita che compaia nella process list del
# container.
kubectl exec -n auth statefulset/keycloak -- bash -c '
  set -euo pipefail
  /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user admin --password "$1"
  /opt/keycloak/bin/kcadm.sh update realms/onepiece -s smtpServer.password="$2"
' bash "$kc_admin_password" "$RESEND_API_KEY"

echo "[configure-realm-smtp] Credenziale Resend impostata sul realm 'onepiece'."
