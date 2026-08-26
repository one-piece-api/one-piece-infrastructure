#!/usr/bin/env bash
# Imposta esplicitamente lo User Profile del realm "onepiece" via Admin API
# dopo l'import: il profilo dichiarativo di default (Keycloak 26) lascia
# "email" modificabile dall'utente stesso sulla schermata hosted "Update
# Account Information" (required action UPDATE_PROFILE, Step 5/UF-IDU-02) -
# un utente potrebbe quindi cambiare il proprio indirizzo senza una nuova
# verifica, vanificando la garanzia di VERIFY_EMAIL (UF-IDU-04). Qui si
# restringe il permesso di modifica di "email" al solo ADMIN (la view resta
# concessa anche a "user", il campo compare comunque, sola lettura).
#
# "username" resta modificabile dall'utente (governato da
# "editUsernameAllowed" in keycloak/realm-onepiece.json - vedi
# docs/adr/0003-activation-via-keycloak-required-actions.md in
# one-piece-user-service per il perché quel flag, da solo, non basta a
# rendere editabile lo username sulla stessa schermata senza un profilo
# esplicito come questo). "firstName"/"lastName" restano modificabili
# dall'utente di proposito: sono richiesti in quello stesso passaggio e mai
# precompilati dal flusso di invito (KeycloakUserDirectoryAdapter non li
# imposta) - renderli sola-lettura bloccherebbe l'attivazione.
#
# Non incorporato nel realm export/import JSON ("components" ->
# declarative-user-profile): è un percorso noto per non essere affidabile
# nell'import di Keycloak per lo User Profile dichiarativo (es.
# keycloak/keycloak#23970, adorsys/keycloak-config-cli#979) - stesso motivo
# per cui la password SMTP (hook accanto a questo) viene impostata via
# Admin API post-import invece che nel JSON del realm.
#
# Hook postsync della release "keycloak" in helmfile.yaml.gotmpl, in ogni
# ambiente (nessun segreto coinvolto - la configurazione è identica
# ovunque). Usa kcadm.sh via "kubectl exec" come configure-realm-smtp.sh
# (l'immagine ufficiale non include curl, keycloak/keycloak#17438).

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Placeholder locale (KC_BOOTSTRAP_ADMIN_PASSWORD in keycloak/values-keycloakx.yaml),
# non un segreto reale - stesso pattern di configure-realm-smtp.sh.
kc_admin_password="admin-change-me-locally"

kubectl exec -i -n auth statefulset/keycloak -- bash -c 'cat > /tmp/onepiece-user-profile-config.json' <<'JSON'
{
  "attributes" : [ {
    "name" : "username",
    "displayName" : "${username}",
    "validations" : {
      "length" : { "min" : 3, "max" : 255 },
      "username-prohibited-characters" : { },
      "up-username-not-idn-homograph" : { }
    },
    "permissions" : { "view" : [ "admin", "user" ], "edit" : [ "admin", "user" ] },
    "multivalued" : false
  }, {
    "name" : "email",
    "displayName" : "${email}",
    "validations" : {
      "email" : { },
      "length" : { "max" : 255 }
    },
    "required" : { "roles" : [ "user" ] },
    "permissions" : { "view" : [ "admin", "user" ], "edit" : [ "admin" ] },
    "multivalued" : false
  }, {
    "name" : "firstName",
    "displayName" : "${firstName}",
    "validations" : {
      "length" : { "max" : 255 },
      "person-name-prohibited-characters" : { }
    },
    "required" : { "roles" : [ "user" ] },
    "permissions" : { "view" : [ "admin", "user" ], "edit" : [ "admin", "user" ] },
    "multivalued" : false
  }, {
    "name" : "lastName",
    "displayName" : "${lastName}",
    "validations" : {
      "length" : { "max" : 255 },
      "person-name-prohibited-characters" : { }
    },
    "required" : { "roles" : [ "user" ] },
    "permissions" : { "view" : [ "admin", "user" ], "edit" : [ "admin", "user" ] },
    "multivalued" : false
  } ],
  "groups" : [ {
    "name" : "user-metadata",
    "displayHeader" : "User metadata",
    "displayDescription" : "Attributes, which refer to user metadata"
  } ]
}
JSON

kubectl exec -n auth statefulset/keycloak -- bash -c '
  set -euo pipefail
  /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user admin --password "$1"
  /opt/keycloak/bin/kcadm.sh update realms/onepiece/users/profile -f /tmp/onepiece-user-profile-config.json
  rm /tmp/onepiece-user-profile-config.json
' bash "$kc_admin_password"

echo "[configure-user-profile] User Profile del realm 'onepiece' impostato (email non modificabile dall'utente)."
