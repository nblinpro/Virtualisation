# Projet Infrastructure as Code - Lab Virtuel

Déploiement automatisé d'une infrastructure critique hautement disponible via :

- **Terraform** : provisionnement des conteneurs LXC sur Proxmox VE
- **Ansible** : installation, sécurisation et configuration des services

## Architecture réseau & serveurs

- **Hyperviseurs** : Cluster PVE (`pve-01`, `pve-02`, `pve-03`)
- **Stockage partagé** : Ceph (`ceph-vm`)
- **Passerelle / Pare-feu** : OPNsense (`10.0.20.1`)
- **Bastion de déploiement** : CT Alpine Linux (`192.168.80.131`)

## Prérequis

### Configuration du bastion (deploy-bastion)

Exécutez ces commandes directement sur le conteneur Alpine de déploiement pour installer l'environnement :

```bash
# Activer le dépôt community (nécessaire pour Ansible)
sed -i '/community/s/^#//g' /etc/apk/repositories
apk update

# Installer les prérequis et Ansible
apk add wget unzip ansible curl

# Installer Terraform manuellement
wget https://releases.hashicorp.com/terraform/1.9.0/terraform_1.9.0_linux_amd64.zip
unzip terraform_1.9.0_linux_amd64.zip
mv terraform /usr/local/bin/
rm terraform_1.9.0_linux_amd64.zip

# Vérifier les versions installées
terraform version
ansible --version
```

### Paire de clés SSH

Générez la paire de clés Ed25519 dédiée au laboratoire IaC et distribuez-la sur vos nœuds physiques Proxmox :

```bash
# Générer la clé SSH sur le bastion
ssh-keygen -t ed25519 -f ~/.ssh/proxmox_lab -N ""

# Copier la clé sur les 3 nœuds Proxmox du cluster de management
for ip in 192.168.3.21 192.168.3.22 192.168.3.23; do
    ssh-copy-id -i ~/.ssh/proxmox_lab.pub root@$ip
done
```

### Token API Proxmox VE

Sur l'interface web de Proxmox :

1. **Datacenter → Permissions → API Tokens → Add**
   - User : `root@pam`
   - Token ID : `terraform-token`
   - ☐ Privilege Separation (décocher pour hériter des droits root)
   - Sauvegardez précieusement le secret affiché.

2. **Datacenter → Permissions → Add → API Token Permission**
   - Path : `/`
   - API Token : `root@pam!terraform-token`
   - Role : `Administrator`

## Déploiement de l'Infrastructure

### Étape 1 : Initialisation Terraform

Configurez vos variables d'accès à l'API Proxmox et aux configurations système avant de lancer le déploiement.

```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
# Renseigner obligatoirement : proxmox_api_token_secret, lxc_root_password

terraform init
```

### Étape 2 : Déploiement ordonnancé et ciblé

L'ordre est important : `dns-01` doit être configuré en premier, car tous les autres conteneurs l'utilisent comme résolveur (`10.0.20.10`).

#### 1. Résolveur DNS Interne (dns-01 — VLAN 20 CORE)

```bash
# Provisionnement de la ressource
terraform apply -target='proxmox_virtual_environment_container.dns_01' -auto-approve

# Échange de clés SSH
ssh-copy-id -i ~/.ssh/proxmox_lab.pub root@10.0.20.10

# Configuration Unbound via Ansible
cd ../ansible
ansible-playbook playbook-dns.yml
```

#### 2. Base de données (pgsql-01 — VLAN 50 DATA)

```bash
cd ../terraform
terraform apply -target='proxmox_virtual_environment_container.pgsql_01' -auto-approve

# Échange de clés SSH
ssh-copy-id -i ~/.ssh/proxmox_lab.pub root@10.0.50.10

# Configuration PostgreSQL via Ansible
cd ../ansible
ansible-playbook playbook-db.yml
```

#### 3. Cluster Serveurs Web (web-01, web-02, web-03 — VLAN 40 WEB)

```bash
cd ../terraform
terraform apply -target='proxmox_virtual_environment_container.web' -auto-approve

# Échange de clés SSH vers chaque nœud web
ssh-copy-id -i ~/.ssh/proxmox_lab.pub root@10.0.40.11
ssh-copy-id -i ~/.ssh/proxmox_lab.pub root@10.0.40.12
ssh-copy-id -i ~/.ssh/proxmox_lab.pub root@10.0.40.13

# Configuration Nginx + PHP-FPM via Ansible
cd ../ansible
ansible-playbook playbook-web.yml --limit web_servers
```

#### 4. Haute Disponibilité & Routage (HAProxy Load Balancers — VLAN 40 WEB)

```bash
cd ../terraform
terraform apply -target='proxmox_virtual_environment_container.lb' -auto-approve

# Échange de clés SSH vers la paire de load balancers
ssh-copy-id -i ~/.ssh/proxmox_lab.pub root@10.0.40.21
ssh-copy-id -i ~/.ssh/proxmox_lab.pub root@10.0.40.22

# Configuration HAProxy et Keepalived via Ansible
cd ../ansible
ansible-playbook playbook-web.yml --limit load_balancers
```

## Validation & Accès Externe

### Tunneling SSH d'administration (depuis votre poste Windows)

Pour accéder en toute sécurité aux services Web internes et aux statistiques d'infrastructure isolés derrière le bastion, initialisez le port-forwarding local SSH suivant :

```powershell
# Commande à exécuter dans votre PowerShell Windows
ssh -L 8080:10.0.40.10:80 -L 8404:10.0.40.10:8404 root@192.168.80.131
```

Une fois le tunnel ouvert :

- **Application Web mutualisée** : accès via <http://localhost:8080> (équilibrage dynamique sur les 3 backends)
- **Tableau de bord de statistiques HAProxy** : accès via <http://localhost:8404/stats> (identifiants : `admin` / `Stats2026!`)

### Tests DNS de validation (depuis deploy-bastion)

```bash
# Vérification de la résolution interne d'infrastructure
dig @10.0.20.10 pve-01.infra.lan +short
# Attendu : 192.168.3.21

# Vérification du fonctionnement du résolveur récursif externe
dig @10.0.20.10 google.com +short

# Vérification de la configuration reverse DNS (PTR)
dig @10.0.20.10 -x 192.168.3.250 +short
# Attendu : fw-01.infra.lan
```

## Cartographie DNS & Plan d'adressage

| Nom DNS | Adresse IPv4 | Zone réseau / VLAN |
|---------|--------------|--------------------|
| pve-01.infra.lan | 192.168.3.21 | Management |
| pve-02.infra.lan | 192.168.3.22 | Management |
| pve-03.infra.lan | 192.168.3.23 | Management |
| fw-01.infra.lan | 192.168.3.250 / 10.0.20.1 | Gateway CORE |
| dns-01.infra.lan | 10.0.20.10 | VLAN 20 (CORE) |
| web.infra.lan | 10.0.40.10 (VIP HA) | VLAN 40 (WEB) |
| web-01.infra.lan | 10.0.40.11 | VLAN 40 (WEB) |
| web-02.infra.lan | 10.0.40.12 | VLAN 40 (WEB) |
| web-03.infra.lan | 10.0.40.13 | VLAN 40 (WEB) |
| lb-01.infra.lan | 10.0.40.21 | VLAN 40 (WEB) |
| lb-02.infra.lan | 10.0.40.22 | VLAN 40 (WEB) |
| pgsql-01.infra.lan | 10.0.50.10 | VLAN 50 (DATA) |
| pbs-01.infra.lan | 10.0.99.10 | Sauvegardes |

## Destruction de la plateforme

Pour libérer l'ensemble des ressources allouées sur le cluster Proxmox :

```bash
cd terraform/
terraform destroy -auto-approve
```
