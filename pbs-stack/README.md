# Stack Proxmox Backup Server (PBS)

Deploiement automatise d'une VM PBS pour sauvegarder le cluster Proxmox.

## Specifications

| Parametre | Valeur |
|-----------|--------|
| VMID | 700 |
| Hostname | pbs-01 |
| Hote | pve-03 |
| Type | VM (KVM) |
| vCPU | 1 |
| RAM | 1 GB |
| Disque systeme | 8 GB sur local-lvm |
| Disque datastore | 50 GB sur local-lvm |
| IP | 10.0.60.20/24 |
| VLAN | 60 (MONITORING) |
| OS | Proxmox Backup Server 4 |
| Web UI | https://10.0.60.20:8007 |

## Pre-requis

1. **ISO PBS** telechargee sur pve-03 dans `/var/lib/vz/template/iso/`
2. **VLAN 60** configure sur OPNsense
3. **Cache provider Terraform** disponible

## Procedure de deploiement (3 phases)

### Phase 1 - Telecharger l'ISO PBS

```bash
ssh -i ~/.ssh/proxmox_lab root@192.168.3.23
cd /var/lib/vz/template/iso/
wget https://enterprise.proxmox.com/iso/proxmox-backup-server_4.0-1.iso
ls -lh proxmox-backup-server_4.0-1.iso
```

Verifier la version exacte sur https://www.proxmox.com/en/downloads/proxmox-backup-server

### Phase 2 - Provisionner la VM

```bash
cd ~/Virtualisation/pbs-stack/terraform

# Copier les credentials
cp ~/Virtualisation/netbox-stack/terraform/terraform.tfvars .
cp -r ~/Virtualisation/netbox-stack/terraform/.terraform .
cp ~/Virtualisation/netbox-stack/terraform/.terraform.lock.hcl .

# Adapter le chemin de l'ISO si necessaire dans terraform.tfvars
# Verifier avec : ssh root@192.168.3.23 "ls /var/lib/vz/template/iso/"

# Provisionner
terraform init
terraform apply -auto-approve
```

⏱ Duree : ~1 min pour creer la VM.

### Phase 3 - Installation interactive PBS

L'installation initiale est **interactive** via la console.

1. Ouvrir Proxmox Web UI : https://192.168.3.21:8006
2. Aller sur **pve-03 > pbs-01 (VMID 700)**
3. Demarrer la VM (Start)
4. Cliquer sur **Console** (noVNC)

#### Etapes installation PBS

1. **Boot screen** : selectionner "Install Proxmox Backup Server (Graphical)"
2. **License agreement** : "I agree"
3. **Hard disk** : selectionner `/dev/sda` (8 GB) -- NE PAS toucher sda1 (50 GB)
   - Options avances : laisser ext4
4. **Location and Time zone** :
   - Country : France
   - Time zone : Europe/Paris
   - Keyboard : French
5. **Password** : `Ynov2026!` (ou ton mot de passe)
   - Email : `admin@infra.lan`
6. **Network configuration** :
   - Management interface : `ens18`
   - Hostname FQDN : `pbs-01.infra.lan`
   - IP address : `10.0.60.20/24`
   - Gateway : `10.0.60.1`
   - DNS server : `10.0.20.10`
7. **Summary** : verifier, puis Install
8. Attendre ~5 min, puis Reboot

⚠️ **Apres reboot**, retirer l'ISO :
- Dans Proxmox UI : Hardware -> CD/DVD Drive -> Edit -> "Do not use any media"

### Phase 4 - Configuration post-installation

Apres l'install, se connecter en SSH :

```bash
ssh -o StrictHostKeyChecking=no root@10.0.60.20
```

#### A. Mettre a jour le systeme

```bash
# Sur pbs-01
# Desactiver le repo enterprise (sans abonnement)
sed -i 's|^deb |#deb |g' /etc/apt/sources.list.d/pbs-enterprise.list

# Ajouter le repo no-subscription
cat > /etc/apt/sources.list.d/pbs-no-subscription.list << 'EOF'
deb http://download.proxmox.com/debian/pbs trixie pbs-no-subscription
EOF

# Update
apt update
apt -y upgrade
```

#### B. Creer le datastore sur le disque additionnel

```bash
# Sur pbs-01
# Le 2eme disque (50 GB) est /dev/sdb
fdisk -l | grep -A 3 "Disk /dev/sdb"

# Formater
mkfs.ext4 -L pbs-datastore /dev/sdb

# Monter
mkdir -p /mnt/datastore
echo "LABEL=pbs-datastore /mnt/datastore ext4 defaults 0 2" >> /etc/fstab
mount /mnt/datastore

# Verifier
df -h | grep datastore
```

#### C. Creer le datastore dans PBS Web UI

1. Aller sur https://10.0.60.20:8007 (login : `root` / mot de passe choisi)
2. **Datastore > Add Datastore**
   - Name : `backups`
   - Backing Path : `/mnt/datastore`
   - GC Schedule : daily 02:00
   - Prune Schedule : daily 03:00
3. **Add**

## Integration avec le cluster Proxmox

### A. Recuperer le fingerprint PBS

```bash
ssh root@10.0.60.20 "proxmox-backup-manager cert info | grep -i fingerprint"
```

Copier le fingerprint affiche (forme : `XX:XX:XX:...`).

### B. Ajouter PBS comme storage dans le cluster Proxmox

Sur **n'importe quel nœud PVE** (UI Proxmox) :

1. **Datacenter > Storage > Add > Proxmox Backup Server**
2. Renseigner :
   - ID : `pbs-01`
   - Server : `10.0.60.20`
   - Username : `root@pam`
   - Password : mot de passe PBS
   - Datastore : `backups`
   - Fingerprint : (colle ici)
3. **Add**

### C. Creer un job de backup

1. **Datacenter > Backup > Add**
   - Storage : `pbs-01`
   - Schedule : `daily 04:00`
   - Selection : All
   - Mode : Snapshot
   - Compression : zstd
2. **Create**

## Acces depuis Windows (optionnel)

NAT inbound OPNsense :

| Champ | Valeur |
|-------|--------|
| Interface | WAN |
| Protocol | TCP |
| Destination port | 8007 |
| Redirect IP | 10.0.60.20 |
| Redirect port | 8007 |

Acces : `https://192.168.80.141:8007`

## Memory pressure

Avec 1 GB de RAM, PBS peut etre tendu. Surveillance :

```bash
ssh root@10.0.60.20 "free -h && systemctl status proxmox-backup-proxy | head -10"
```

Si OOM, augmenter la RAM :
```bash
ssh root@192.168.3.23 "qm set 700 -memory 2048"
ssh root@192.168.3.23 "qm reboot 700"
```

## Pour le rapport

Points valorisants :
- ✅ **Sauvegardes incrementales** : PBS ne stocke que les blocs modifies (dedup)
- ✅ **Verification d'integrite** : checksums automatiques
- ✅ **Retention configurable** : grandfather-father-son (GFS)
- ✅ **GC + Prune** : nettoyage automatique
- ✅ **Restore granulaire** : file-level restore possible

## Structure du projet

```
pbs-stack/
├── README.md
└── terraform/
    ├── main.tf                  VM 700 (1vCPU/1GB/8GB+50GB)
    └── terraform.tfvars.example
```
