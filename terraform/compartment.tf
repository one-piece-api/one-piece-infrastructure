resource "oci_identity_compartment" "onepiece" {
  compartment_id = var.tenancy_ocid
  name           = "onepiece"
  description    = "Risorse del progetto one-piece-api (ambiente remoto dev, vedi ADR-0005)"
  enable_delete  = true
}
