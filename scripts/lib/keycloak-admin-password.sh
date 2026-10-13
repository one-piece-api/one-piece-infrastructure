#!/usr/bin/env bash
# Imposta kc_admin_password dal Secret one-piece-keycloak-admin-credentials
# (chart "credentials": placeholder in locale/CI, Vault in remote). Va incluso
# con "source", dopo che il cluster è raggiungibile.

kc_admin_password="$(kubectl get secret one-piece-keycloak-admin-credentials -n auth \
  -o jsonpath='{.data.password}' | base64 -d)"
