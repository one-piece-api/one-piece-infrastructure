#!/usr/bin/env bash
# Distrugge l'intero ambiente locale eliminando il cluster kind: non serve
# "helm uninstall" prima, il cluster contiene tutto (namespace, workload,
# volumi persistenti compresi).
#
# Uso: scripts/teardown.sh [-y|--yes]   (-y salta la conferma interattiva)

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  log "nessun cluster kind '$CLUSTER_NAME' da eliminare."
  exit 0
fi

if [ "${1:-}" != "-y" ] && [ "${1:-}" != "--yes" ]; then
  read -r -p "Eliminare il cluster kind '$CLUSTER_NAME' e tutto il suo contenuto? [y/N] " reply
  case "$reply" in
    y|Y|yes|YES) ;;
    *) log "annullato."; exit 0 ;;
  esac
fi

log "elimino il cluster kind '$CLUSTER_NAME'..."
kind delete cluster --name "$CLUSTER_NAME"
