# Nextcloud Stack — VLAN 20 CORE

Déploiement de Nextcloud sur un CT LXC + Docker dans le VLAN CORE.

## 🎯 Architecture

```
Internet
   │
   └─→ OPNsense (NAT inbound)
          │  WAN:8090 → 10.0.20.60:8080
          ↓
       nextcloud-01 (10.0.20.60)
          │ VLAN 20 CORE
          │
          └─ Docker stack
             ├─ nextcloud-app   (port 8080 exposé)
             ├─ nextcloud-db    (Postgres 16)
             └─ nextcloud-redis (cache)
```

## 📋 Spécifications

| Élément | Valeur |
|---------|--------|
| **Hostname** | nextcloud-01 |
| **VMID** | 207 |
| **VLAN** | 20 (CORE) |
| **IP interne** | 10.0.20.60/24 |
| **IP WAN (NAT)** | 192.168.80.143:8090 |
| **OS** | Debian 13 LXC (unprivileged) |
| **Specs** | 2 vCPU / 2 GB RAM / 12 GB disque |
| **Node** | pve-02 |

## 🚀 Déploiement

### 1. Provisionner le CT (Terraform)

```bash
cd ~/Virtualisation/nextcloud-stack/terraform
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars   # remplir le token

terraform init
terraform apply -auto-approve
```

### 2. Démarrer le CT (1ère fois)

```bash
ssh -i ~/.ssh/proxmox_lab root@192.168.3.22 "pct start 207"
sleep 30
```

### 3. Installer la collection Ansible (1ère fois uniquement)

```bash
ansible-galaxy collection install community.docker
```

### 4. Lancer le playbook

```bash
cd ../ansible
ansible-playbook -i inventory/hosts.ini playbook.yml
```

⏱ **~8 minutes** (apt update + install Docker + pull images + start containers)

## 🔌 Configuration OPNsense (NAT inbound)

Après le déploiement, configurer le port forward dans OPNsense :

**Firewall → NAT → Port Forward → Add :**

| Champ | Valeur |
|-------|--------|
| Interface | WAN |
| TCP/IP Version | IPv4 |
| Protocol | TCP |
| Source | any |
| Destination | WAN address |
| Destination port range | 8090 → 8090 |
| Redirect target IP | 10.0.20.60 |
| Redirect target port | 8080 |
| Description | NAT Nextcloud |
| Filter rule association | Pass (automatique) |

**Apply Changes** → la règle est active.

## 🌐 Accès

| Accès | URL |
|-------|-----|
| **Depuis le bastion / réseau interne** | http://10.0.20.60:8080 |
| **Depuis Windows / Internet (après NAT)** | http://192.168.80.143:8090 |

**Login admin** : `ncadmin` / `Ynov2026!ChangeMe`

⚠️ **Changer le mot de passe** à la première connexion !

## 🧪 Tests

```bash
# Depuis le bastion
curl -I http://10.0.20.60:8080/status.php
# Doit retourner HTTP/1.1 200 OK

# Voir le JSON de status
curl http://10.0.20.60:8080/status.php
# {"installed":true,"maintenance":false,"productname":"Nextcloud",...}
```

## 🐳 Gérer la stack Docker

```bash
# SSH sur le CT
ssh -i ~/.ssh/proxmox_lab root@10.0.20.60

# Voir les containers
cd /opt/nextcloud
docker compose ps

# Voir les logs
docker compose logs app | tail -50
docker compose logs db | tail -50

# Redemarrer
docker compose restart

# Stopper / Demarrer
docker compose down
docker compose up -d
```

## 📊 Ressources réelles

| Composant | RAM | Disque |
|-----------|-----|--------|
| OS Debian + Docker | ~300 MB | ~3 GB |
| Image Nextcloud | ~400 MB | ~1 GB |
| Image Postgres | ~100 MB | ~100 MB |
| Image Redis | ~50 MB | ~50 MB |
| **Total** | **~850 MB** | **~5 GB** |
| Marge sur 2 GB / 12 GB | **~1.2 GB libre** | **~7 GB libre** |

## 🔧 Dépannage

### Le playbook plante à l'installation de Docker

```bash
# Verifier que nesting/keyctl sont actives
ssh -i ~/.ssh/proxmox_lab root@192.168.3.22 \
  "cat /etc/pve/lxc/207.conf | grep features"

# Doit afficher : features: keyctl=1,nesting=1,fuse=1
```

### Nextcloud retourne "Untrusted domain"

Ajouter ton URL dans les trusted domains :

```bash
ssh -i ~/.ssh/proxmox_lab root@10.0.20.60
cd /opt/nextcloud
docker compose exec -u www-data app php occ config:system:set \
  trusted_domains 10 --value="mon-url"
```

### Re-démarrer après reboot

Le CT redémarre automatiquement (start_on_boot=true) et Docker aussi (restart: unless-stopped sur les containers). Aucune action manuelle.

## 🧹 Désinstallation

```bash
# Stopper et supprimer le CT
ssh -i ~/.ssh/proxmox_lab root@192.168.3.22 "pct stop 207 && pct destroy 207"

# Retirer la regle NAT sur OPNsense (UI)

# Detruire l'etat Terraform
cd ~/Virtualisation/nextcloud-stack/terraform
terraform destroy -auto-approve
```

## 🎓 Pour le rapport

À mentionner dans le rapport :

**§3.8 Services applicatifs** — Ajouter Nextcloud comme nouveau service :

> "Nextcloud (`nextcloud-01`, IP 10.0.20.60) est déployé en VLAN CORE comme service collaboratif d'entreprise. Il est conteneurisé via Docker (3 conteneurs : Nextcloud + PostgreSQL + Redis), ce qui simplifie son cycle de vie et l'isolation de ses dépendances. L'accès externe se fait via NAT inbound OPNsense sur le port 8090."

**§3.12 Récapitulatif des services** — Ajouter dans la catégorie "Outils d'admin" ou créer "Cloud collaboratif (1)" :

> "Cloud collaboratif (1) | Nextcloud (Docker : app + Postgres + Redis)"

## 📷 Captures bonus

- **fig-XX-nextcloud-dashboard** : page d'accueil Nextcloud après login
- **fig-XX-docker-compose-ps** : terminal `docker compose ps` montrant les 3 containers UP
