#!/usr/bin/env bash
# Riconcilia il realm "onepiece" con keycloak/realm-onepiece.json via
# keycloak-config-cli, non solo "crea se manca" come "--import-realm"
# (bug noto, vedi il commento in testa a apply-realm-configmap.sh) - vedi
# docs/adr/0011-keycloak-config-cli-realm-sync.md per il contesto completo.
#
# Un Job è immutabile: va eliminato e riapplicato esplicitamente ad ogni
# sync per farlo rieseguire, anche quando il suo manifest non cambia (il
# contenuto reale - la ConfigMap del realm - può essere cambiato, o il
# realm può aver driftato per una modifica manuale via Admin Console).
#
# Hook postsync della release "keycloak" in helmfile.yaml.gotmpl, in ogni
# ambiente (stesso pattern di configure-realm-smtp.sh) - gira dopo
# apply-realm-configmap.sh (presync) e dopo che Keycloak è pronto.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

kubectl delete job/keycloak-config-cli -n auth --ignore-not-found

kubectl apply -f keycloak/config-cli-job.yaml

if ! kubectl wait --for=condition=complete --timeout=180s job/keycloak-config-cli -n auth; then
  echo "[sync-realm-config] keycloak-config-cli non ha completato con successo, log del pod:" >&2
  kubectl logs -n auth job/keycloak-config-cli --tail=200 >&2 || true
  exit 1
fi

echo "[sync-realm-config] Realm 'onepiece' riconciliato con realm-onepiece.json."
