###############################################################################
# Terraform - Container LXC : ldap-01 (OpenLDAP)
# VLAN 20 CORE - pve-03
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
# Variables
# =============================================================================
variable "proxmox_api_url" {
  type    = string
  default = "https://192.168.3.21:8006/"
}

variable "proxmox_api_token_id" {
  type    = string
  default = "root@pam!terraform-token"
}

variable "proxmox_api_token_secret" {
  type      = string
  sensitive = true
}

variable "proxmox_ssh_private_key" {
  type    = string
  default = "/root/.ssh/proxmox_lab"
}

variable "ssh_public_key" {
  type    = string
  default = "/root/.ssh/proxmox_lab.pub"
}

variable "lxc_root_password" {
  type      = string
  sensitive = true
}

variable "ceph_pool" {
  type    = string
  default = "ceph_vm"
}

variable "lxc_template" {
  type    = string
  default = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
}

# =============================================================================
# Provider
# =============================================================================
provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = true

  ssh {
    agent       = false
    username    = "root"
    private_key = file(var.proxmox_ssh_private_key)
  }
}

# =============================================================================
# Container LXC : ldap-01
# =============================================================================
resource "proxmox_virtual_environment_container" "ldap_01" {
  description   = "OpenLDAP - VLAN 20 CORE"
  node_name     = "pve-03"
  vm_id         = 800
  tags          = ["ldap", "openldap", "auth", "vlan20", "core"]
  start_on_boot = true
  unprivileged  = true

  initialization {
    hostname = "ldap-01"

    ip_config {
      ipv4 {
        address = "10.0.20.40/24"
        gateway = "10.0.20.1"
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
    cores        = 1
  }

  memory {
    dedicated = 256
    swap      = 256
  }

  disk {
    datastore_id = var.ceph_pool
    size         = 2
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
    order      = "60"
    up_delay   = "5"
    down_delay = "5"
  }
}

output "ldap_summary" {
  value = {
    hostname  = "ldap-01"
    ip        = "10.0.20.40"
    vlan      = "20 (CORE)"
    node      = "pve-03"
    base_dn   = "dc=infra,dc=lan"
    admin_dn  = "cn=admin,dc=infra,dc=lan"
    ldap_uri  = "ldap://10.0.20.40:389"
  }
}
