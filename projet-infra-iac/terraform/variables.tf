###############################################################################
# Variables Terraform - dns-01
###############################################################################

variable "proxmox_api_url" {
  description = "URL de l'API Proxmox"
  type        = string
}

variable "proxmox_api_token_id" {
  description = "ID du token API (ex: root@pam!terraform-token)"
  type        = string
}

variable "proxmox_api_token_secret" {
  description = "Secret du token API"
  type        = string
  sensitive   = true
}

variable "proxmox_ssh_private_key" {
  description = "Chemin vers la cle privee SSH pour Proxmox"
  type        = string
  default     = "~/.ssh/proxmox_lab"
}

variable "ssh_public_key" {
  description = "Chemin vers la cle publique SSH (injectee dans les LXC)"
  type        = string
  default     = "~/.ssh/proxmox_lab.pub"
}

variable "lxc_root_password" {
  description = "Mot de passe root pour les LXC"
  type        = string
  sensitive   = true
}

variable "dns_node" {
  description = "Noeud Proxmox cible pour dns-01"
  type        = string
  default     = "pve-02"
}

variable "ceph_pool" {
  description = "Pool Ceph pour le stockage"
  type        = string
  default     = "ceph-vm"
}

variable "lxc_template" {
  description = "Template LXC Debian (verifier le nom exact disponible)"
  type        = string
  default     = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
}

# =============================================================================
# pgsql-01 (ajout v2)
# =============================================================================
variable "db_node" {
  description = "Noeud Proxmox cible pour pgsql-01"
  type        = string
  default     = "pve-03"
}

variable "postgres_db_name" {
  description = "Nom de la base de donnees a creer"
  type        = string
  default     = "webapp_db"
}

variable "postgres_db_user" {
  description = "Nom de l'utilisateur applicatif"
  type        = string
  default     = "webapp"
}

variable "postgres_db_password" {
  description = "Mot de passe de l'utilisateur applicatif"
  type        = string
  sensitive   = true
  default     = "WebApp2026!ChangeMe"
}
