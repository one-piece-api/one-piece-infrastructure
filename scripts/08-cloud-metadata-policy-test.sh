#!/usr/bin/env bash
# Verifica la NetworkPolicy sui metadata del cloud (ADR-0027, D5, chart
# "namespace"): presente in ogni namespace del progetto e applicata ai pod
# senza etichetta di eccezione. L'eccezione si prova solo dove l'indirizzo
# dei metadata risponde (runner GitHub su Azure); in locale (Docker Desktop)
# non risponde e quella verifica viene saltata.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
cd "$REPO_ROOT"

POLICY_NAME="deny-cloud-metadata"
EXCEPTION_LABEL="onepiece-api/oci-metadata=allowed"
METADATA_URL="http://169.254.169.254/"
PROBE_NAMESPACE="app"
PROBE_IMAGE="docker.io/curlimages/curl:8.17.0"

failures=0
fail() { error "$*"; failures=$((failures + 1)); }

# probe <nome> [etichette]: codice di uscita di curl verso i metadata da un pod
# effimero (0 = raggiunti, 28 = timeout). Log letti a pod concluso: con
# "kubectl run -i" l'output va perso se il pod finisce prima dell'attach.
probe() {
  local name="$1" labels="${2:-}"
  kubectl delete pod "$name" -n "$PROBE_NAMESPACE" --ignore-not-found >/dev/null
  kubectl run "$name" -n "$PROBE_NAMESPACE" --restart=Never --image="$PROBE_IMAGE" \
    ${labels:+--labels="$labels"} --command -- \
    sh -c "curl -s -o /dev/null --connect-timeout 5 '$METADATA_URL'; echo \"exit=\$?\"" >/dev/null
  kubectl wait pod "$name" -n "$PROBE_NAMESPACE" --timeout=120s \
    --for=jsonpath='{.status.phase}'=Succeeded >/dev/null || true
  kubectl logs "$name" -n "$PROBE_NAMESPACE" 2>/dev/null | sed -n 's/^exit=//p' | tail -n 1
  kubectl delete pod "$name" -n "$PROBE_NAMESPACE" --ignore-not-found >/dev/null
}

log "1/3 NetworkPolicy presente in ogni namespace del progetto..."
for namespace in $(kubectl get namespaces -l project=onepiece-api -o name | cut -d/ -f2); do
  kubectl get networkpolicy "$POLICY_NAME" -n "$namespace" >/dev/null 2>&1 \
    || fail "NetworkPolicy $POLICY_NAME assente nel namespace $namespace"
done

log "2/3 un pod senza eccezione non raggiunge i metadata..."
blocked="$(probe metadata-probe-blocked)"
[ -n "$blocked" ] || fail "sonda senza eccezione non eseguita"
[ "$blocked" != "0" ] || fail "pod senza eccezione ha raggiunto $METADATA_URL"

log "3/3 un pod con l'eccezione li raggiunge (se l'ambiente li espone)..."
allowed="$(probe metadata-probe-allowed "$EXCEPTION_LABEL")"
if [ "$allowed" = "0" ]; then
  log "eccezione verificata."
else
  warn "metadata non raggiungibili da questo ambiente (curl exit $allowed): eccezione non verificabile qui."
fi

[ "$failures" -eq 0 ] || { error "$failures verifiche fallite"; exit 1; }
log "NetworkPolicy sui metadata verificata."
