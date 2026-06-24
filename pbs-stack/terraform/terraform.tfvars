proxmox_api_url          = "https://192.168.3.21:8006/"
proxmox_api_token_id     = "root@pam!terraform-token"
proxmox_api_token_secret = "a289e91f-af17-4454-9510-4c5a1b8a01bd"

proxmox_ssh_private_key = "/root/.ssh/proxmox_lab"

# Chemin ISO PBS sur le datastore local de pve-03
# Verifier d'abord avec : ssh root@192.168.3.23 "ls /var/lib/vz/template/iso/"
pbs_iso_path = "local:iso/proxmox-backup-server_4.2-1.iso"
