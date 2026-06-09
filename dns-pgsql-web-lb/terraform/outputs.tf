###############################################################################
# Outputs Terraform - genere l'inventaire Ansible complet
###############################################################################

output "summary" {
  description = "Resume des LXC deployes"
  value = {
    "dns-rec-01"  = "10.0.20.10 (${var.dns_node}, VLAN 20) - AdGuard Home"
    "dns-auth-01" = "10.0.20.11 (${var.dns_node}, VLAN 20) - BIND9"
    "pgsql-01"    = "10.0.50.10 (${var.db_node}, VLAN 50)"
    "web-01"      = "10.0.40.11 (pve-01, VLAN 40)"
    "web-02"      = "10.0.40.12 (pve-02, VLAN 40)"
    "web-03"      = "10.0.40.13 (pve-03, VLAN 40)"
    "lb-01"       = "10.0.10.11 (pve-01, VLAN 10) - MASTER"
    "lb-02"       = "10.0.10.12 (pve-02, VLAN 10) - BACKUP"
    "VIP"         = "10.0.10.100 (VLAN 10 DMZ, geree par Keepalived)"
  }
}

# =============================================================================
# Inventaire Ansible genere automatiquement
# =============================================================================
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory.ini"
  content  = <<-EOT
    # =============================================================================
    # Inventaire Ansible - genere automatiquement par Terraform
    # NE PAS EDITER A LA MAIN
    # =============================================================================

    [dns_recursive]
    dns-rec-01 ansible_host=10.0.20.10

    [dns_authoritative]
    dns-auth-01 ansible_host=10.0.20.11

    [dns_servers:children]
    dns_recursive
    dns_authoritative

    [database_servers]
    pgsql-01 ansible_host=10.0.50.10

    [web_servers]
    web-01 ansible_host=10.0.40.11
    web-02 ansible_host=10.0.40.12
    web-03 ansible_host=10.0.40.13

    [load_balancers]
    lb-01 ansible_host=10.0.10.11 keepalived_state=MASTER keepalived_priority=110
    lb-02 ansible_host=10.0.10.12 keepalived_state=BACKUP keepalived_priority=100

    [cluster_web:children]
    web_servers
    load_balancers

    [infra:children]
    dns_servers
    database_servers
    cluster_web

    [infra:vars]
    ansible_user=root
    ansible_ssh_private_key_file=~/.ssh/proxmox_lab
    ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
    ansible_python_interpreter=/usr/bin/python3
  EOT
}
