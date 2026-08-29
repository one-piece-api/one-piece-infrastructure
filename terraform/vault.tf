# Vault "DEFAULT" (non "VIRTUAL_PRIVATE") con chiave software-protected
# (non HSM): resta nell'allowance Always Free (150 secret, chiavi software
# illimitate — vedi ADR-0005). I valori dei secret NON sono gestiti da
# Terraform (evita di far transitare segreti in chiaro nello state file):
# vanno creati manualmente, vedi README.md di questa cartella.

resource "oci_kms_vault" "onepiece" {
  compartment_id = oci_identity_compartment.onepiece.id
  display_name   = "onepiece-vault"
  vault_type     = "DEFAULT"
}

resource "oci_kms_key" "onepiece" {
  compartment_id       = oci_identity_compartment.onepiece.id
  display_name         = "onepiece-secrets-key"
  management_endpoint  = oci_kms_vault.onepiece.management_endpoint
  protection_mode      = "SOFTWARE"

  key_shape {
    algorithm = "AES"
    length    = 32
  }
}
