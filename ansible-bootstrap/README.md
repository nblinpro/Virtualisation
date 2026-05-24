# Bootstrap Proxmox VE 9 + Ceph automatise

Ce projet automatise le bootstrap complet d'un cluster Proxmox VE 9 avec stockage Ceph.

## Architecture cible

```
                        Internet
                            |
                    +-------+--------+
                    |   FAI Box      |
                    | 192.168.1.254  |
                    +-------+--------+
                            |
                            | (Bridged sur le LAN domestique 192.168.1.0/24)
                            |
              +-------+  +-------+  +-------+
              | pve-01|  | pve-02|  | pve-03|
              | IP DHCP|  | IP DHCP| | IP DHCP|  <-- IPs au demarrage
              |.1.69  |  |.1.151 |  |.1.38  |
              +-------+  +-------+  +-------+

              Apres le playbook, les PVE auront leurs IPs finales :
              
              +-------+  +-------+  +-------+
              | pve-01|  | pve-02|  | pve-03|
              |.3.21  |  |.3.22  |  |.3.23  |  <-- IPs finales (VMnet1)
              +-------+  +-------+  +-------+
              | OSD  |   | OSD  |   | OSD  |
              | 30Go |   | 30Go |   | 30Go |  -> Ceph pool ceph_vm
              +-------+  +-------+  +-------+
                        Cluster + Ceph
                       192.168.254.0/24 (VMnet2)
```

## Pre-requis

### Sur Windows hote

1. **3 VMs Proxmox** installees (depuis l'ISO Proxmox VE 9)
2. Sur **chaque VM Proxmox** :
   - 4 Network Adapters dans VMware Settings :
     - Adapter 1 : **VMnet1** (host-only 192.168.3.0/24)
     - Adapter 2 : **Bridged** (sur ton Wi-Fi physique - pour WAN d'OPNsense plus tard)
     - Adapter 3 : **VMnet2** (host-only 192.168.254.0/24)
     - Adapter 4 : **LAN Segment "lab-trunk"** (pour trunk VLANs)
   - 2 disques :
     - Disque 1 : 40 Go (systeme Proxmox)
     - Disque 2 : 30+ Go (pour Ceph OSD)
3. **IP DHCP du LAN domestique attribuee** (l'Adapter 2 Bridged donne cette IP)
4. **Cle SSH deployee** depuis l'hote qui va lancer Ansible

### Sur la machine qui lance Ansible

La machine doit avoir acces aux PVE via leur IP DHCP (192.168.1.X).

**Si tu lances depuis deploy-01** (qui est sur VMnet1), tu dois lui donner acces a 192.168.1.0/24 :
- Ajouter un Network Adapter Bridged a la VM deploy-01 dans VMware
- Apres `dhclient`, deploy-01 aura une IP 192.168.1.X et pourra joindre les PVE

**Si tu lances depuis Windows (WSL)** : pas de probleme, tu es directement sur le bon reseau.

## Procedure d'utilisation

### Etape 1 : Mettre les IPs DHCP actuelles des PVE dans l'inventaire

```bash
nano inventory.ini
```

Adapter les `ansible_host` selon les IPs DHCP attribuees par ta box :

```ini
pve-01 ansible_host=192.168.80.133 node_id=1
pve-02 ansible_host=192.168.80.134 node_id=2
pve-03 ansible_host=192.168.80.135 node_id=3
```

### Etape 2 : Deployer la cle SSH

```bash

for ip in 192.168.1.69 192.168.1.151 192.168.1.38; do
    echo "=== $ip ==="
    ssh-copy-id -o StrictHostKeyChecking=no -i ~/.ssh/proxmox_lab.pub root@$ip
done
```

### Etape 3 : Tester la connectivite

```bash
cd ansible-bootstrap/
ansible -i inventory.ini pve_nodes -m ping
```

Tu dois avoir 3 SUCCESS.

### Etape 4 : Lancer le bootstrap

```bash
ansible-playbook playbook-bootstrap.yml --tags phase1
ansible-playbook playbook-bootstrap.yml
```

Le playbook va te demander le **mot de passe root Proxmox** (utilise pour `pvecm add`).

⏱️ Duree totale : **~25-30 minutes**.

## Ce que fait le playbook (etape par etape)

### Phase 1 - Configuration reseau (5 min)

- Detecte les 4 interfaces physiques (nic0/1/2/3)
- Configure /etc/network/interfaces avec 4 bridges :
  - vmbr0 : IP statique 192.168.3.X/24 (management)
  - vmbr1 : sans IP, bridge pour WAN OPNsense
  - vmbr2 : IP statique 192.168.254.X/24 (cluster)
  - vmbr3 : sans IP, VLAN-aware (trunk pour OPNsense OPT1)
- Configure /etc/hosts
- Installe ifupdown2 et outils reseau
- Configure les depots APT (retire enterprise, ajoute no-subscription)
- **Reload le reseau via at + sleep pour eviter perte SSH instantanee**

**ATTENTION** : Apres cette phase, les PVE changent d'IP. Ansible bascule automatiquement sur les nouvelles IPs (192.168.3.21/22/23).

### Phase 2 - Bascule d'IP (5-15 sec)

Ansible attend que les PVE repondent sur leur nouvelle IP avant de continuer.

### Phase 3 - Cluster Proxmox (5 min)

- Cree le cluster sur pve-01 (`pvecm create`)
- Fait join de pve-02 et pve-03 (`pvecm add`) sequentiellement

### Phase 4 - Ceph (10-15 min)

- Ajoute le depot Ceph no-subscription
- Installe Ceph squid
- `pveceph init` sur pve-01 (avec networks public/cluster)
- Cree 3 MONs (un par noeud, sequentiel)
- Cree les MGRs
- Cree 3 OSDs sur /dev/sdb (sequentiel)
- Cree le pool RBD `ceph_vm` (size=2, min_size=1)

### Phase 5 - Resume

Affiche l'etat final du cluster et de Ceph.

## Idempotence

Le playbook peut etre relance plusieurs fois sans risque :
- Si la config reseau est deja en place, rien ne change
- Si le cluster existe, il n'est pas recree
- Si les MON/MGR/OSD existent, ils ne sont pas recrees

## Verification apres deploiement

```bash
# Cluster
ssh root@192.168.3.21 "pvecm status"

# Ceph
ssh root@192.168.3.21 "ceph -s"
ssh root@192.168.3.21 "ceph osd tree"
ssh root@192.168.3.21 "ceph osd pool ls"

# Web UI Proxmox
# https://192.168.3.21:8006
```

## Prochaines etapes

Une fois le bootstrap termine :

1. **Acceder a Proxmox** : https://192.168.3.21:8006
2. **Creer la VM 100 OPNsense** (manuellement, depuis l'ISO)
3. **Configurer OPNsense** : LAN sur vmbr0, WAN sur vmbr1, OPT1 sur vmbr3
4. **Restore XML** OPNsense (47 regles, 7 VLANs, etc.)
5. **Provisionner les LXC** via Terraform (`projet-infra-iac/terraform`)
6. **Configurer les LXC** via Ansible (`projet-infra-iac/ansible/playbook-all.yml`)

## Troubleshooting

### "Il faut au moins 4 interfaces physiques"

→ Verifier dans VMware Settings que les 4 Network Adapters sont presents et "Connected".

### "Permission denied" sur ssh-copy-id

→ Verifier que SSH root est autorise sur Proxmox (`PermitRootLogin yes` dans `/etc/ssh/sshd_config`).

### Ansible perd la connexion apres la phase 1

→ C'est NORMAL. L'IP change. Ansible bascule automatiquement. Si ca echoue, attendre 30 secondes et relancer le playbook : il reprendra a la phase 2.

### "Le disque /dev/sdb n'existe pas"

→ Verifier dans VMware Settings que le 2e disque est bien attache aux VMs.
→ Pour utiliser un autre disque, modifier `ceph_disk_path` dans `group_vars/all.yml`.

### "pvecm add" echoue (mauvais mot de passe)

→ Le mot de passe root des 3 PVE doit etre le meme.
→ Verifier que tu peux te connecter en SSH avec ce mot de passe.

## Anecdote pour le rapport

Ce playbook represente une **automatisation IaC complete** de la couche hyperviseur. Avant ce script, le bootstrap manuel d'un cluster Proxmox + Ceph prenait **2 heures** (clics dans l'interface web, mots de passe a taper, attente entre etapes). Avec ce playbook, le meme deploiement prend **30 minutes** et est **100% reproductible**.

C'est la difference fondamentale entre l'**administration traditionnelle** (clic-clic-clic) et l'**Infrastructure as Code** (un fichier Yaml, une commande).
