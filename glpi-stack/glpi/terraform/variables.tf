variable "proxmox_endpoint" {
  description = "URL API Proxmox"
  type        = string
  default     = "https://192.168.3.21:8006/"
}

variable "proxmox_api_token" {
  description = "Token API Proxmox"
  type        = string
  sensitive   = true
}

variable "ssh_private_key" {
  description = "Cle SSH privee"
  type        = string
  default     = "~/.ssh/proxmox_lab"
}

variable "ssh_public_key" {
  description = "Cle SSH publique"
  type        = string
  default     = "~/.ssh/proxmox_lab.pub"
}

variable "lxc_root_password" {
  description = "Mot de passe root LXC"
  type        = string
  sensitive   = true
  default     = "Ynov2026!GLPI"
}

variable "lxc_template" {
  description = "Template LXC Debian 13"
  type        = string
  default     = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
}

variable "ceph_pool" {
  description = "Pool Ceph"
  type        = string
  default     = "ceph_vm"
}
