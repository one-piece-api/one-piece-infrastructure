#!/usr/bin/env bash
# Crea il cluster kind locale, se non esiste già (idempotente).
# Nessuna extraPortMapping: l'accesso ai servizi avviene solo via
# "kubectl port-forward" (vedi kubernetes/kind-config.yaml).

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
cd "$REPO_ROOT"

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  log "cluster kind '$CLUSTER_NAME' già esistente, salto la creazione."
else
  log "creo il cluster kind '$CLUSTER_NAME'..."
  kind create cluster --config kubernetes/kind-config.yaml
fi
