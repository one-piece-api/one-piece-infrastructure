# VM del remoto (ADR-0027): una A1 Always Free con k3s a nodo singolo,
# installato da cloud-init (cloud-init.yaml.tftpl), più un volume dati per i
# PersistentVolume di local-path, separato dal sistema operativo.

data "oci_identity_availability_domains" "ads" {
  compartment_id = oci_identity_compartment.onepiece.id
}

data "oci_identity_fault_domains" "ads" {
  compartment_id      = oci_identity_compartment.onepiece.id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
}

# Ubuntu 24.04 per lo shape A1 (il filtro sullo shape tiene solo le immagini
# aarch64), la più recente per prima. Le release successive non ricreano la
# VM: vedi ignore_changes sotto.
data "oci_core_images" "ubuntu_a1" {
  compartment_id           = oci_identity_compartment.onepiece.id
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = local.vm_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

locals {
  vm_shape = "VM.Standard.A1.Flex"

  # Tutto l'allotment A1 Always Free (2 OCPU / 12 GB) su una VM.
  vm_ocpus         = 2
  vm_memory_in_gbs = 12

  # 50 GB di boot + 50 GB di dati: 100 dei 200 GB Always Free. 10 VPU per GB
  # (Balanced) è il minimo per un boot volume; livelli più alti sono a
  # pagamento.
  boot_volume_size_in_gbs = 50
  data_volume_size_in_gbs = 50
  volume_vpus_per_gb      = 10

  # Percorso stabile del primo volume dati (consistent device paths delle
  # immagini OCI): cloud-init lo aspetta, lo formatta solo se vuoto e lo
  # monta su data_mount_path.
  data_volume_device = "/dev/oracleoci/oraclevdb"
  data_mount_path    = "/data"

  # WireGuard (ADR-0027): unica porta aperta a internet oltre alla 443. Rete
  # del tunnel fuori da VCN (10.0.0.0/16) e da pod e Service di k3s
  # (10.42.0.0/16, 10.43.0.0/16).
  wireguard_port       = 51820
  wireguard_server_ip  = "10.99.0.1"
  wireguard_ci_ip      = "10.99.0.2"
  wireguard_owner_ip   = "10.99.0.3"
  wireguard_prefix_len = 24
}

resource "oci_core_instance" "k3s" {
  compartment_id      = oci_identity_compartment.onepiece.id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  # Fault domain esplicito (ciclato tra i retry con -var fault_domain_index=N
  # in caso di "Out of host capacity", vedi README.md) o scelto da Oracle (-1).
  fault_domain = var.fault_domain_index >= 0 ? data.oci_identity_fault_domains.ads.fault_domains[var.fault_domain_index].name : null
  display_name = "onepiece-k3s"
  shape        = local.vm_shape

  shape_config {
    ocpus         = local.vm_ocpus
    memory_in_gbs = local.vm_memory_in_gbs
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_a1.images[0].id
    boot_volume_size_in_gbs = local.boot_volume_size_in_gbs
    boot_volume_vpus_per_gb = local.volume_vpus_per_gb
  }

  create_vnic_details {
    subnet_id = oci_core_subnet.public.id
    # Nessun IP effimero: l'IP pubblico è quello riservato (network.tf).
    assign_public_ip = false
    hostname_label   = "k3s"
  }

  # Solo IMDSv2 (header di autorizzazione obbligatorio): l'instance principal
  # di ESO e del CronJob dei backup lo usa già.
  instance_options {
    are_legacy_imds_endpoints_disabled = true
  }

  metadata = {
    ssh_authorized_keys = var.owner_ssh_public_key
    user_data = base64encode(templatefile("${path.module}/cloud-init.yaml.tftpl", {
      k3s_version          = var.k3s_version
      data_volume_device   = local.data_volume_device
      data_mount_path      = local.data_mount_path
      wireguard_port       = local.wireguard_port
      wireguard_server_ip  = local.wireguard_server_ip
      wireguard_ci_ip      = local.wireguard_ci_ip
      wireguard_owner_ip   = local.wireguard_owner_ip
      wireguard_prefix_len = local.wireguard_prefix_len
      wireguard_ci_key     = var.wireguard_ci_public_key
      wireguard_owner_key  = var.wireguard_owner_public_key
      cloudflare_ipv4      = data.cloudflare_ip_ranges.current.ipv4_cidrs
    }))
  }

  lifecycle {
    # Una nuova immagine Ubuntu non ricrea la VM (gli aggiornamenti arrivano
    # da unattended-upgrades). cloud-init gira solo al primo boot: le
    # modifiche successive (peer, versione k3s) si applicano sulla VM, non
    # ricreandola. Ricreazione voluta: terraform apply -replace.
    ignore_changes = [
      source_details[0].source_id,
      metadata["user_data"],
    ]
  }
}

resource "oci_core_volume" "data" {
  compartment_id      = oci_identity_compartment.onepiece.id
  availability_domain = oci_core_instance.k3s.availability_domain
  display_name        = "onepiece-k3s-data"
  size_in_gbs         = local.data_volume_size_in_gbs
  vpus_per_gb         = local.volume_vpus_per_gb

  # Contiene i dati di PostgreSQL: mai cancellato da un apply.
  lifecycle {
    prevent_destroy = true
  }
}

resource "oci_core_volume_attachment" "data" {
  attachment_type = "paravirtualized"
  instance_id     = oci_core_instance.k3s.id
  volume_id       = oci_core_volume.data.id
  device          = local.data_volume_device
}

# IP privato primario della VM: riceve l'IP pubblico riservato (network.tf).
data "oci_core_vnic_attachments" "k3s" {
  compartment_id = oci_identity_compartment.onepiece.id
  instance_id    = oci_core_instance.k3s.id
}

data "oci_core_private_ips" "k3s" {
  vnic_id = data.oci_core_vnic_attachments.k3s.vnic_attachments[0].vnic_id
}
