terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.46.0"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  insecure = true

  ssh {
    agent       = false
    private_key = file(var.ssh_private_key)
    username    = "root"
  }

  api_token = var.proxmox_api_token
}

# =============================================================================
# LXC Monitoring : Prometheus + Grafana + Loki + Promtail (tout-en-un)
# =============================================================================
resource "proxmox_virtual_environment_container" "monitoring" {
  description   = "Monitoring all-in-one (Prometheus + Grafana + Loki + Promtail)"
  node_name     = "pve-02"
  vm_id         = 501
  tags          = ["monitoring", "prometheus", "grafana", "loki", "vlan60"]
  start_on_boot = true
  unprivileged  = true

  initialization {
    hostname = "monitoring-01"
    ip_config {
      ipv4 {
        address = "10.0.60.10/24"
        gateway = "10.0.60.1"
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
    cores = 2
  }
  memory {
    dedicated = 1536
    swap      = 512
  }
  disk {
    datastore_id = var.ceph_pool
    size         = 6
  }
  network_interface {
    name    = "eth0"
    bridge  = "vmbr3"
    vlan_id = 60
  }
  operating_system {
    template_file_id = var.lxc_template
    type             = "debian"
  }
  startup {
    order      = "50"
    up_delay   = "10"
    down_delay = "5"
  }

  features {
    nesting = true
  }
}

# =============================================================================
# Outputs
# =============================================================================
output "monitoring_ip" {
  value = "10.0.60.10"
}

output "grafana_url" {
  value = "http://10.0.60.10:3000"
}

output "prometheus_url" {
  value = "http://10.0.60.10:9090"
}

output "loki_url" {
  value = "http://10.0.60.10:3100"
}
