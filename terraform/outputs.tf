data "oci_containerengine_cluster_kube_config" "onepiece" {
  cluster_id = oci_containerengine_cluster.onepiece.id
}

resource "local_file" "kubeconfig" {
  content         = data.oci_containerengine_cluster_kube_config.onepiece.content
  filename        = "${path.module}/kubeconfig"
  file_permission = "0600"
}

output "cluster_id" {
  value = oci_containerengine_cluster.onepiece.id
}

output "compartment_id" {
  value = oci_identity_compartment.onepiece.id
}

output "vault_id" {
  value = oci_kms_vault.onepiece.id
}

output "vault_key_id" {
  value = oci_kms_key.onepiece.id
}

output "kubeconfig_path" {
  value = local_file.kubeconfig.filename
}

output "lb_ip" {
  value = oci_core_public_ip.lb.ip_address
}

output "subnet_id" {
  value = oci_core_subnet.public.id
  # Necessario per il Service LoadBalancer di ingress-nginx: con la
  # topologia a subnet unica (network.tf) il cloud-controller-manager OCI
  # non riesce a dedurla da sé ("a subnet must be specified") - va passata
  # esplicitamente via l'annotazione oci-load-balancer-subnet1, vedi
  # helmfile.yaml.gotmpl.
}
