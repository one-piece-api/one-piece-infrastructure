#!/usr/bin/env bash
# Verifica l'irrigidimento del realm (D3/D4, piano production-remote):
# - brute-force attivo (blocco temporaneo) in ogni ambiente; la password
#   policy solo in "remote" (vedi apply-realm-configmap.sh);
# - la rotta di Keycloak nega /realms/master con una risposta diretta 404
#   (verificato sul manifest renderizzato: l'host auth. esiste solo in remote).

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
cd "$REPO_ROOT"

# shellcheck disable=SC1091
source "$REPO_ROOT/scripts/lib/keycloak-admin-password.sh"

realm="$(kubectl exec -n "$NAMESPACE" statefulset/keycloak -- bash -c '
  /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user admin --password "$1" >/dev/null
  /opt/keycloak/bin/kcadm.sh get realms/onepiece --fields bruteForceProtected,permanentLockout,failureFactor,passwordPolicy
' bash "$kc_admin_password")"

failures=0
check() {
  if jq -e "$1" <<<"$realm" >/dev/null; then
    log "ok: $2"
  else
    error "$2"
    failures=$((failures + 1))
  fi
}

check '.bruteForceProtected == true and .permanentLockout == false' "brute-force attivo, blocco temporaneo"
if [ "${HELMFILE_ENVIRONMENT:-default}" = "remote" ]; then
  check '.failureFactor == 5' "soglia brute-force di produzione (5)"
  check '(.passwordPolicy // "") | contains("length(12)")' "password policy di produzione"
else
  check '(.passwordPolicy // "") == ""' "nessuna password policy fuori da remote"
fi

rendered="$(helm template route helm/charts/http-route --set name=keycloak \
  --set 'denyPaths[0]=/realms/master' | tr -d '\r')"
if grep -q 'kind: HTTPRouteFilter' <<<"$rendered" && grep -q 'value: /realms/master' <<<"$rendered"; then
  log "ok: /realms/master negato dalla rotta"
else
  error "/realms/master non negato dalla rotta"
  failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  error "$failures verifiche fallite"
  exit 1
fi
