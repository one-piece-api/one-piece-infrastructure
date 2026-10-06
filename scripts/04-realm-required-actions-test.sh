#!/usr/bin/env bash
# Verifica che le azioni richieste di Keycloak usate dal progetto siano
# registrate e attive nel realm "onepiece" dopo il sync.
#
# Perché: keycloak-config-cli (ADR-0011) tratta la lista "requiredActions" di
# realm-onepiece.json come elenco completo e cancella le azioni non
# dichiarate. Quando la lista conteneva solo delete_account (ADR-0013), ogni
# sync rimuoveva UPDATE_PASSWORD/UPDATE_PROFILE/VERIFY_EMAIL e l'invito
# (execute-actions-email, UF-IDU-01) mostrava una pagina senza step, senza
# poter attivare l'account. Gira dopo il secondo "helmfile sync" della CI,
# che è il momento in cui la cancellazione avveniva.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
cd "$REPO_ROOT"

# Placeholder locale (KC_BOOTSTRAP_ADMIN_PASSWORD in keycloak/values-keycloakx.yaml),
# non un segreto reale - stesso pattern di configure-realm-smtp.sh.
kc_admin_password="admin-change-me-locally"

# Invito (UF-IDU-01), profilo utente di Keycloak 26, cambio lingua,
# cancellazione self-service (ADR-0013).
required=(UPDATE_PASSWORD UPDATE_PROFILE VERIFY_EMAIL VERIFY_PROFILE update_user_locale delete_account)

enabled_actions="$(kubectl exec -n "$NAMESPACE" statefulset/keycloak -- bash -c '
  /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user admin --password "$1" >/dev/null
  /opt/keycloak/bin/kcadm.sh get authentication/required-actions -r onepiece --fields alias,enabled --format csv --noquotes
' bash "$kc_admin_password" | awk -F, '$2 == "true" { print $1 }')"

failures=0
for action in "${required[@]}"; do
  if grep -qx "$action" <<<"$enabled_actions"; then
    log "ok: azione richiesta $action attiva"
  else
    error "azione richiesta $action assente o disattivata nel realm 'onepiece'"
    failures=$((failures + 1))
  fi
done

if [ "$failures" -gt 0 ]; then
  error "$failures azioni richieste mancanti - vedi requiredActions in keycloak/realm-onepiece.json"
  exit 1
fi
log "Tutte le azioni richieste del progetto sono attive."
