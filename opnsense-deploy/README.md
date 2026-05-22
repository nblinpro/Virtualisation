# Deploiement automatise d'OPNsense (VM 100)

Ce playbook automatise la creation de la VM 100 OPNsense sur pve-01 avec restoration du XML de configuration existant (47 regles, 7 VLANs, alias, DHCP Kea).

## Pre-requis

1. **Cluster Proxmox + Ceph deja deploye** (via le playbook bootstrap)
2. **Bridges configures** : vmbr0 (WAN), vmbr1 (LAN admin), vmbr3 (trunk VLAN)
3. **Pool de stockage Ceph** `ceph_vm` operationnel
4. **Internet sur pve-01** (pour telecharger l'ISO OPNsense)
5. **Cle SSH proxmox_lab** deja deployee sur pve-01

## Architecture cible

```
                 pve-01 (host)
                     |
            +--------+--------+
            |   VM 100 fw-01  |  (OPNsense)
            +-----------------+
              | net0 -> vmbr0 (vtnet0 - WAN)
              | net1 -> vmbr1 (vtnet1 - LAN 192.168.3.250)
              | net2 -> vmbr3 (vtnet2 - OPT1 trunk VLAN)
              +
```

OPNsense aura 3 interfaces apres restore :
- **vtnet0 = WAN** : DHCP via VMware NAT (192.168.80.X) ou Bridged
- **vtnet1 = LAN** : 192.168.3.250/24 (reseau admin)
- **vtnet2 = OPT1** : trunk parent pour 7 VLANs (DMZ, CORE, LAN_USERS, BACKEND_WEB, BACKEND_DB, MONITORING, BACKUP)

## Specifications VM

| Element | Valeur |
|---------|--------|
| VMID | 100 |
| Nom | fw-01 |
| RAM | 2 Go |
| vCPUs | 2 (host CPU) |
| BIOS | UEFI (OVMF) |
| Machine | q35 |
| Disque | 16 Go sur ceph_vm (avec iothread) |
| Reseau 1 | virtio @ vmbr0 |
| Reseau 2 | virtio @ vmbr1 |
| Reseau 3 | virtio @ vmbr3 |
| Console | serial0 (pour acces SSH/qm terminal) |

## Utilisation

### Workflow complet

```bash
# 1. PHASE 1 : Telechargement ISO + Creation VM (automatique, ~3-5 min)
ansible-playbook playbook-opnsense.yml --tags vm

# 2. INSTALLATION : Manuelle via console
ssh -i ~/.ssh/proxmox_lab root@192.168.3.21
qm terminal 100
# - Login : installer / opnsense
# - Keymap : fr-oss
# - Install (UFS)
# - Selectionner le seul disque dispo
# - Confirmer
# - Reboot
# Pour quitter la console serie : Ctrl+O puis Enter

# 3. Apres reboot, retirer l'ISO
ssh -i ~/.ssh/proxmox_lab root@192.168.3.21 "qm set 100 --delete ide2"

# 4. PHASE 2 : Restoration du XML (instructions affichees)
ansible-playbook playbook-opnsense.yml --tags restore
```

### Workflow en une seule commande (PAS recommande)

```bash
# Lance les 2 phases, mais affiche juste les instructions pour l'install manuelle
ansible-playbook playbook-opnsense.yml
```

## Configuration restoree par le XML

Le XML restoré configure automatiquement :
- **47 regles de pare-feu** (inter-VLAN, Internet, services)
- **14 alias** (BACKEND_WEB, DB_SERVERS, WEB_PORTS, etc.)
- **7 VLANs** sur OPT1 :
  - VLAN 10 (DMZ)
  - VLAN 20 (CORE)
  - VLAN 30 (LAN_USERS)
  - VLAN 40 (BACKEND_WEB)
  - VLAN 50 (BACKEND_DB)
  - VLAN 60 (MONITORING)
  - VLAN 99 (BACKUP)
- **DHCP Kea** pour les VLANs
- **DNS** : pointe sur 10.0.20.10 (dns-01)
- **Hostname** : fw-01.infra.lan
- **Timezone** : Europe/Paris

## Variables importantes

Dans `group_vars/all.yml` :

```yaml
opnsense_version: "25.7"      # Version OPNsense a telecharger
vm_storage: "ceph_vm"         # Stockage Ceph
vm_memory: 2048               # 2 Go RAM
vm_cores: 2
opnsense_lan_ip: "192.168.3.250"
```

## Acces a OPNsense apres deploiement

### Depuis Windows hote

1. Acces web : `https://192.168.3.250` (avec route statique ajoutee)
   ```powershell
   route -p add 192.168.3.0 mask 255.255.255.0 <IP_VMnet1_de_Windows>
   ```

2. Login par defaut : `root / opnsense` (a changer)

### Depuis deploy-01

```bash
ssh root@192.168.3.250
```

## Troubleshooting

### "Pas d'acces Internet sur pve-01"

→ Verifier `ip -4 addr show vmbr0` et `ping 8.8.8.8` depuis pve-01.
→ Si DHCP echoue, voir l'etat de VMware NAT/Bridged sur Windows.

### "VM ne demarre pas"

→ Verifier le pool ceph_vm : `pvesm status | grep ceph_vm`
→ Voir les logs : `qm log 100`

### "OPNsense LAN injoignable apres install"

→ Verifier que la VM a 3 net adapters via `qm config 100`
→ Verifier l'install OPNsense via la console serie (`qm terminal 100`)
→ Verifier que l'assignation des interfaces est correcte (option 1 du menu OPNsense)

### "MAC differents entre XML et VM cree par qm"

OPNsense identifie ses interfaces par nom (vtnet0/1/2) et non par MAC. L'ordre des bridges dans `qm create` est important :
- net0 = WAN (vtnet0)
- net1 = LAN (vtnet1)
- net2 = OPT1 (vtnet2)

Le playbook respecte cet ordre.

## Anecdote pour le rapport

Le deploiement automatise d'une VM Proxmox avec un OS particulier (OPNsense base FreeBSD) demontre la flexibilite de l'IaC. Le module `qm create` permet de :
- Creer la VM avec specifications precises
- Attacher l'ISO automatiquement
- Configurer les bridges reseau
- Definir le boot order

L'installation OS reste manuelle (5 min via console), mais la **restoration de la conf** via XML permet de retrouver **instantanement** un firewall avec ses 47 regles, 7 VLANs et alias en quelques secondes. C'est l'illustration parfaite du principe **"Infrastructure as Code"** : meme la conf des appliances reseau est versionnee dans Git.
