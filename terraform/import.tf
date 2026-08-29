# Temporaneo: ispeziona i node pool esistenti nel cluster. Da rimuovere dopo l'uso.
data "oci_containerengine_node_pools" "existing" {
  compartment_id = oci_identity_compartment.onepiece.id
  cluster_id     = oci_containerengine_cluster.onepiece.id
}
