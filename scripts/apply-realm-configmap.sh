#!/usr/bin/env bash
# Genera e applica la ConfigMap del realm da keycloak/realm-onepiece.json.
#
# Hook presync della release "keycloak" in helmfile.yaml: gira prima di ogni
# sync così la ConfigMap è sempre allineata al realm prima che Keycloak la
# monti, senza mantenere una copia YAML duplicata potenzialmente
# disallineata — realm-onepiece.json resta l'unica source of truth (vedi
# docs/adr/0001-local-auth-stack.md).

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

kubectl create configmap one-piece-realm-config \
  --from-file=realm-onepiece.json=keycloak/realm-onepiece.json \
  -n auth --dry-run=client -o yaml | kubectl apply -f -
