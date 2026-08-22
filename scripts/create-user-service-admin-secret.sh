#!/usr/bin/env bash
# Crea (o aggiorna) il Secret con il client secret del client Keycloak
# "user-service-admin" nel namespace "app".
#
# Hook presync della release "user-service" in helmfile.yaml.gotmpl:
# user-service lo referenzia tramite un secretKeyRef (vedi
# helm/charts/user-service) per autenticarsi come service account contro
# l'Admin REST API di Keycloak (Step 3 del piano — listing utenti, UF-IDU-17).
#
# Il valore vive in keycloak/realm-onepiece.json (unica source of truth,
# nessun placeholder duplicato da tenere sincronizzato a mano) — stesso
# pattern di generate-oauth2-proxy-secret.sh.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

client_secret="$(jq -r '.clients[] | select(.clientId=="user-service-admin") | .secret' keycloak/realm-onepiece.json)"
if [ -z "$client_secret" ] || [ "$client_secret" = "null" ]; then
  echo "[create-user-service-admin-secret] ERRORE: impossibile estrarre il client secret di 'user-service-admin' da keycloak/realm-onepiece.json" >&2
  exit 1
fi

kubectl create secret generic one-piece-user-service-admin-credentials \
  --from-literal=client-secret="$client_secret" \
  -n app --dry-run=client -o yaml | kubectl apply -f -
