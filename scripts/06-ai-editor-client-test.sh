#!/usr/bin/env bash
# Verifica il client "ai-editor" (ADR-0026): token con client credentials,
# claim attesi e accettazione del bearer da parte di oauth2-proxy. Una modifica
# al realm che rompe l'identità dell'AI editor fa fallire la CI.
# Il secret si legge dal Secret del realm e non viene mai stampato.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
cd "$REPO_ROOT"

KC_URL="http://localhost:8080"
PROXY_URL="http://localhost:4180"
WORKDIR="$(mktemp -d)"
PF_PIDS=()

cleanup() {
  for pid in "${PF_PIDS[@]:-}"; do
    kill "$pid" >/dev/null 2>&1 || true
  done
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

# shellcheck disable=SC1091
source "$REPO_ROOT/scripts/lib/port-forward.sh"

start_port_forward keycloak-http 8080:8080 "$WORKDIR/pf-keycloak.log"
start_port_forward oauth2-proxy 4180:4180 "$WORKDIR/pf-oauth2-proxy.log"

client_secret="$(kubectl get secret one-piece-realm-secrets -n "$NAMESPACE" \
  -o jsonpath='{.data.AI_EDITOR_CLIENT_SECRET}' | base64 -d)"

log "1/2 richiedo un token con client credentials..."
token="$(curl -sf -u "ai-editor:$client_secret" -d grant_type=client_credentials \
  "$KC_URL/realms/onepiece/protocol/openid-connect/token" | jq -r .access_token)"
[ -n "$token" ] && [ "$token" != "null" ] || { error "nessun token per il client ai-editor"; exit 1; }

# Payload del JWT: base64url senza padding.
payload="$(cut -d. -f2 <<<"$token" | tr '_-' '/+')"
while [ $(( ${#payload} % 4 )) -ne 0 ]; do payload="$payload="; done
claims="$(base64 -d <<<"$payload")"

failures=0
check() {
  if jq -e "$1" <<<"$claims" >/dev/null; then
    log "ok: $2"
  else
    error "$2"
    failures=$((failures + 1))
  fi
}

check '.preferred_username == "ai-editor"' "preferred_username = ai-editor"
check '.email == "ai-editor@onepieceapi.dev"' "email dell'AI editor"
check '(.sub // "") | test("^[0-9a-f-]{36}$")' "sub presente"
check '[.aud] | flatten | index("onepiece-proxy") != null' "audience onepiece-proxy"
check '.resource_access["onepiece-proxy"].roles | sort == ["content:read", "content:write"]' \
  "solo i permessi di EDITOR (content:read, content:write)"

log "2/2 verifico che oauth2-proxy accetti il bearer..."
status="$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $token" "$PROXY_URL/oauth2/auth")"
if [ "$status" = "202" ]; then
  log "ok: bearer accettato da oauth2-proxy"
else
  error "oauth2-proxy ha risposto $status al bearer dell'AI editor"
  failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  error "$failures verifiche fallite"
  exit 1
fi
