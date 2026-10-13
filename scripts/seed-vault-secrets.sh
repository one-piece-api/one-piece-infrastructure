#!/usr/bin/env bash
# Crea in OCI Vault i secret usati dal remoto (generati o da .env.local) (PR1/PR4
# del piano production-remote), in un colpo solo. Idempotente: un secret già
# esistente NON viene mai sovrascritto (una rotazione è un'operazione
# esplicita, non un effetto collaterale di un nuovo lancio). Nessun valore
# viene stampato. I nomi corrispondono ai vaultKey di
# helm/charts/credentials/values.yaml.
#
# Richiede: OCI CLI autenticata, openssl, terraform (outputs di terraform/).
# Opzionali: OCI_VAULT_ID, OCI_COMPARTMENT_ID, OCI_VAULT_KEY_ID.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
export SUPPRESS_LABEL_WARNING=True

tf_output() { terraform -chdir=terraform output -raw "$1"; }
vault_id="${OCI_VAULT_ID:-$(tf_output vault_id)}"
compartment_id="${OCI_COMPARTMENT_ID:-$(tf_output compartment_id)}"
key_id="${OCI_VAULT_KEY_ID:-$(tf_output vault_key_id)}"

hex()    { openssl rand -hex "$1" | tr -d '\r\n'; }
# oauth2-proxy decodifica solo base64 URL-safe a 32 byte (vedi ADR-0009).
cookie() { openssl rand -base64 32 | tr -- '+/' '-_' | tr -d '\r\n'; }

# nome-secret:generatore - i client secret sono condivisi tra realm e
# consumatori tramite lo stesso secret del Vault.
generated=(
  "onepiece-postgres-admin-password:hex 24"
  "onepiece-keycloak-db-password:hex 24"
  "onepiece-user-service-db-password:hex 24"
  "onepiece-content-service-db-password:hex 24"
  "onepiece-public-api-reader-db-password:hex 24"
  "onepiece-redis-password:hex 24"
  "onepiece-keycloak-admin-password:hex 24"
  "onepiece-proxy-client-secret:hex 32"
  "onepiece-user-service-admin-client-secret:hex 32"
  "onepiece-oauth2-proxy-cookie-secret:cookie"
)

# Il confronto sui nomi non dipende dai CRLF dell'OCI CLI su Windows.
active_names="$(oci vault secret list --compartment-id "$compartment_id" --vault-id "$vault_id" \
  --lifecycle-state ACTIVE --all --query 'data[]."secret-name"')"

# nome-secret:variabile - valori forniti dall'operatore (.env.local o
# ambiente), non generabili. Il token Cloudflare DNS (cert-manager) si carica
# a mano, vedi terraform/README.md.
provided=(
  "onepiece-ghcr-pull-username:GHCR_PULL_USERNAME"
  "onepiece-ghcr-pull-token:GHCR_PULL_TOKEN"
  "onepiece-resend-api-key:RESEND_API_KEY"
)

# shellcheck disable=SC1091
source scripts/lib/load-env-local.sh

created=0

# ensure_secret <nome> <valore>: crea il secret solo se assente.
ensure_secret() {
  local name="$1" value="$2"
  if grep -q "\"$name\"" <<<"$active_names"; then
    echo "[seed-vault-secrets] $name già presente, lasciato com'è."
    return
  fi
  oci vault secret create-base64 --compartment-id "$compartment_id" --vault-id "$vault_id" \
    --key-id "$key_id" --secret-name "$name" \
    --secret-content-content "$(printf '%s' "$value" | base64 -w0)" >/dev/null
  echo "[seed-vault-secrets] $name creato."
  created=$((created + 1))
}

for entry in "${generated[@]}"; do
  # shellcheck disable=SC2086
  ensure_secret "${entry%%:*}" "$(${entry#*:})"
done

for entry in "${provided[@]}"; do
  variable="${entry#*:}"
  if [ -z "${!variable:-}" ]; then
    echo "[seed-vault-secrets] ${entry%%:*} saltato: $variable non impostata."
    continue
  fi
  ensure_secret "${entry%%:*}" "${!variable}"
done
echo "[seed-vault-secrets] Fatto: $created nuovi secret."
