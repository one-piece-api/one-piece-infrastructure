# Subnet pubblica unica con la sola VM k3s (ADR-0027). Aperte a internet solo
# la 443 (da Cloudflare) e WireGuard; il firewall della VM ripete gli stessi
# limiti (cloud-init.yaml.tftpl).

resource "oci_core_vcn" "onepiece" {
  compartment_id = oci_identity_compartment.onepiece.id
  cidr_blocks    = ["10.0.0.0/16"]
  display_name   = "onepiece-vcn"
  dns_label      = "onepiece"
}

resource "oci_core_internet_gateway" "onepiece" {
  compartment_id = oci_identity_compartment.onepiece.id
  vcn_id         = oci_core_vcn.onepiece.id
  display_name   = "onepiece-igw"
  enabled        = true
}

resource "oci_core_route_table" "public" {
  compartment_id = oci_identity_compartment.onepiece.id
  vcn_id         = oci_core_vcn.onepiece.id
  display_name   = "onepiece-public-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.onepiece.id
  }
}

resource "oci_core_security_list" "onepiece" {
  compartment_id = oci_identity_compartment.onepiece.id
  vcn_id         = oci_core_vcn.onepiece.id
  display_name   = "onepiece-public-sl"

  # Accesso di CI e proprietario (API di Kubernetes, SSH) solo dal tunnel.
  ingress_security_rules {
    protocol    = "17" # UDP
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    description = "WireGuard (ADR-0027)"
    udp_options {
      min = local.wireguard_port
      max = local.wireguard_port
    }
  }

  # Unico ingresso HTTP(S): la 443 solo da Cloudflare (ADR-0020), l'origin
  # non è raggiungibile in altro modo. ServiceLB di k3s la apre sulla VM. Con la modalità Full (strict)
  # Cloudflare contatta l'origin solo sulla 443, quindi la 80 non gli serve.
  # Gli intervalli arrivano dal provider Cloudflare, non da un elenco a mano.
  dynamic "ingress_security_rules" {
    for_each = data.cloudflare_ip_ranges.current.ipv4_cidrs
    content {
      protocol    = "6"
      source      = ingress_security_rules.value
      source_type = "CIDR_BLOCK"
      description = "HTTPS (Gateway) - solo da Cloudflare, ADR-0020"
      tcp_options {
        min = 443
        max = 443
      }
    }
  }

  ingress_security_rules {
    protocol    = "all"
    source      = "10.0.0.0/16"
    source_type = "CIDR_BLOCK"
    description = "Traffico interno alla VCN"
  }

  egress_security_rules {
    protocol         = "all"
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    description      = "Tutto il traffico in uscita"
  }
}

resource "oci_core_subnet" "public" {
  compartment_id             = oci_identity_compartment.onepiece.id
  vcn_id                     = oci_core_vcn.onepiece.id
  cidr_block                 = "10.0.1.0/24"
  display_name               = "onepiece-public-subnet"
  dns_label                  = "public"
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.onepiece.id]
  prohibit_public_ip_on_vnic = false
}

# IP pubblico riservato dell'origin, assegnato all'IP privato della VM
# (ADR-0027): Cloudflare punta qui (cloudflare.tf), i peer WireGuard pure. Il
# limite Always Free di questo tenancy è 1 IP riservato: prima va liberato dal
# vecchio Load Balancer (piano k3s-remote, K4).
resource "oci_core_public_ip" "ingress" {
  compartment_id = oci_identity_compartment.onepiece.id
  display_name   = "onepiece-ingress-ip"
  lifetime       = "RESERVED"
  private_ip_id  = data.oci_core_private_ips.k3s.private_ips[0].id
}

# Stesso indirizzo di prima (84.8.249.65): rinominato, non ricreato.
moved {
  from = oci_core_public_ip.lb
  to   = oci_core_public_ip.ingress
}
