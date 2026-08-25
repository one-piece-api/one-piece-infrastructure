#!/usr/bin/env bash
# Carica i segreti locali da .env.local (radice del repo, escluso da git dal
# pattern ".env.*" in .gitignore) se presente - copiare da .env.local.example
# e valorizzare una volta sola, invece di "export" manuale ad ogni sessione
# di shell. Stesso spirito di oauth2-proxy/secret.local.yaml per gli altri
# segreti locali di questo repo (vedi scripts/generate-oauth2-proxy-secret.sh).
#
# Va incluso con "source" da ogni script che legge un segreto locale
# (RESEND_API_KEY oggi, altri in futuro) - autonomo apposta, non solo via
# lib/common.sh, perché gli hook Helmfile (es. configure-realm-smtp.sh)
# vengono invocati direttamente da Helmfile e non passano da setup.sh o da
# common.sh.

_env_local_file="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.env.local"
if [ -f "$_env_local_file" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$_env_local_file"
  set +a
fi
unset _env_local_file
