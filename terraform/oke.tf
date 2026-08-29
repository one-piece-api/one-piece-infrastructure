data "oci_identity_availability_domains" "ads" {
  compartment_id = oci_identity_compartment.onepiece.id
}

data "oci_identity_fault_domains" "ads" {
  compartment_id      = oci_identity_compartment.onepiece.id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
}

data "oci_containerengine_cluster_option" "onepiece" {
  cluster_option_id = "all"
  compartment_id    = oci_identity_compartment.onepiece.id
}

locals {
  # Ultima versione Kubernetes supportata da OKE al momento dell'apply,
  # non fissata a mano (coerente con la policy di versioning del progetto:
  # verificata al momento, non assunta da memoria).
  kubernetes_version = data.oci_containerengine_cluster_option.onepiece.kubernetes_versions[
    length(data.oci_containerengine_cluster_option.onepiece.kubernetes_versions) - 1
  ]
}

resource "oci_containerengine_cluster" "onepiece" {
  compartment_id     = oci_identity_compartment.onepiece.id
  name               = "onepiece-remote"
  vcn_id             = oci_core_vcn.onepiece.id
  kubernetes_version = local.kubernetes_version

  # Basic (non Enhanced): control plane gratuito, vedi ADR-0005.
  type = "BASIC_CLUSTER"

  endpoint_config {
    is_public_ip_enabled = true
    subnet_id            = oci_core_subnet.public.id
  }

  # Flannel invece di VCN-native: nessuna subnet dedicata ai pod da
  # dimensionare, scelta più semplice per un cluster dev a singolo nodo.
  cluster_pod_network_options {
    cni_type = "FLANNEL_OVERLAY"
  }
}

data "oci_containerengine_node_pool_option" "onepiece" {
  node_pool_option_id = oci_containerengine_cluster.onepiece.id
  compartment_id      = oci_identity_compartment.onepiece.id
}

locals {
  # Filtra l'immagine Oracle Linux compatibile con lo shape ARM (aarch64).
  # Se questa lista comprehension fallisce (nessun match), verificare i
  # `source_name` disponibili con:
  #   terraform console -> data.oci_containerengine_node_pool_option.onepiece.sources
  a1_image_id = [
    for source in data.oci_containerengine_node_pool_option.onepiece.sources :
    source.image_id if can(regex("aarch64", source.source_name))
  ][0]
}

resource "oci_containerengine_node_pool" "a1" {
  cluster_id         = oci_containerengine_cluster.onepiece.id
  compartment_id     = oci_identity_compartment.onepiece.id
  name               = "pool-a1"
  kubernetes_version = local.kubernetes_version
  node_shape         = "VM.Standard.A1.Flex"

  # 1 OCPU/6 GB per nodo: NON alzare ocpus qui per dare più CPU al nodo
  # esistente - OKE non fa resize in-place di uno shape già in esecuzione,
  # richiede "instance-mode cycling" (distruggi e ricrea il nodo), che
  # rimette in coda per la scarsa capacità Ampere A1 in eu-turin-1 (lo
  # stesso problema aggirato con fatica in precedenza). Per più capacità,
  # aggiungere un secondo nodo (node_config_details.size sotto) invece di
  # ridimensionare questo.
  node_shape_config {
    ocpus         = 1
    memory_in_gbs = 6
  }

  node_source_details {
    source_type             = "IMAGE"
    image_id                = local.a1_image_id
    boot_volume_size_in_gbs = 50
  }

  node_config_details {
    # 2 nodi da 1 OCPU/6 GB ciascuno invece di ridimensionare quello già
    # esistente (vedi commento su node_shape_config sopra) - stesso
    # allotment Always Free totale (2 OCPU/12 GB), ma senza toccare il nodo
    # già funzionante: se la capacità per il secondo nodo non si trova, il
    # primo resta comunque intatto.
    size = 2

    placement_configs {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
      subnet_id            = oci_core_subnet.public.id
      # Fault domain esplicito (ciclato tra i retry con -var fault_domain_index=N,
      # vedi terraform/README.md) oppure non specificato (-1 = auto-assegnato
      # da Oracle) per verificare se l'auto-assegnazione trova capacità diversa
      # da quella esplicitamente richiesta finora.
      fault_domains = var.fault_domain_index >= 0 ? [
        data.oci_identity_fault_domains.ads.fault_domains[var.fault_domain_index].name
      ] : null
    }
  }
}
