#!/usr/bin/env bash
# Genera oauth2-proxy/secret.local.yaml (se assente) e lo applica al cluster.
#
# Hook presync della release "oauth2-proxy" in helmfile.yaml: i suoi values
# (oauth2-proxy/values-oauth2-proxy.yaml) referenziano questo Secret tramite
# config.existingSecret, che deve quindi esistere già quando il chart viene
# sincronizzato. Idempotente: se il file esiste già (es. da un run
# precedente) viene riusato così com'è, senza rigenerare il cookie secret.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

SECRET_FILE="oauth2-proxy/secret.local.yaml"

if [ -f "$SECRET_FILE" ]; then
  echo "[generate-oauth2-proxy-secret] $SECRET_FILE già presente, lo riuso così com'è."
else
  echo "[generate-oauth2-proxy-secret] genero $SECRET_FILE da secret.local.example.yaml..."

  # Client secret: estratto da realm-onepiece.json (unica source of truth,
  # nessun placeholder duplicato da tenere sincronizzato a mano).
  client_secret="$(jq -r '.clients[] | select(.clientId=="onepiece-proxy") | .secret' keycloak/realm-onepiece.json)"
  if [ -z "$client_secret" ] || [ "$client_secret" = "null" ]; then
    echo "[generate-oauth2-proxy-secret] ERRORE: impossibile estrarre il client secret di 'onepiece-proxy' da keycloak/realm-onepiece.json" >&2
    exit 1
  fi

  # Cookie secret: 32 byte casuali, base64 URL-safe (oauth2-proxy decodifica
  # solo questa variante — con caratteri +/ standard il decode fallisce e
  # la stringa viene trattata come 44 byte raw invece di 32, vedi ADR).
  cookie_secret="$(openssl rand -base64 32 | tr -- '+/' '-_')"

  sed \
    -e "s#REPLACE_WITH_CLIENT_SECRET#${client_secret}#" \
    -e "s#REPLACE_WITH_RANDOM_32_BYTE_BASE64#${cookie_secret}#" \
    oauth2-proxy/secret.local.example.yaml > "$SECRET_FILE"
fi

kubectl apply -f "$SECRET_FILE"
