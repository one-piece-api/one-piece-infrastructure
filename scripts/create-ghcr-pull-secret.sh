#!/usr/bin/env bash
# Crea (o aggiorna) il Secret imagePullSecret per ghcr.io nel namespace "app".
#
# Hook presync delle release "user-service" e "user-frontend" in
# helmfile.yaml.gotmpl: nell'ambiente "ci" i loro Pod referenziano questo Secret
# tramite imagePullSecrets (i package GHCR sono privati di default) e deve
# quindi esistere già quando il chart viene sincronizzato.
#
# In locale (ambiente "default") le immagini sono costruite a mano e
# caricate direttamente nel cluster kind con "kind load docker-image"
# (ADR-0003): nessun pull da registry, quindi qui non c'è nulla da fare.
# GHCR_PULL_TOKEN assente è il segnale di questo caso, non un errore.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck disable=SC1091
source lib/load-env-local.sh

if [ -z "${GHCR_PULL_TOKEN:-}" ]; then
  echo "[create-ghcr-pull-secret] GHCR_PULL_TOKEN non impostata, salto (ambiente locale)."
  exit 0
fi

kubectl create secret docker-registry ghcr-pull-secret \
  --docker-server=ghcr.io \
  --docker-username="${GHCR_PULL_USERNAME:?GHCR_PULL_USERNAME non impostata}" \
  --docker-password="$GHCR_PULL_TOKEN" \
  -n app --dry-run=client -o yaml | kubectl apply -f -
