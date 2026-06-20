# Stack NAS Samba v1.1 - Serveur de fichiers

Deploiement automatise d'un serveur de fichiers Samba.

## Changements v1.0 -> v1.1

| Element | Avant | Apres |
|---------|-------|-------|
| Share `backups` | Present | Retire (PBS gere) |
| Utilisateur `nasadmin` | Present | Retire |
| `smbclient` (client) | Absent | Installe |
| `server signing` | non defini | auto (compat invite) |
| Protocole min | SMB2_10 | SMB3 |
| Tests post-deploy | Manuels | Automatiques (3 tests) |

## Specifications

| Parametre | Valeur |
|-----------|--------|
| VMID | 601 |
| Hostname | nas-01 |
| Hote | pve-03 |
| vCPU | 1 |
| RAM | 256 MB |
| Disque | 5 GB sur ceph_vm |
| IP | 10.0.99.10/24 |
| VLAN | 99 (BACKUP) |

## Composants

- **Samba** (smbd) sur port 445
- **smbclient** pour tests locaux
- **2 shares** : public (RO invite), documents (RW auth)
- **1 utilisateur** Samba : ynov

## Shares disponibles

| Share | Acces | Authentification | Usage |
|-------|-------|------------------|-------|
| `public` | Lecture seule | Invite | Documentation, README |
| `documents` | RW | `ynov` | Documents partages utilisateur |

## Identifiants

| User | Password | Acces |
|------|----------|-------|
| `ynov` | `Ynov2026!` | public + documents |

## Procedure de deploiement

### 1. Decompresser

```bash
cd ~/Virtualisation/
tar -xzf nas-stack.tar.gz
cd nas-stack/
```

### 2. Provisionner avec Terraform (si nouvelle install)

```bash
cd terraform/
cp ~/Virtualisation/netbox-stack/terraform/terraform.tfvars .
cp -r ~/Virtualisation/netbox-stack/terraform/.terraform .
cp ~/Virtualisation/netbox-stack/terraform/.terraform.lock.hcl .

terraform init
terraform apply -auto-approve
```

### 3. Echange cle SSH

```bash
ssh-keygen -f ~/.ssh/known_hosts -R 10.0.99.10 2>/dev/null
ssh -i ~/.ssh/proxmox_lab -o StrictHostKeyChecking=no root@10.0.99.10 "hostname"
```

### 4. Deployer Samba

```bash
cd ../ansible/
ansible-playbook -i inventory.ini playbook-nas.yml
```

⏱ ~2 minutes. Le playbook execute automatiquement 3 tests de validation a la fin.

## Migration depuis v1.0 (si vous aviez l'ancien stack)

Pour passer de l'ancienne version (avec share `backups` + user `nasadmin`) :

```bash
# 1. Mettre a jour le code
cd ~/Virtualisation/
mv nas-stack nas-stack.v1.0.bak
tar -xzf nas-stack.tar.gz

# 2. Appliquer le nouveau role
cd nas-stack/ansible
ansible-playbook -i inventory.ini playbook-nas.yml

# 3. Nettoyer manuellement les elements obsoletes
ssh root@10.0.99.10 "
  rm -rf /srv/shares/backups
  smbpasswd -x nasadmin 2>/dev/null
  userdel nasadmin 2>/dev/null
  groupdel nasadmin 2>/dev/null
"
```

## Acces aux partages

### Depuis Windows

```
\\10.0.99.10\public          (lecture seule, sans auth)
\\10.0.99.10\documents       (login : ynov / Ynov2026!)
```

### Depuis Linux

```bash
# Lister
smbclient -L //10.0.99.10 -U ynov%Ynov2026!

# Acces public
smbclient //10.0.99.10/public -N

# Acces documents
smbclient //10.0.99.10/documents -U ynov%Ynov2026!

# Monter
mount -t cifs //10.0.99.10/documents /mnt/docs \
  -o username=ynov,password=Ynov2026!,uid=1000,gid=1000
```

## Tests post-deploiement automatises

Le playbook execute 3 tests :

1. **Liste des shares** : verifie que `public` est visible
2. **Acces public anonyme** : verifie qu'on peut lire le README
3. **Acces documents authentifie** : verifie l'auth `ynov`

Si un test echoue, le playbook s'arrete et indique le probleme.

## Strategie de sauvegarde

- **Documents utilisateur** : sur le NAS Samba (donnees vivantes)
- **Sauvegardes VMs/CTs** : sur **Proxmox Backup Server** (pbs-01)
  - URL : https://10.0.60.20:8007
  - Datastore : `backups`

Les deux roles sont **separes** : NAS = production, PBS = sauvegardes.

## Troubleshooting

### Test 2 echoue avec "Bad SMB2 signature"

Cause : `server signing = mandatory` empeche les invites de se connecter.
Solution : utiliser `server signing = auto` (corrige dans v1.1).

### Connexion impossible depuis Windows

Verifier :
1. `\\10.0.99.10` (par IP, pas par nom NetBIOS)
2. Reseau autorise dans `hosts allow` (RFC 1918 par defaut)
3. Pas de regle pare-feu OPNsense qui bloque

### Ressources tendues

256 MB RAM est tres juste. Si OOM kill :
```bash
ssh root@192.168.3.21 "pct set 601 -memory 384"
```

## Structure du projet

```
nas-stack/
├── README.md
├── terraform/
│   ├── main.tf                              CT 601 (1vCPU/256MB/5GB)
│   └── terraform.tfvars.example
└── ansible/
    ├── inventory.ini
    ├── playbook-nas.yml
    └── roles/nas_samba/
        ├── defaults/main.yml                Users + 2 shares
        ├── handlers/main.yml                Restart samba
        ├── tasks/main.yml                   Install + config + 3 tests
        └── templates/
            └── smb.conf.j2                  Config Samba SMB3 + signing auto

```

## Pour le rapport

Points valorisants :

- ✅ **Separation des responsabilites** : NAS = donnees, PBS = sauvegardes
- ✅ **Durcissement** : SMB3 only, signature SMB3, hosts allow RFC 1918
- ✅ **Tests automatises** : 3 tests valides a chaque deploiement
- ✅ **Idempotent** : replay sans risque
- ✅ **Leger** : 256 MB RAM (vs 8 GB TrueNAS Core)
- ✅ **IaC** : Terraform + Ansible coherent avec le reste du datacenter
