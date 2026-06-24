proxmox_api_url          = "https://192.168.3.21:8006/"
proxmox_api_token_id     = "root@pam!terraform-token"
proxmox_api_token_secret = "a289e91f-af17-4454-9510-4c5a1b8a01bd"

proxmox_ssh_private_key = "/root/.ssh/proxmox_lab"
ssh_public_key          = "/root/.ssh/proxmox_lab.pub"

lxc_root_password = "Ynov2026!"

ceph_pool    = "ceph_vm"
lxc_template = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
