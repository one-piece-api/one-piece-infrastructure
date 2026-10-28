# Instance principal (ADR-0025, ADR-0027): la VM si autentica a OCI con la
# propria identità, nessuna chiave API né segreto nello state. La usano ESO
# (lettura del Vault) e il CronJob dei backup (scrittura nel bucket). Una
# NetworkPolicy la nega agli altri pod (helmfile). IAM è gratuito.
# Il dynamic group vive nel tenancy, le policy nel compartment del progetto.

resource "oci_identity_dynamic_group" "instances" {
  compartment_id = var.tenancy_ocid
  name           = "onepiece-instances"
  description    = "Istanze del compartment onepiece (instance principal di ESO e dei backup)"
  matching_rule  = "ALL {instance.compartment.id = '${oci_identity_compartment.onepiece.id}'}"
}

# Il nome di un dynamic group non si cambia in OCI: il rename ricrea gruppo e
# policy, sotto lo stesso indirizzo Terraform.
moved {
  from = oci_identity_dynamic_group.oke_nodes
  to   = oci_identity_dynamic_group.instances
}

# Sola lettura dei secret: ESO non crea né modifica nulla nel Vault.
resource "oci_identity_policy" "eso_read_secrets" {
  compartment_id = oci_identity_compartment.onepiece.id
  name           = "onepiece-eso-read-secrets"
  description    = "External Secrets Operator legge i secret del Vault dalla VM"
  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.instances.name} to read secret-family in compartment id ${oci_identity_compartment.onepiece.id}",
  ]
}

# Il CronJob dei backup crea ed elenca oggetti solo nel bucket dei backup: non
# legge, non sovrascrive e non cancella (la scadenza è della lifecycle policy).
resource "oci_identity_policy" "backup_write" {
  compartment_id = oci_identity_compartment.onepiece.id
  name           = "onepiece-backup-write"
  description    = "Il CronJob pg_dump scrive i dump nel bucket dei backup dalla VM"
  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.instances.name} to manage objects in compartment id ${oci_identity_compartment.onepiece.id} where all {target.bucket.name = '${oci_objectstorage_bucket.backups.name}', any {request.permission = 'OBJECT_CREATE', request.permission = 'OBJECT_INSPECT'}}",
  ]
}

# Object Storage applica le lifecycle policy con la propria identità: senza
# questo permesso la regola dei 14 giorni non viene accettata.
resource "oci_identity_policy" "object_storage_lifecycle" {
  compartment_id = oci_identity_compartment.onepiece.id
  name           = "onepiece-object-storage-lifecycle"
  description    = "Object Storage cancella i dump scaduti (lifecycle policy)"
  statements = [
    "Allow service objectstorage-${var.region} to manage object-family in compartment id ${oci_identity_compartment.onepiece.id}",
  ]
}
