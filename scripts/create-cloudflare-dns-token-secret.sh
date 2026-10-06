#!/usr/bin/env bash
# Crea (o aggiorna) il Secret con il token API Cloudflare usato da
# cert-manager per la verifica DNS-01 (ADR-0021), nel namespace
# "cert-manager" dove i ClusterIssuer cercano i loro Secret.
#
# Hook presync della release "cert-manager" in helmfile.yaml.gotmpl, solo
# nell'ambiente "remote" (locale e CI non hanno dominio né cert-manager).
# Il token (permessi Zone Read + DNS Edit sulla sola zona onepieceapi.dev)
# arriva da CLOUDFLARE_DNS_API_TOKEN: secret GitHub Actions in CI
# (deploy-remote.yml), .env.local per un sync manuale.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck disable=SC1091
source scripts/lib/load-env-local.sh

: "${CLOUDFLARE_DNS_API_TOKEN:?CLOUDFLARE_DNS_API_TOKEN non impostata - richiesta in \"remote\" (vedi docs/adr/0021-https-cert-manager-dns01.md)}"

kubectl create secret generic cloudflare-dns-api-token \
  --namespace cert-manager \
  --from-literal=api-token="$CLOUDFLARE_DNS_API_TOKEN" \
  --dry-run=client -o yaml \
  | kubectl apply -f - >/dev/null

echo "[create-cloudflare-dns-token-secret] Secret cloudflare-dns-api-token aggiornato (namespace cert-manager)."
