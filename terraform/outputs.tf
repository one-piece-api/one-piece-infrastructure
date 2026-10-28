output "compartment_id" {
  value = oci_identity_compartment.onepiece.id
}

output "vault_id" {
  value = oci_kms_vault.onepiece.id
}

output "vault_key_id" {
  value = oci_kms_key.onepiece.id
}

output "ingress_ip" {
  value = oci_core_public_ip.ingress.ip_address
}

output "instance_id" {
  value = oci_core_instance.k3s.id
}

# Endpoint dei peer WireGuard (CI e proprietario).
output "wireguard_endpoint" {
  value = "${oci_core_public_ip.ingress.ip_address}:${local.wireguard_port}"
}

output "backup_bucket" {
  value = oci_objectstorage_bucket.backups.name
}

# Namespace Object Storage del tenancy: OCI_OBJECT_STORAGE_NAMESPACE del
# deploy, usato dal CronJob dei backup (helmfile.yaml.gotmpl).
output "object_storage_namespace" {
  value = data.oci_objectstorage_namespace.onepiece.namespace
}

output "subnet_id" {
  value = oci_core_subnet.public.id
}

output "region" {
  value = var.region
}
