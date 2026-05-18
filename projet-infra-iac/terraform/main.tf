###############################################################################
# Terraform - Provisionnement dns-01 (LXC) sur Proxmox
# Projet Virtualisation M1 - Datacenter Prive
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
  }
}

# =============================================================================
# Provider Proxmox
# =============================================================================
provider "proxmox" {
  endpoint = var.proxmox_api_url

  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"

  insecure = true # Certificat auto-signe Proxmox

  ssh {
    agent    = false
    username = "root"
    # Authentification par cle SSH pour les operations qui ne passent pas par l'API
    private_key = file(var.proxmox_ssh_private_key)
  }
}

# =============================================================================
# Container LXC : dns-01
# =============================================================================
resource "proxmox_virtual_environment_container" "dns_01" {
  description   = "DNS interne Unbound (VLAN 20 CORE)"
  node_name     = var.dns_node # pve-02
  vm_id         = 201
  tags          = ["dns", "core", "vlan20", "infra"]
  start_on_boot = true
  unprivileged  = true

  initialization {
    hostname = "dns-01"

    # Adresse IP statique sur le VLAN 20
    ip_config {
      ipv4 {
        address = "10.0.20.10/24"
        gateway = "10.0.20.1"
      }
    }

    # DNS au boot (avant que Unbound soit installe)
    dns {
      domain  = "infra.lan"
      servers = ["1.1.1.1", "9.9.9.9"]
    }

    user_account {
      password = var.lxc_root_password
      keys     = [trimspace(file(var.ssh_public_key))]
    }
  }

  cpu {
    architecture = "amd64"
    cores        = 1
  }

  memory {
    dedicated = 512
    swap      = 512
  }

  disk {
    datastore_id = var.ceph_pool
    size         = 4
  }

  network_interface {
    name    = "eth0"
    bridge  = "vmbr3"
    vlan_id = 20
  }

  operating_system {
    template_file_id = var.lxc_template
    type             = "debian"
  }

  features {
    nesting = false
  }

  startup {
    order      = "10"
    up_delay   = "5"
    down_delay = "5"
  }
}

# =============================================================================
# Container LXC : pgsql-01 (PostgreSQL 17)
# =============================================================================
resource "proxmox_virtual_environment_container" "pgsql_01" {
  description   = "Base de donnees PostgreSQL 17 (VLAN 50 BACKEND_DB)"
  node_name     = var.db_node
  vm_id         = 301
  tags          = ["postgres", "database", "vlan50", "backend"]
  start_on_boot = true
  unprivileged  = true

  initialization {
    hostname = "pgsql-01"

    ip_config {
      ipv4 {
        address = "10.0.50.10/24"
        gateway = "10.0.50.1"
      }
    }

    dns {
      domain  = "infra.lan"
      servers = ["10.0.20.10", "1.1.1.1"]
    }

    user_account {
      password = var.lxc_root_password
      keys     = [trimspace(file(var.ssh_public_key))]
    }
  }

  cpu {
    architecture = "amd64"
    cores        = 2
  }

  memory {
    dedicated = 1024
    swap      = 512
  }

  disk {
    datastore_id = var.ceph_pool
    size         = 8
  }

  network_interface {
    name    = "eth0"
    bridge  = "vmbr3"
    vlan_id = 50
  }

  operating_system {
    template_file_id = var.lxc_template
    type             = "debian"
  }

  features {
    nesting = false
  }

  startup {
    order      = "20"
    up_delay   = "5"
    down_delay = "5"
  }

  depends_on = [proxmox_virtual_environment_container.dns_01]
}


# =============================================================================
# Cluster Web (web-01, web-02, web-03) - boucle for_each pour anti-affinity
# =============================================================================
locals {
  web_servers = {
    "web-01" = { vmid = 401, node = "pve-01", ip = "10.0.40.11" }
    "web-02" = { vmid = 402, node = "pve-02", ip = "10.0.40.12" }
    "web-03" = { vmid = 403, node = "pve-03", ip = "10.0.40.13" }
  }
}

resource "proxmox_virtual_environment_container" "web" {
  for_each = local.web_servers

  description   = "Serveur web (Nginx + PHP-FPM) - membre du cluster web HA"
  node_name     = each.value.node
  vm_id         = each.value.vmid
  tags          = ["web", "backend", "vlan40", "cluster"]
  start_on_boot = true
  unprivileged  = true

  initialization {
    hostname = each.key
    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = "10.0.40.1"
      }
    }
    dns {
      domain  = "infra.lan"
      servers = ["10.0.20.10", "1.1.1.1"]
    }
    user_account {
      password = var.lxc_root_password
      keys     = [trimspace(file(var.ssh_public_key))]
    }
  }

  cpu {
    cores = 1
  }
  memory {
    dedicated = 512
  }
  disk {
    datastore_id = var.ceph_pool
    size         = 4
  }
  network_interface {
    name    = "eth0"
    bridge  = "vmbr3"
    vlan_id = 40
  }
  operating_system {
    template_file_id = var.lxc_template
    type             = "debian"
  }
  startup {
    order      = "30"
    up_delay   = "5"
    down_delay = "5"
  }

  depends_on = [
    proxmox_virtual_environment_container.dns_01,
    proxmox_virtual_environment_container.pgsql_01
  ]
}

# =============================================================================
# Load Balancers (lb-01, lb-02) - HAProxy + Keepalived
# =============================================================================
locals {
  lb_servers = {
    "lb-01" = { vmid = 411, node = "pve-01", ip = "10.0.40.21", state = "MASTER", priority = 110 }
    "lb-02" = { vmid = 412, node = "pve-02", ip = "10.0.40.22", state = "BACKUP", priority = 100 }
  }
}

resource "proxmox_virtual_environment_container" "lb" {
  for_each = local.lb_servers

  description   = "Load Balancer HAProxy + Keepalived (${each.value.state})"
  node_name     = each.value.node
  vm_id         = each.value.vmid
  tags          = ["loadbalancer", "haproxy", "vlan40"]
  start_on_boot = true
  unprivileged  = true

  initialization {
    hostname = each.key
    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = "10.0.40.1"
      }
    }
    dns {
      domain  = "infra.lan"
      servers = ["10.0.20.10", "1.1.1.1"]
    }
    user_account {
      password = var.lxc_root_password
      keys     = [trimspace(file(var.ssh_public_key))]
    }
  }

  cpu {
    cores = 1
  }
  memory {
    dedicated = 512
  }
  disk {
    datastore_id = var.ceph_pool
    size         = 4
  }
  network_interface {
    name    = "eth0"
    bridge  = "vmbr3"
    vlan_id = 40
  }
  operating_system {
    template_file_id = var.lxc_template
    type             = "debian"
  }
  startup {
    order      = "40"
    up_delay   = "5"
    down_delay = "5"
  }

  depends_on = [proxmox_virtual_environment_container.web]
}
