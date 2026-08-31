#!/usr/bin/env bash
# Porta un realm "onepiece" già esistente in linea con l'attuale
# keycloak/realm-onepiece.json per tre cose che "--import-realm" non
# aggiorna su entità già presenti (bug noto, keycloak/keycloak#14884, vedi
# anche apply-realm-configmap.sh e configure-remote-redirect-uris.sh):
#
#   1. i permessi client-role "roles:read"/"roles:assign"/"roles:manage"
#      possono mancare, o essere ancora presenti sotto il vecchio nome
#      "roles:write" (rinominato in ADR-0011/0012 di one-piece-user-service);
#   2. il ruolo ADMIN può ancora avere "roles:write" tra i suoi composite
#      invece dei tre permessi correnti;
#   3. il service account "user-service-admin" può non avere ancora
#      manage-realm/manage-clients/view-clients/query-clients (necessari per
#      creare/eliminare ruoli e permessi via Admin API, vedi ADR-0012 - solo
#      "manage-realm" non basta: Keycloak tratta la gestione dei ruoli realm
#      e quella dei ruoli client come due permessi separati).
#
# Idempotente: ogni passo controlla lo stato attuale prima di agire, quindi
# è sicuro rieseguirlo (compreso un realm già completamente allineato, dove
# non fa nulla) - stesso principio di ogni altro hook postsync qui accanto.
#
# Hook postsync della release "keycloak" in helmfile.yaml.gotmpl, in ogni
# ambiente (nessun segreto coinvolto). Usa kcadm.sh via "kubectl exec" come
# gli altri hook (l'immagine ufficiale non include curl, keycloak/keycloak#17438).

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Placeholder locale (KC_BOOTSTRAP_ADMIN_PASSWORD in keycloak/values-keycloakx.yaml),
# non un segreto reale - stesso pattern di configure-realm-smtp.sh.
kc_admin_password="admin-change-me-locally"

kubectl exec -n auth statefulset/keycloak -- bash -c '
  set -euo pipefail
  /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user admin --password "$1"

  cid=$(/opt/keycloak/bin/kcadm.sh get clients -r onepiece -q clientId=onepiece-proxy --fields id --format csv --noquotes | tail -n1)
  existing_perms=$(/opt/keycloak/bin/kcadm.sh get "clients/$cid/roles" -r onepiece --fields name --format csv --noquotes)

  ensure_permission() {
    if ! printf "%s\n" "$existing_perms" | grep -qx "$1"; then
      /opt/keycloak/bin/kcadm.sh create "clients/$cid/roles" -r onepiece -s "name=$1" -s "description=$2"
    fi
  }
  ensure_permission "roles:read" "View the role/permission registry"
  ensure_permission "roles:assign" "Assign or revoke a crew member'"'"'s roles"
  ensure_permission "roles:manage" "Create/delete roles and permissions, assign permissions to roles"

  admin_composites=$(/opt/keycloak/bin/kcadm.sh get-roles -r onepiece --rname ADMIN --cclientid onepiece-proxy --fields name --format csv --noquotes)
  if printf "%s\n" "$admin_composites" | grep -qx "roles:write"; then
    /opt/keycloak/bin/kcadm.sh remove-roles -r onepiece --rname ADMIN --cclientid onepiece-proxy --rolename roles:write
  fi
  for perm in roles:read roles:assign roles:manage; do
    if ! printf "%s\n" "$admin_composites" | grep -qx "$perm"; then
      /opt/keycloak/bin/kcadm.sh add-roles -r onepiece --rname ADMIN --cclientid onepiece-proxy --rolename "$perm"
    fi
  done

  sa_roles=$(/opt/keycloak/bin/kcadm.sh get-roles -r onepiece --uusername service-account-user-service-admin --cclientid realm-management --fields name --format csv --noquotes)
  for role in manage-realm manage-clients view-clients query-clients; do
    if ! printf "%s\n" "$sa_roles" | grep -qx "$role"; then
      /opt/keycloak/bin/kcadm.sh add-roles -r onepiece --uusername service-account-user-service-admin --cclientid realm-management --rolename "$role"
    fi
  done
' bash "$kc_admin_password"

echo "[configure-role-catalog-permissions] roles:manage e i permessi correlati sincronizzati sul realm 'onepiece'."
