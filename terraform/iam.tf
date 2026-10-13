# Accesso di External Secrets Operator al Vault (PR0, piano production-remote).
# Instance principal: i nodi OKE (istanze del compartment) si autenticano a OCI
# con l'identità dell'istanza, nessuna chiave API né segreto nello state. La
# workload identity per-pod richiederebbe un cluster Enhanced (a pagamento,
# fuori da Always Free - ADR-0005). IAM è gratuito.
# Il dynamic group vive nel tenancy, la policy nel compartment del progetto.

resource "oci_identity_dynamic_group" "oke_nodes" {
  compartment_id = var.tenancy_ocid
  name           = "onepiece-oke-nodes"
  description    = "Nodi OKE del compartment onepiece (instance principal di External Secrets Operator)"
  matching_rule  = "ALL {instance.compartment.id = '${oci_identity_compartment.onepiece.id}'}"
}

# Sola lettura dei secret: ESO non crea né modifica nulla nel Vault.
resource "oci_identity_policy" "eso_read_secrets" {
  compartment_id = oci_identity_compartment.onepiece.id
  name           = "onepiece-eso-read-secrets"
  description    = "External Secrets Operator legge i secret del Vault dai nodi OKE"
  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.oke_nodes.name} to read secret-family in compartment id ${oci_identity_compartment.onepiece.id}",
  ]
}
