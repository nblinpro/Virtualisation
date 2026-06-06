terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.46.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  insecure  = true
  api_token = var.proxmox_api_token

  ssh {
    agent       = false
    private_key = file(var.ssh_private_key)
    username    = "root"
  }
}

# =============================================================================
# LXC GLPI - Gestion du parc et helpdesk (ITSM)
# =============================================================================
resource "proxmox_virtual_environment_container" "glpi" {
  description   = "GLPI - Gestion de parc IT et helpdesk"
  node_name     = "pve-01"
  vm_id         = 305
  tags          = ["glpi", "itsm", "helpdesk", "vlan20"]
  start_on_boot = true
  unprivileged  = true

  initialization {
    hostname = "glpi-01"
    ip_config {
      ipv4 {
        address = "10.0.20.50/24"
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
    cores = 1
  }
  memory {
    dedicated = 512
    swap      = 512
  }
  disk {
    datastore_id = var.ceph_pool
    size         = 3
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
  startup {
    order      = "60"
    up_delay   = "5"
    down_delay = "5"
  }

  features {
    nesting = true
  }
}

# =============================================================================
# Outputs
# =============================================================================
output "glpi_ip" {
  value = "10.0.20.50"
}

output "glpi_url" {
  value = "http://10.0.20.50"
}

output "glpi_hostname" {
  value = "glpi-01"
}
