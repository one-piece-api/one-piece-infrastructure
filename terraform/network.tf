# Topologia semplificata a subnet pubblica unica (endpoint API + nodi + LB):
# scelta adeguata a un singolo ambiente dev senza requisiti di alta
# disponibilità (vedi ADR-0005). Per un setup più isolato/hardened, la
# topologia standard OKE prevede subnet separate per endpoint/nodi/LB/pod
# (vedi documentazione OCI sul networking dei cluster).

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

  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    description = "Kubernetes API server (kubectl da qualunque rete)"
    tcp_options {
      min = 6443
      max = 6443
    }
  }

  ingress_security_rules {
    protocol    = "6"
    source      = var.allowed_client_cidr
    source_type = "CIDR_BLOCK"
    description = "HTTP (ingress-nginx) - solo dal CIDR autorizzato, vedi var.allowed_client_cidr"
    tcp_options {
      min = 80
      max = 80
    }
  }

  ingress_security_rules {
    protocol    = "6"
    source      = var.allowed_client_cidr
    source_type = "CIDR_BLOCK"
    description = "HTTPS (ingress-nginx) - solo dal CIDR autorizzato, vedi var.allowed_client_cidr"
    tcp_options {
      min = 443
      max = 443
    }
  }

  ingress_security_rules {
    protocol    = "6"
    source      = "10.0.1.0/24"
    source_type = "CIDR_BLOCK"
    description = "NodePort: solo dalla Load Balancer, che vive nella stessa subnet"
    tcp_options {
      min = 30000
      max = 32767
    }
  }

  ingress_security_rules {
    protocol    = "all"
    source      = "10.0.0.0/16"
    source_type = "CIDR_BLOCK"
    description = "Traffico interno alla VCN (control plane <-> kubelet, health check OKE)"
  }

  ingress_security_rules {
    protocol    = "6"
    source      = "10.0.1.0/24"
    source_type = "CIDR_BLOCK"
    # Porta fissa usata da kube-proxy per l'health check dei node dal Load
    # Balancer (esternalTrafficPolicy) - OCI la aggiunge automaticamente
    # alla security list alla creazione del primo Service LoadBalancer, ma
    # non essendo dichiarata qui verrebbe rimossa a ogni apply successivo,
    # rompendo l'health check.
    description = "Health check del Load Balancer verso i node (kube-proxy, porta fissa)"
    tcp_options {
      min = 10256
      max = 10256
    }
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

# IP pubblico riservato per il Load Balancer di ingress-nginx (ADR-0005):
# senza dominio, oauth2-proxy/Keycloak devono usare un indirizzo noto in
# anticipo (non solo dopo la creazione del LB) per costruire URL di
# redirect OAuth2 raggiungibili dal browser - vedi
# helmfile.yaml.gotmpl (annotazione oci.oraclecloud.com/reserved-ips).
# Dentro l'allowance Always Free (fino a 2 IP pubblici riservati).
resource "oci_core_public_ip" "lb" {
  compartment_id = oci_identity_compartment.onepiece.id
  display_name   = "onepiece-lb-ip"
  lifetime       = "RESERVED"

  lifecycle {
    # L'assegnazione alla private IP del Load Balancer è gestita da
    # Kubernetes (annotazione oci.oraclecloud.com/reserved-ips sul Service
    # ingress-nginx), non da qui: senza questo, un apply successivo alla
    # prima associazione prova a scollegare l'IP dal LB, rompendo l'accesso
    # pubblico.
    ignore_changes = [private_ip_id]
  }
}
