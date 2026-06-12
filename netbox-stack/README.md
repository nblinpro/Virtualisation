# Stack NetBox v1.1 - IPAM

Deploiement automatise de NetBox 4.1 via Terraform + Ansible sur LXC Debian 13.

## Specifications

| Parametre | Valeur |
|-----------|--------|
| VMID | 304 |
| Hostname | netbox-01 |
| Hote | pve-02 |
| vCPU | 2 |
| RAM | 1 GB |
| Disque | 4 GB sur ceph_vm |
| IP | 10.0.20.30/24 |
| VLAN | 20 (CORE) |

## Composants installes

- **NetBox 4.1.5** (application Django + IPAM)
- **PostgreSQL** (base de donnees)
- **Redis** (cache + queue)
- **Gunicorn** (serveur d'application Python, 3 workers)
- **Nginx** (reverse proxy HTTP)

## Fixes integres dans v1.1

Cette version corrige les 6 problemes rencontres lors du premier deploiement :

| # | Probleme | Solution |
|---|----------|----------|
| 1 | PostgreSQL `SQL_ASCII vs UTF8` (Debian 13 LXC) | `template: template0` + `lc_collate: C.UTF-8` |
| 2 | Utilisateur redis non cree par APT | Tache Ansible `user: name=redis` |
| 3 | Redis systemd `217/USER` et `226/NAMESPACE` | Service systemd custom LXC-friendly |
| 4 | Git `dubious ownership` apres chown | `git config --global --add safe.directory` |
| 5 | NetBox 4.x : `auth.User` deplace | `from users.models import User` |
| 6 | Static files dans `static/` pas `staticfiles/` | Nginx alias corrige + permissions |
| 7 | CSRF 403 depuis WAN NAT | `CSRF_TRUSTED_ORIGINS` inclut WAN |

## Procedure de deploiement

### 1. Decompresser et installer le projet

```bash
cd ~/Virtualisation/
# Si version precedente existe, sauvegarder
mv netbox-stack netbox-stack.OLD 2>/dev/null

# Decompresser
tar -xzf netbox-stack.tar.gz
cd netbox-stack/
```

### 2. Configuration Terraform

```bash
cd terraform/

# Copier ton terraform.tfvars existant ou creer depuis l'exemple
cp ~/Virtualisation/dns-pgsql-web-lb/terraform/terraform.tfvars . 2>/dev/null \
  || cp terraform.tfvars.example terraform.tfvars

# Si nouveau bastion, adapter les chemins (/root/ pas /home/ynov/)
sed -i 's|/home/ynov|/root|g' terraform.tfvars

# Cache provider depuis projet existant (evite l'acces a registry.terraform.io)
cp -r ~/Virtualisation/dns-pgsql-web-lb/terraform/.terraform . 2>/dev/null
cp ~/Virtualisation/dns-pgsql-web-lb/terraform/.terraform.lock.hcl . 2>/dev/null
```

### 3. Provisionnement Terraform

```bash
terraform init
terraform apply -auto-approve
```

⏱ Duree : ~1 minute pour creer le CT.

### 4. Echange cle SSH

```bash
# Nettoyer ancienne cle si existante
ssh-keygen -f ~/.ssh/known_hosts -R 10.0.20.30 2>/dev/null

# Accepter la nouvelle cle automatiquement
ssh -i ~/.ssh/proxmox_lab -o StrictHostKeyChecking=no root@10.0.20.30 "hostname"
```

Tu dois voir : `netbox-01`

### 5. Deploiement Ansible

```bash
cd ../ansible/

# Installer la collection PostgreSQL (une seule fois sur le bastion)
ansible-galaxy collection install community.postgresql

# Lancer le playbook
ansible-playbook -i inventory.ini playbook-netbox.yml
```

⏱ Duree totale : **10-15 minutes**.

Etapes les plus longues :
- `pip install requirements.txt` (~5-10 min sur 1 vCPU)
- `manage.py migrate` (~1-2 min)
- `collectstatic` (~30 sec)

## Acces NetBox

| Element | Valeur |
|---------|--------|
| URL interne | http://10.0.20.30 |
| Login | admin |
| Password | Ynov2026! |

### NAT inbound OPNsense (acces depuis Windows)

| Champ | Valeur |
|-------|--------|
| Interface | WAN |
| Protocol | TCP |
| Destination | WAN address |
| Destination port | 8095 |
| Redirect IP | 10.0.20.30 |
| Redirect port | 80 |

Acces depuis Windows : `http://192.168.80.141:8095`

## Configuration NetBox post-deploiement

Une fois connecte, remplir dans cet ordre :

### A. Structure organisationnelle
1. **Organization > Sites** : creer `ynov-lab`
2. **Virtualization > Cluster Types** : creer `Proxmox VE`
3. **Virtualization > Clusters** : creer `ynov-lab`

### B. Reseau (IPAM)
1. **IPAM > VLAN Groups** : creer `ynov-lab`
2. **IPAM > VLANs** : creer les 7 VLANs (10, 20, 30, 40, 50, 60, 99)
3. **IPAM > Prefixes** : creer les 8 prefixes (les 7 VLANs + `192.168.3.0/24` management)

### C. Devices physiques
1. **DCIM > Device Roles** : creer `Hypervisor`
2. **DCIM > Manufacturers** : creer `Proxmox`
3. **DCIM > Device Types** : creer `PVE Node`
4. **DCIM > Devices** : creer pve-01, pve-02, pve-03

### D. Virtual Machines (le gros morceau)
1. **Virtualization > Virtual Machines** : creer chaque CT/VM
2. Pour chacun : assigner cluster, ressources, VLAN, adresse IP

### E. Services (en bonus)
- **IPAM > Services** : associer chaque service a sa VM
  - HTTPS:443 sur lb-01
  - PostgreSQL:5432 sur pgsql-01
  - DNS:53 sur dns-rec-01, dns-auth-01
  - etc.

## Commandes utiles

### Voir les services
```bash
ssh -i ~/.ssh/proxmox_lab root@10.0.20.30 \
  "systemctl status netbox netbox-rq nginx postgresql redis-server | grep -E 'Active|Loaded'"
```

### Voir les logs NetBox
```bash
ssh -i ~/.ssh/proxmox_lab root@10.0.20.30 "journalctl -u netbox -f"
```

### Mode debug (en cas de probleme)
```bash
ssh -i ~/.ssh/proxmox_lab root@10.0.20.30 "
  sed -i 's/DEBUG = False/DEBUG = True/' /opt/netbox/netbox/netbox/configuration.py
  systemctl restart netbox
"
# IMPORTANT : remettre DEBUG = False apres
```

### Backup PostgreSQL NetBox
```bash
ssh -i ~/.ssh/proxmox_lab root@10.0.20.30 \
  "sudo -u postgres pg_dump netbox > /tmp/netbox-backup.sql"

scp -i ~/.ssh/proxmox_lab root@10.0.20.30:/tmp/netbox-backup.sql .
```

### Memory pressure

Avec 1 GB de RAM, surveiller :
- Gunicorn workers (3 par defaut, ~150 MB total)
- PostgreSQL (~100 MB)
- Redis (~10 MB)
- Django app (~250 MB)
- Reserve pour le systeme (~300 MB)

Si OOM kills :
```bash
# Reduire Gunicorn a 2 workers
ssh root@10.0.20.30 "sed -i 's/workers = 3/workers = 2/' /opt/netbox/gunicorn.py"
ssh root@10.0.20.30 "systemctl restart netbox"
```

## Troubleshooting

### Erreur : "non-zero return code" sur collectstatic
- Verifier que `/opt/netbox/netbox/static` est ecrivable par netbox
- Relancer : `sudo -u netbox /opt/netbox/venv/bin/python manage.py collectstatic --no-input`

### Erreur 403 CSRF apres deploiement
- Verifier que l'URL d'acces est dans CSRF_TRUSTED_ORIGINS
- Voir : `grep CSRF /opt/netbox/netbox/netbox/configuration.py`

### Erreur 404 sur les fichiers statiques (CSS/JS)
- Verifier la config Nginx : `grep alias /etc/nginx/sites-enabled/netbox`
- Doit pointer sur `/opt/netbox/netbox/static/` (pas `/staticfiles/`)

### Redis ne demarre pas
- Si status 217/USER : verifier que l'utilisateur redis existe (`id redis`)
- Si status 226/NAMESPACE : remplacer le service systemd par notre version LXC-friendly
- Voir tasks/main.yml section 3 pour le service systemd correct

## Structure du projet

```
netbox-stack/
├── README.md                                  Ce fichier
├── terraform/
│   ├── main.tf                                Provisionnement CT (VMID 304)
│   └── terraform.tfvars.example
└── ansible/
    ├── inventory.ini
    ├── playbook-netbox.yml
    └── roles/netbox/
        ├── defaults/main.yml                  Variables (passwords, version)
        ├── handlers/main.yml                  Restart services
        ├── tasks/main.yml                     Installation (avec tous les fixes)
        └── templates/
            ├── configuration.py.j2            Config NetBox (CSRF inclus)
            ├── gunicorn.py.j2                 Config app server
            ├── netbox.service.j2              Systemd unit
            ├── netbox-rq.service.j2           Worker queue
            └── nginx-netbox.conf.j2           Reverse proxy (path static/)
```

## Version

- **v1.0** : Deploiement initial (problemes rencontres)
- **v1.1** : Tous les fixes integres, idempotent et reproductible

Date de mise a jour : Juin 2026
