#!/usr/bin/env bash
# Verifica end-to-end il flow OAuth 2.0 Authorization Code + PKCE, l'unico
# modo previsto di autenticarsi (Direct Access Grants è disabilitato di
# proposito sul client "onepiece-proxy", vedi keycloak/realm-onepiece.json).
#
# Simula un browser con un cookie jar curl: redirect a Keycloak, login,
# callback, sessione, accesso a whoami con gli header inoltrati.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
cd "$REPO_ROOT"

KC_URL="http://localhost:8080"
PROXY_URL="http://localhost:4180"
WORKDIR="$(mktemp -d)"
COOKIES="$WORKDIR/cookies.txt"
PF_PIDS=()

cleanup() {
  for pid in "${PF_PIDS[@]:-}"; do
    kill "$pid" >/dev/null 2>&1 || true
  done
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

# start_port_forward <service> <local:remote> <logfile>
# kubectl port-forward a volte fallisce con "address already in use" se la
# porta locale è appena stata rilasciata da un run precedente (TIME_WAIT):
# un paio di retry con una breve pausa risolvono senza intervento manuale.
start_port_forward() {
  local service="$1" ports="$2" logfile="$3" attempt
  for attempt in 1 2 3; do
    kubectl port-forward "svc/$service" -n "$NAMESPACE" "$ports" >"$logfile" 2>&1 &
    local pid=$!
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      grep -q "Forwarding from" "$logfile" 2>/dev/null && { PF_PIDS+=("$pid"); return 0; }
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.5
    done
    kill "$pid" >/dev/null 2>&1 || true
    sleep 1
  done
  error "impossibile avviare 'kubectl port-forward svc/$service $ports' dopo 3 tentativi"
  cat "$logfile" >&2
  exit 1
}

log "avvio port-forward verso keycloak-http e oauth2-proxy..."
start_port_forward keycloak-http 8080:8080 "$WORKDIR/pf-keycloak.log"
start_port_forward oauth2-proxy 4180:4180 "$WORKDIR/pf-oauth2-proxy.log"

log "1/5 verifico l'endpoint di discovery OIDC..."
discovery="$(curl -sf "$KC_URL/realms/onepiece/.well-known/openid-configuration")"
echo "$discovery" | jq -e --arg iss "$KC_URL/realms/onepiece" \
  '.issuer == $iss and .authorization_endpoint != null and .token_endpoint != null and .jwks_uri != null' \
  >/dev/null || { error "discovery document inatteso: $discovery"; exit 1; }

log "2/5 verifico il redirect di oauth2-proxy verso Keycloak (con PKCE)..."
curl -s -c "$COOKIES" -b "$COOKIES" -D "$WORKDIR/step1.h" "$PROXY_URL/" -o /dev/null
auth_url="$(grep -i '^location:' "$WORKDIR/step1.h" | sed 's/^[Ll]ocation: //' | tr -d '\r')"
[ -n "$auth_url" ] || { error "nessun redirect da $PROXY_URL/"; exit 1; }
echo "$auth_url" | grep -q "code_challenge=" || { error "redirect senza PKCE code_challenge: $auth_url"; exit 1; }
echo "$auth_url" | grep -q "code_challenge_method=S256" || { error "PKCE method non è S256: $auth_url"; exit 1; }

log "3/5 effettuo il login come 'luffy'..."
curl -s -c "$COOKIES" -b "$COOKIES" "$auth_url" -o "$WORKDIR/login.html"
action_url="$(grep -o 'action="[^"]*"' "$WORKDIR/login.html" | head -1 | sed 's/action="//;s/"$//;s/&amp;/\&/g')"
[ -n "$action_url" ] || { error "form di login non trovato nella pagina Keycloak"; exit 1; }

luffy_password="$(jq -r '.users[] | select(.username=="luffy") | .credentials[0].value' keycloak/realm-onepiece.json)"
curl -s -c "$COOKIES" -b "$COOKIES" -D "$WORKDIR/step3.h" \
  -X POST "$action_url" \
  --data-urlencode "username=luffy" \
  --data-urlencode "password=$luffy_password" \
  --data-urlencode "credentialId=" \
  -o /dev/null
callback_url="$(grep -i '^location:' "$WORKDIR/step3.h" | sed 's/^[Ll]ocation: //' | tr -d '\r')"
echo "$callback_url" | grep -q "/oauth2/callback" || { error "login fallito, nessun redirect al callback: vedi $WORKDIR/login.html"; exit 1; }

log "4/5 completo il callback (scambio del code, creazione sessione)..."
curl -s -c "$COOKIES" -b "$COOKIES" -D "$WORKDIR/step4.h" "$callback_url" -o /dev/null
grep -qi "^HTTP/.* 302" "$WORKDIR/step4.h" || { error "callback non ha restituito una sessione (vedi $WORKDIR/step4.h)"; exit 1; }

log "5/5 accedo autenticato e verifico gli header inoltrati a whoami..."
body="$(curl -s -c "$COOKIES" -b "$COOKIES" "$PROXY_URL/")"
echo "$body" | grep -q "^Authorization: Bearer " || { error "header Authorization Bearer assente"; exit 1; }
echo "$body" | grep -q "^X-Forwarded-Email: luffy@onepiece.local" || { error "header X-Forwarded-Email assente/errato"; exit 1; }
echo "$body" | grep -q "^X-Forwarded-User: " || { error "header X-Forwarded-User assente"; exit 1; }

log "smoke test superato: Authorization Code + PKCE end-to-end funzionante."
