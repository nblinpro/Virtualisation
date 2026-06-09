# Projet Infrastructure as Code - Lab Virtuel

Déploiement automatisé d'une infrastructure critique hautement disponible via :

- **Terraform** : provisionnement des conteneurs LXC sur Proxmox VE
- **Ansible** : installation, sécurisation et configuration des services

## Architecture réseau & serveurs

- **Hyperviseurs** : Cluster PVE (`pve-01`, `pve-02`, `pve-03`)
- **Stockage partagé** : Ceph (`ceph-vm`)
- **Passerelle / Pare-feu** : OPNsense (`10.0.20.1`)
- **Bastion de déploiement** : CT Alpine Linux (`192.168.80.131`)

## Services déployés

Conformément au cahier des charges, le service DNS est séparé en 2 rôles distincts :

| Service | Rôle | IP | VLAN |
|---------|------|-----|------|
| **dns-rec-01** | DNS récursif AdGuard Home (avec filtrage publicitaire) | 10.0.20.10 | 20 (CORE) |
| **dns-auth-01** | DNS autoritaire BIND9 (zone infra.lan) | 10.0.20.11 | 20 (CORE) |
| pgsql-01 | PostgreSQL 17 | 10.0.50.10 | 50 (BACKEND_DB) |
| web-01/02/03 | Cluster web HA (Nginx + PHP-FPM) | 10.0.40.11-13 | 40 (BACKEND_WEB) |
| lb-01/02 | Load Balancers HAProxy + Keepalived | 10.0.10.11-12 | 10 (DMZ) |
| VIP | Adresse virtuelle frontale | 10.0.10.100 | 10 (DMZ) |

### Architecture DNS

```
[Tous les clients]
   │ DNS configure : 10.0.20.10
   ▼
[dns-rec-01 - AdGuard Home]
   │ Filtre les pubs/trackers
   │ Si zone "infra.lan" → forward
   ▼
[dns-auth-01 - BIND9]   →   reponse pour *.infra.lan
   │
   │ (sinon → DoT vers Internet)
   ▼
[1.1.1.1 / 9.9.9.9]
```

## Prérequis

### Configuration du bastion (deploy-bastion)

```bash
sed -i '/community/s/^#//g' /etc/apk/repositories
apk update
apk add nano git ansible wget unzip curl openssh-client

wget https://releases.hashicorp.com/terraform/1.9.0/terraform_1.9.0_linux_amd64.zip
unzip terraform_1.9.0_linux_amd64.zip
mv terraform /usr/local/bin/
rm terraform_1.9.0_linux_amd64.zip

terraform version
ansible --version
```

### Paire de clés SSH

```bash
ssh-keygen -t ed25519 -f ~/.ssh/proxmox_lab -N ""

for ip in 192.168.3.21 192.168.3.22 192.168.3.23; do
    ssh-copy-id -i ~/.ssh/proxmox_lab.pub root@$ip
done
```

### Token API Proxmox VE

Sur l'interface web Proxmox :

1. **Datacenter → Permissions → API Tokens → Add**
   - User : `root@pam`
   - Token ID : `terraform-token`
   - ☐ Privilege Separation (décocher)

2. **Datacenter → Permissions → Add → API Token Permission**
   - Path : `/`
   - API Token : `root@pam!terraform-token`
   - Role : `Administrator`

## Déploiement de l'Infrastructure

### Étape 1 : Initialisation Terraform

```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
# Renseigner : proxmox_api_token_secret, lxc_root_password

terraform init
```

### Étape 2 : Déploiement ordonnancé

**Important** : l'ordre est crucial. BIND9 doit être déployé avant AdGuard, car AdGuard forwarde la zone infra.lan vers BIND9.

#### 1. DNS Autoritaire (dns-auth-01 — BIND9)

```bash
terraform apply -target='proxmox_virtual_environment_container.dns_auth_01' -auto-approve

ssh-copy-id -i ~/.ssh/proxmox_lab.pub root@10.0.20.11
```

#### 2. DNS Récursif (dns-rec-01 — AdGuard Home)

```bash
terraform apply -target='proxmox_virtual_environment_container.dns_rec_01' -auto-approve

ssh-copy-id -i ~/.ssh/proxmox_lab.pub root@10.0.20.10
```

#### 3. Configuration des 2 DNS

```bash
cd ../ansible
ansible-playbook -i inventory.ini playbook-dns.yml
```

Ce playbook configure d'abord BIND9 (autoritaire) puis AdGuard (récursif).

#### 4. Base de données (pgsql-01)

```bash
cd ../terraform
terraform apply -target='proxmox_virtual_environment_container.pgsql_01' -auto-approve

ssh-copy-id -i ~/.ssh/proxmox_lab.pub root@10.0.50.10

cd ../ansible
ansible-playbook -i inventory.ini playbook-db.yml
```

#### 5. Cluster web (web-01, web-02, web-03)

```bash
cd ../terraform
terraform apply -target='proxmox_virtual_environment_container.web' -auto-approve

ssh-copy-id -i ~/.ssh/proxmox_lab.pub root@10.0.40.11
ssh-copy-id -i ~/.ssh/proxmox_lab.pub root@10.0.40.12
ssh-copy-id -i ~/.ssh/proxmox_lab.pub root@10.0.40.13

cd ../ansible
ansible-playbook -i inventory.ini playbook-web.yml --limit web_servers
```

#### 6. Load Balancers (lb-01, lb-02)

```bash
cd ../terraform
terraform apply -target='proxmox_virtual_environment_container.lb' -auto-approve

ssh-copy-id -i ~/.ssh/proxmox_lab.pub root@10.0.10.11
ssh-copy-id -i ~/.ssh/proxmox_lab.pub root@10.0.10.12

cd ../ansible
ansible-playbook -i inventory.ini playbook-web.yml --limit load_balancers
```

## Validation DNS

```bash
# Resolution interne via AdGuard → BIND9
dig @10.0.20.10 pve-01.infra.lan +short
# Attendu : 192.168.3.21

# Resolution externe via AdGuard (DoT Cloudflare)
dig @10.0.20.10 google.com +short

# Test direct sur BIND9 (autoritaire)
dig @10.0.20.11 web-01.infra.lan +short
# Attendu : 10.0.40.11

# BIND9 doit REFUSER les requetes hors zone
dig @10.0.20.11 google.com +short
# Attendu : (vide) - BIND9 refuse car recursion no

# Verifier que les pubs sont bloquees
dig @10.0.20.10 doubleclick.net +short
# Attendu : 0.0.0.0 ou NXDOMAIN
```

## Interface AdGuard Home

URL : <http://10.0.20.10:3001> (depuis le LAN admin ou via NAT inbound)

- Login : `admin`
- Password : `Ynov2026!`

Statistiques disponibles :
- Requêtes par seconde
- Top domaines requêtés
- Top clients
- Pubs/trackers bloqués
- Logs de toutes les requêtes

## Cartographie DNS & Plan d'adressage

| Nom DNS | Adresse IPv4 | Zone / VLAN |
|---------|--------------|-------------|
| pve-01.infra.lan | 192.168.3.21 | Management |
| pve-02.infra.lan | 192.168.3.22 | Management |
| pve-03.infra.lan | 192.168.3.23 | Management |
| fw-01.infra.lan | 192.168.3.250 / 10.0.20.1 | Gateway |
| **dns-rec-01.infra.lan** | **10.0.20.10** | **VLAN 20 (CORE)** |
| **dns-auth-01.infra.lan** | **10.0.20.11** | **VLAN 20 (CORE)** |
| web.infra.lan | 10.0.10.100 (VIP) | VLAN 10 (DMZ) |
| web-01.infra.lan | 10.0.40.11 | VLAN 40 |
| web-02.infra.lan | 10.0.40.12 | VLAN 40 |
| web-03.infra.lan | 10.0.40.13 | VLAN 40 |
| lb-01.infra.lan | 10.0.10.11 | VLAN 10 (DMZ) |
| lb-02.infra.lan | 10.0.10.12 | VLAN 10 (DMZ) |
| pgsql-01.infra.lan | 10.0.50.10 | VLAN 50 (DB) |

## Mots de passe

| Service | Identifiants |
|---------|--------------|
| HAProxy stats | `http://VIP:8404/stats` — admin / Stats2026! |
| AdGuard Home | `http://10.0.20.10:3001` — admin / Ynov2026! |

## Destruction de la plateforme

```bash
cd terraform/
terraform destroy -auto-approve
```
