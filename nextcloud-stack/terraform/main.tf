###############################################################################
# Terraform - CT Nextcloud (nextcloud-01)
# CT LXC Debian 13 + Docker pour Nextcloud + Postgres + Redis
# VLAN 20 CORE - 10.0.20.60
# Acces externe via NAT inbound OPNsense
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

variable "ct_password" {
  type      = string
  sensitive = true
  default   = "Ynov2026!"
}

variable "ssh_public_key_file" {
  type    = string
  default = "/root/.ssh/proxmox_lab.pub"
}

variable "lxc_template" {
  type    = string
  default = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
}

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

resource "proxmox_virtual_environment_container" "nextcloud_01" {
  description = "Nextcloud (Docker) - VLAN 20 CORE"
  tags        = ["nextcloud", "docker", "vlan20", "core"]

  node_name = "pve-02"
  vm_id     = 207

  # Nesting + keyctl + fuse obligatoires pour Docker dans LXC
  # NOTE : keyctl et fuse ne peuvent pas etre actives via API token,
  # ils sont actives via 'pct set' depuis l'hyperviseur (role Ansible)
  features {
    nesting = true
  }

  unprivileged = true

  start_on_boot = true
  startup {
    order      = 50
    up_delay   = 20
    down_delay = 20
  }

  cpu {
    cores        = 2
    architecture = "amd64"
  }

  memory {
    dedicated = 2048
    swap      = 512
  }

  # Disque unique 12 GB - OS + Docker + data (POC minimal)
  disk {
    datastore_id = "ceph_vm"
    size         = 12
  }

  network_interface {
    name     = "eth0"
    bridge   = "vmbr3"
    vlan_id  = 20
    firewall = false
  }

  initialization {
    hostname = "nextcloud-01"

    ip_config {
      ipv4 {
        address = "10.0.20.60/24"
        gateway = "10.0.20.1"
      }
    }

    dns {
      domain  = "infra.lan"
      servers = ["10.0.20.10"]
    }

    user_account {
      password = var.ct_password
      keys     = [trimspace(file(var.ssh_public_key_file))]
    }
  }

  operating_system {
    template_file_id = var.lxc_template
    type             = "debian"
  }

  console {
    enabled = true
    type    = "tty"
  }
}

output "nextcloud_summary" {
  value = {
    hostname    = "nextcloud-01"
    vmid        = 207
    ip          = "10.0.20.60"
    node        = "pve-02"
    vlan        = "20 (CORE)"
    web_ui      = "http://10.0.20.60:8080"
    public_url  = "http://192.168.80.143:8090 (après NAT inbound OPNsense)"
    resources   = "2 vCPU / 2 GB RAM / 12 GB disque"
    nat_rule    = "Sur OPNsense : Firewall → NAT → Port Forward → WAN:8090 → 10.0.20.60:8080"
  }
}
