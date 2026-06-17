# Stack NAS Samba - Serveur de fichiers

Deploiement automatise d'un serveur de fichiers Samba conformement au sujet :
> "Serveur de Fichiers (NAS) : Un conteneur LXC avec Samba/NFS pour le partage de documents."

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

## Composants installes

- **Samba** (smbd) sur port 445
- **3 shares** : public (lecture seule), documents (auth), backups (admin)
- **2 utilisateurs** : ynov (standard), nasadmin (admin)

## Shares disponibles

| Share | Acces | Authentification | Usage |
|-------|-------|------------------|-------|
| `public` | Lecture seule | Invite | Documentation, fichiers de test |
| `documents` | RW | `ynov` / `nasadmin` | Documents partages |
| `backups` | RW | `nasadmin` uniquement | Sauvegardes (futur PBS) |

## Mots de passe Samba

| Utilisateur | Mot de passe |
|-------------|--------------|
| `ynov` | `Ynov2026!` |
| `nasadmin` | `NasAdmin2026!` |

## Procedure de deploiement

### 1. Decompresser et configurer

```bash
cd ~/Virtualisation/
tar -xzf nas-stack.tar.gz
cd nas-stack/

cd terraform/
cp ~/Virtualisation/netbox-stack/terraform/terraform.tfvars .
cp -r ~/Virtualisation/netbox-stack/terraform/.terraform .
cp ~/Virtualisation/netbox-stack/terraform/.terraform.lock.hcl .
```

### 2. Provisionner le LXC

```bash
terraform init
terraform apply -auto-approve
```

⏱ Duree : ~1 minute.

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

⏱ Duree : ~3 minutes.

## Acces aux partages

### Depuis Windows

Ouvrir l'explorateur et taper dans la barre d'adresse :

```
\\10.0.99.10\public          (lecture seule, sans authentification)
\\10.0.99.10\documents       (login : ynov / Ynov2026!)
\\10.0.99.10\backups         (login : nasadmin / NasAdmin2026!)
```

⚠️ Pour acceder depuis Windows, il faut une route depuis ton PC vers VLAN 99 (NAT inbound sur OPNsense ou VPN).

### Depuis Linux (smbclient)

```bash
# Lister les shares
smbclient -L //10.0.99.10 -N

# Acces public (anonyme)
smbclient //10.0.99.10/public -N

# Acces documents (authentifie)
smbclient //10.0.99.10/documents -U ynov%Ynov2026!

# Monter en local
mount -t cifs //10.0.99.10/documents /mnt/docs \
  -o username=ynov,password=Ynov2026!,uid=1000,gid=1000
```

### Depuis macOS (Finder)

`Cmd+K` puis `smb://10.0.99.10`

## NAT inbound OPNsense (optionnel - acces Windows depuis WAN)

Pour acceder au NAS depuis ton PC Windows via WAN (192.168.80.x) :

| Champ | Valeur |
|-------|--------|
| Interface | WAN |
| Protocol | TCP |
| Destination port | 445 |
| Redirect IP | 10.0.99.10 |
| Redirect port | 445 |

Puis acces depuis Windows : `\\192.168.80.141\public`

⚠️ Note : exposer SMB sur Internet est une **TRES mauvaise pratique** (WannaCry, etc.). En lab c'est OK, mais en prod jamais sans VPN.

## Tests post-deploiement

### Depuis le bastion

```bash
# Test smbclient
ssh -i ~/.ssh/proxmox_lab root@10.0.10.50 "apk add samba-client 2>/dev/null; smbclient -L //10.0.99.10 -N"
```

### Verifications sur le NAS

```bash
ssh -i ~/.ssh/proxmox_lab root@10.0.99.10

# Statut Samba
systemctl status smbd

# Config Samba (validation syntaxe)
testparm

# Lister les utilisateurs Samba
pdbedit -L

# Lister les shares
smbclient -L //127.0.0.1 -N

# Voir les connexions actives
smbstatus
```

## Troubleshooting

### Erreur : OOM kill smbd avec 256 MB RAM

Si tu vois `Out of memory: Killed process ... smbd` dans dmesg :

```bash
# Augmenter la RAM
ssh -i ~/.ssh/proxmox_lab root@192.168.3.21 \
  "pct set 601 -memory 384"
```

### Erreur : "NT_STATUS_LOGON_FAILURE" lors de la connexion

Verifier que l'utilisateur Samba est bien active :

```bash
ssh root@10.0.99.10 "pdbedit -L -v ynov"
# Verifier 'Account Flags' contient 'U' (User) sans 'D' (Disabled)

# Reactiver si necessaire
smbpasswd -e ynov
```

### Erreur : connexion refusee

```bash
# Verifier que smbd ecoute
ss -tlnp | grep 445

# Voir les logs Samba
tail -50 /var/log/samba/log.smbd
```

### Pas de NetBIOS broadcast

Le service `nmbd` n'est PAS active car incompatible avec LXC unprivileged. Consequence : tu ne verras pas le NAS dans le voisinage reseau Windows. Acces uniquement par IP ou nom DNS.

## Structure du projet

```
nas-stack/
├── README.md
├── terraform/
│   ├── main.tf                                CT 601 (1 vCPU/256MB/5GB)
│   └── terraform.tfvars.example
└── ansible/
    ├── inventory.ini
    ├── playbook-nas.yml
    └── roles/nas_samba/
        ├── defaults/main.yml                  Users + shares
        ├── handlers/main.yml
        ├── tasks/main.yml                     Install + config
        └── templates/
            └── smb.conf.j2                    Config Samba
```

## Pour le rapport

Points valorisants :

- ✅ **Sujet respecte** : LXC + Samba pour partage de documents
- ✅ **Multi-niveaux d'acces** : invite, authentifie, admin
- ✅ **SMB3** uniquement (`server min protocol = SMB2_10`)
- ✅ **Restriction reseau** : `hosts allow` limite aux RFC 1918
- ✅ **Ressources legeres** : 256 MB RAM (4x moins qu'une VM TrueNAS)
- ✅ **Cohesion IaC** : meme template Debian 13, meme stack Terraform + Ansible
