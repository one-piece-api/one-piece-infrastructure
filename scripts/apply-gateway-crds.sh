#!/usr/bin/env bash
# Applica le CRD della Gateway API e di Envoy Gateway (ADR-0019) alla
# versione data, prima del sync della release "envoy-gateway".
#
# Hook presync della release "envoy-gateway" in helmfile.yaml.gotmpl, in
# ogni ambiente. Perché non lasciarle al chart gateway-helm (crds.enabled):
# lì stanno nella cartella crds/, che Helm installa solo la prima volta e
# non aggiorna mai - un upgrade di Envoy Gateway resterebbe con le CRD
# vecchie. È il metodo indicato dal README di gateway-crds-helm: "helm
# template" + "kubectl apply --server-side" (le CRD sono troppo grandi per
# un'apply client-side e per il Secret di una release Helm).
#
# Uso: scripts/apply-gateway-crds.sh <versione Envoy Gateway, es. v1.9.2>

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

version="${1:?versione di Envoy Gateway richiesta, es. v1.9.2}"

# Download e render separati: con un riferimento oci:// diretto, Helm 4
# stampa "Pulled:/Digest:" sullo stdout di "helm template", mescolandoli al
# manifest (kubectl lo rifiuta con "apiVersion not set").
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

helm pull oci://docker.io/envoyproxy/gateway-crds-helm \
  --version "$version" --untar --untardir "$workdir" >/dev/null

helm template gateway-crds "$workdir/gateway-crds-helm" \
  --set crds.gatewayAPI.enabled=true \
  --set crds.envoyGateway.enabled=true \
  >"$workdir/crds.yaml"

kubectl apply --server-side --force-conflicts -f "$workdir/crds.yaml" >/dev/null

echo "[apply-gateway-crds] CRD Gateway API + Envoy Gateway $version applicate."
