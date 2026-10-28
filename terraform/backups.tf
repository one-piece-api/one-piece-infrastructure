# Backup logici del database (ADR-0027, piano production-remote D5): un
# CronJob pg_dump giornaliero scrive qui, Object Storage cancella i dump più
# vecchi di backup_retention_days. Always Free: 20 GB e 50.000 richieste al
# mese, ampiamente sopra un dump al giorno.

data "oci_objectstorage_namespace" "onepiece" {
  compartment_id = var.tenancy_ocid
}

locals {
  backup_retention_days = 14
}

resource "oci_objectstorage_bucket" "backups" {
  compartment_id = oci_identity_compartment.onepiece.id
  namespace      = data.oci_objectstorage_namespace.onepiece.namespace
  name           = "onepiece-backups"
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"
  versioning     = "Disabled"
}

resource "oci_objectstorage_object_lifecycle_policy" "backups" {
  namespace = data.oci_objectstorage_namespace.onepiece.namespace
  bucket    = oci_objectstorage_bucket.backups.name

  rules {
    name        = "delete-after-${local.backup_retention_days}-days"
    action      = "DELETE"
    target      = "objects"
    is_enabled  = true
    time_amount = local.backup_retention_days
    time_unit   = "DAYS"
  }

  depends_on = [oci_identity_policy.object_storage_lifecycle]
}
