#!/usr/bin/env bash
# Aggiunge l'IP pubblico riservato ai redirect URI dei client "onepiece-proxy"
# e "account" (quest'ultimo per la cancellazione self-service dell'account,
# ADR-0013 - deleteAccountUrl() in one-piece-user-frontend costruisce
# redirect_uri dall'origin corrente dell'app), solo nell'ambiente "remote" -
# keycloak/realm-onepiece.json resta fisso su "localhost" (locale/CI, unica
# source of truth per quegli ambienti), e "--import-realm" non aggiorna un
# client già esistente in un realm già importato (bug noto, vedi il commento
# in apply-realm-configmap.sh), quindi il redirect URI per l'ambiente remoto
# va corretto via Admin API dopo ogni sync, non nel JSON.
#
# Hook postsync della release "keycloak" in helmfile.yaml, sempre invocato
# ma no-op fuori da "remote" (stesso pattern di configure-realm-smtp.sh).

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [ "${HELMFILE_ENVIRONMENT:-default}" != "remote" ]; then
  exit 0
fi

: "${OCI_LB_IP:?OCI_LB_IP non impostata - richiesta in \"remote\" (terraform output -raw lb_ip)}"

# Placeholder locale (KC_BOOTSTRAP_ADMIN_PASSWORD in keycloak/values-keycloakx.yaml),
# non un segreto reale - stesso pattern già usato in configure-realm-smtp.sh.
kc_admin_password="admin-change-me-locally"

kubectl exec -n auth statefulset/keycloak -- bash -c '
  set -euo pipefail
  /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user admin --password "$1"

  proxy_client_id="$(/opt/keycloak/bin/kcadm.sh get clients -r onepiece -q clientId=onepiece-proxy --fields id --format csv --noquotes)"
  /opt/keycloak/bin/kcadm.sh update "clients/$proxy_client_id" -r onepiece \
    -s "redirectUris=[\"http://localhost:4180/oauth2/callback\",\"http://localhost:4180/\",\"http://$2/oauth2/callback\",\"http://$2/\"]" \
    -s "attributes.\"post.logout.redirect.uris\"=\"http://localhost:4180/*##http://$2/*\""

  account_client_id="$(/opt/keycloak/bin/kcadm.sh get clients -r onepiece -q clientId=account --fields id --format csv --noquotes)"
  /opt/keycloak/bin/kcadm.sh update "clients/$account_client_id" -r onepiece \
    -s "redirectUris=[\"/realms/onepiece/account/*\",\"http://localhost:4180/*\",\"http://$2/*\"]"
' bash "$kc_admin_password" "$OCI_LB_IP"

echo "[configure-remote-redirect-uris] redirect URI dei client 'onepiece-proxy' e 'account' aggiornati per $OCI_LB_IP."
