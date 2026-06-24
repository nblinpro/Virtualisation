###############################################################################
# Terraform - VM Proxmox Backup Server (pbs-01) - POC
# OVMF/Q35 obligatoire pour PBS 4.x
# VLAN 99 BACKUP - 10.0.99.20
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

variable "pbs_iso_path" {
  type        = string
  description = "Chemin de l'ISO PBS sur le datastore local"
  default     = "local:iso/proxmox-backup-server_4.2-1.iso"
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

resource "proxmox_virtual_environment_vm" "pbs_01" {
  name        = "pbs-01"
  description = "Proxmox Backup Server - VLAN 99 BACKUP (POC)"
  tags        = ["pbs", "backup", "vlan99", "storage"]

  node_name = "pve-03"
  vm_id     = 700

  on_boot = true
  startup {
    order      = 100
    up_delay   = 30
    down_delay = 30
  }

  # Machine Q35 + BIOS UEFI obligatoire pour PBS 4.x
  machine = "q35"
  bios    = "ovmf"

  efi_disk {
    datastore_id      = "local-lvm"
    file_format       = "raw"
    type              = "4m"
    pre_enrolled_keys = false
  }

  cpu {
    cores   = 2
    type    = "host"
    sockets = 1
  }

  memory {
    dedicated = 2048
  }

  # Disque unique 8 GB (systeme + datastore POC)
  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 8
    file_format  = "raw"
    cache        = "none"
    discard      = "on"
    ssd          = true
  }

  network_device {
    bridge   = "vmbr3"
    model    = "virtio"
    vlan_id  = 99
    firewall = false
  }

  cdrom {
    file_id   = var.pbs_iso_path
    interface = "ide2"
  }

  boot_order = ["ide2", "scsi0"]

  operating_system {
    type = "l26"
  }

  scsi_hardware = "virtio-scsi-single"

  agent {
    enabled = false
  }

  lifecycle {
    ignore_changes = [
      cdrom,
      started,
    ]
  }
}

output "pbs_summary" {
  value = {
    hostname    = "pbs-01"
    vmid        = 700
    ip_target   = "10.0.99.20"
    node        = "pve-03"
    vlan        = "99 (BACKUP)"
    web_ui      = "https://10.0.99.20:8007"
    bios        = "OVMF (UEFI)"
    machine     = "Q35"
    vcpu        = "2"
    memory      = "2048 MB"
    disk        = "8 GB (POC)"
    note        = "Installation initiale interactive via console PVE"
  }
}
