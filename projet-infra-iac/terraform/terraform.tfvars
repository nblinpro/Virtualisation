###############################################################################
# Variables a renseigner
# Copier en terraform.tfvars et adapter les valeurs
###############################################################################

# API Proxmox - URL d'un des noeuds du cluster
proxmox_api_url = "https://192.168.3.21:8006/"

# Token API Proxmox - cree via :
# Datacenter > Permissions > API Tokens > Add
# Puis : Datacenter > Permissions > Add > API Token Permission
# Role: Administrator, Path: /
proxmox_api_token_id     = "root@pam!terraform-token"
proxmox_api_token_secret = "3f08cba4-1e9b-4908-b795-3af9179d4771"

# Cles SSH
proxmox_ssh_private_key = "/home/ynov/.ssh/proxmox_lab"
ssh_public_key          = "/home/ynov/.ssh/proxmox_lab.pub"

# Mot de passe root pour les LXC (utilise par cloud-init)
lxc_root_password = "ChangeMe2026!"

# Cibles
dns_node     = "pve-02"
ceph_pool    = "ceph_vm"
lxc_template = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"

# Pour pgsql-01
db_node              = "pve-03"
postgres_db_name     = "webapp_db"
postgres_db_user     = "webapp"
postgres_db_password = "WebApp2026!ChangeMe"
