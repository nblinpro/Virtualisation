# Bootstrap Proxmox VE 9 + Ceph (semi-automatisé)

Ce projet automatise le bootstrap réseau et Ceph d'un cluster Proxmox VE 9 à 3
noeuds. **La création du cluster Proxmox (corosync) se fait manuellement**,
entre les phases 1/2 (réseau) et la phase 4 (Ceph) : le playbook se contente
de **vérifier** que le cluster existe avant d'installer Ceph dessus.

## Vue d'ensemble du déroulé

```
Phase 1 (ansible) : réseau + dépôts APT          -> automatique
Phase 2 (ansible) : vérification des IPs         -> automatique
   --- suppression de la LXC/VM de déploiement ---  -> MANUEL
   --- création du cluster Proxmox (pvecm) ---       -> MANUEL
Phase 3 (ansible) : vérification que le cluster existe -> automatique
Phase 4 (ansible) : installation Ceph (MON/MGR/OSD/pool) -> automatique
Phase 5 (ansible) : résumé final (pvecm status + ceph -s) -> automatique
```

## Architecture cible

Chaque noeud Proxmox dispose de **4 interfaces réseau physiques** (`nic0` à
`nic3`, détectées automatiquement par le rôle `pve_network`) qui sont
transformées en 4 bridges :

| Bridge  | Interface | Rôle                                   | Adressage                          |
|---------|-----------|-----------------------------------------|-------------------------------------|
| `vmbr0` | nic1      | Internet (Bridged sur le Wi-Fi/LAN)     | **DHCP, inchangé** (sert à la connexion Ansible initiale) |
| `vmbr1` | nic0      | Management/admin (VMnet1 host-only)     | Statique `192.168.3.X/24`           |
| `vmbr2` | nic2      | Cluster Corosync + Ceph (VMnet2 host-only) | Statique `192.168.254.X/24`      |
| `vmbr3` | nic3      | Trunk VLAN (LAN Segment, pour OPNsense plus tard) | Sans IP, `bridge-vlan-aware yes`, VLANs 2-4094 |

```
                        Internet / LAN domestique
                                |
                        +-------+--------+
                        |   Box / Wi-Fi  |
                        +-------+--------+
                                |  (Adapter Bridged -> vmbr0, DHCP, INCHANGE)
              +-------+     +-------+     +-------+
              | pve-01|     | pve-02|     | pve-03|
              +-------+     +-------+     +-------+
                  |  vmbr1 (VMnet1, admin static)         |
                  | .3.21         .3.22          .3.23    |
                  |  vmbr2 (VMnet2, cluster + ceph)        |
                  | .254.21       .254.22        .254.23   |
                  |  vmbr3 (trunk VLAN, pour OPNsense OPT1) |
                  +------------------------------------------+
                         Cluster Proxmox "ynov-lab" + Ceph
```

Important : contrairement à une version précédente du projet, **`vmbr0`
garde son IP DHCP du début à la fin** (commentaire dans le template :
`INCHANGE`). C'est `vmbr1` qui reçoit l'IP d'admin statique. Ansible continue
donc de se connecter aux noeuds via leur IP DHCP (`inventory.ini`) pendant
toutes les phases automatisées — il n'y a pas de bascule d'IP en plein
playbook.

## Structure du projet

```
ansible-bootstrap/
├── ansible.cfg                     # config Ansible (inventaire, ssh, forks...)
├── inventory.ini                   # IPs DHCP actuelles des 3 PVE + groupes
├── playbook-bootstrap.yml          # playbook principal (5 phases)
├── group_vars/
│   ├── all.yml                     # réseaux, nom du cluster, conf Ceph
│   └── pve_nodes.yml                # IP mgmt/cluster + node_id par noeud
└── roles/
    ├── pve_network/                # Phase 1 : interfaces, /etc/hosts, dépôts APT
    │   ├── tasks/main.yml
    │   ├── handlers/main.yml
    │   └── templates/interfaces.j2
    ├── pve_cluster/                 # Présent mais NON utilisé par le playbook
    │   └── tasks/main.yml           # (cf. section "Création manuelle du cluster")
    └── pve_ceph/                    # Phase 4 : MON/MGR/OSD/pool RBD
        └── tasks/main.yml
```

> ℹ️ Le rôle `roles/pve_cluster` existe toujours dans le repo (il sait créer
> le cluster et y faire joindre les noeuds via `pvecm create` / `pvecm add`),
> mais **il n'est plus appelé par `playbook-bootstrap.yml`**. Il sert de
> référence pour reproduire les mêmes commandes manuellement (voir plus bas).

## Pré-requis

### Sur l'hôte (Windows/hyperviseur)

1. **3 VMs Proxmox VE 9** installées depuis l'ISO.
2. Sur **chaque VM Proxmox**, 4 Network Adapters :
   - Adapter 1 → **VMnet1** (host-only `192.168.3.0/24`) → deviendra `vmbr1` (nic0)
   - Adapter 2 → **Bridged** sur le Wi-Fi/LAN physique → deviendra `vmbr0` (nic1, DHCP)
   - Adapter 3 → **VMnet2** (host-only `192.168.254.0/24`) → deviendra `vmbr2` (nic2)
   - Adapter 4 → **LAN Segment "lab-trunk"** → deviendra `vmbr3` (nic3, trunk VLAN)
3. 2 disques par noeud :
   - Disque 1 : 20 Go (système Proxmox)
   - Disque 2 : 30+ Go (réservé à l'OSD Ceph, `/dev/sdb` par défaut)
4. IP DHCP du LAN domestique obtenue par chaque noeud (Adapter 2 Bridged).

### Sur la machine qui lance Ansible

```bash
apk add ansible openssh sshpass wget unzip   # ou apt/dnf selon ta distro
ansible --version
```

**Deux façons de lancer Ansible :**

- **Depuis une LXC/VM de déploiement ("deploy-01") posée sur VMnet1** : tant
  que les noeuds n'ont que leur IP DHCP (avant la Phase 1), cette LXC a
  besoin d'un Network Adapter Bridged temporaire pour atteindre le LAN
  domestique (`192.168.1.0/24`) où traînent les IPs DHCP des PVE.
- **Depuis Windows/WSL** : si l'hôte a déjà accès au Wi-Fi/LAN et à VMnet1
  nativement, pas besoin de LXC intermédiaire.

## Variables principales

### `group_vars/all.yml`

| Variable | Valeur par défaut | Description |
|---|---|---|
| `mgmt_network` / `mgmt_netmask` | `192.168.3.0` / `24` | Réseau admin (vmbr1) |
| `cluster_network` / `cluster_netmask` | `192.168.254.0` / `24` | Réseau Corosync + Ceph (vmbr2) |
| `cluster_name` | `ynov-lab` | Nom du cluster Proxmox |
| `ceph_release` | `squid` | Version Ceph |
| `ceph_disk_path` | `/dev/sdb` | Disque dédié à l'OSD |
| `ceph_pool_name` | `ceph_vm` | Pool RBD créé en Phase 4 |
| `ceph_pool_size` / `ceph_pool_min_size` | `2` / `1` | Réplication (3 noeuds) |
| `pve_repo_no_subscription` / `pve_remove_enterprise_repo` | `true` | Gestion des dépôts APT |

### `group_vars/pve_nodes.yml`

IP de management (`mgmt_ip`, sur vmbr1) et IP cluster (`cluster_ip`, sur
vmbr2) pour `pve-01`, `pve-02`, `pve-03`. À adapter si tu changes le plan
d'adressage.

## Procédure complète

### Étape 1 — Renseigner les IPs DHCP actuelles dans l'inventaire

```bash
nano inventory.ini
```

```ini
[pve_nodes]
pve-01 ansible_host=192.168.1.69  node_id=1
pve-02 ansible_host=192.168.1.151 node_id=2
pve-03 ansible_host=192.168.1.38  node_id=3
```

Ce sont les IPs DHCP du LAN domestique, obtenues via l'Adapter 2 Bridged.

### Étape 2 — Déployer la clé SSH sur les 3 noeuds

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "ansible@bootstrap" -N ""

for ip in 192.168.1.69 192.168.1.151 192.168.1.38; do
    echo "=== $ip ==="
    ssh-copy-id -o StrictHostKeyChecking=no -i ~/.ssh/id_ed25519.pub root@$ip
done
```

(`ansible_ssh_private_key_file` dans `inventory.ini` pointe déjà vers
`~/.ssh/id_ed25519`.)

### Étape 3 — Tester la connectivité

```bash
cd ansible-bootstrap/
ansible -i inventory.ini pve_nodes -m ping
```

Tu dois obtenir 3 `SUCCESS`.

### Étape 4 — Phase 1 : configuration réseau

```bash
ansible-playbook playbook-bootstrap.yml --tags phase1
```

Ce que fait cette phase (rôle `pve_network`) :
- Détecte les 4 interfaces physiques `nic0-3` (échoue si moins de 4 trouvées).
- Force le hostname et met à jour `/etc/hosts` avec les IPs admin/cluster de
  tous les noeuds.
- Retire le dépôt Proxmox/Ceph *enterprise*, ajoute les dépôts
  *no-subscription*.
- Sauvegarde l'ancien `/etc/network/interfaces`, déploie le nouveau
  (template `interfaces.j2`) avec les 4 bridges décrits plus haut, puis
  applique via `ifreload -a`.

⏱️ ~5 minutes. **`vmbr0` garde son IP DHCP** : Ansible reste connecté sur la
même IP qu'à l'étape 1, aucune bascule à gérer.

### Étape 5 — Phase 2 : vérification des IPs

```bash
ansible-playbook playbook-bootstrap.yml --tags phase2
```

Vérifie que `vmbr1` porte bien l'IP admin attendue (`pve_nodes[...].mgmt_ip`)
et affiche l'IP DHCP de `vmbr0`. Le playbook s'arrête en erreur si l'IP
admin ne correspond pas à `group_vars/pve_nodes.yml`.

### Étape 6 — (MANUEL) Suppression de la LXC/VM de déploiement

Une fois les phases 1 et 2 validées, les 3 noeuds Proxmox ont leur IP admin
statique opérationnelle sur `vmbr1` (`192.168.3.21/22/23`), routable depuis
VMnet1. La LXC/VM de déploiement temporaire (« deploy-01 »), qui ne servait
qu'à atteindre les IPs DHCP du LAN domestique le temps que `vmbr1` n'existait
pas encore, n'est plus nécessaire :

1. Supprime la LXC/VM de déploiement depuis l'interface Proxmox (ou
   `pct destroy <vmid>` / `qm destroy <vmid>` selon le type).
2. Poursuis la procédure **directement depuis ton poste hôte** (Windows/WSL
   ou toute machine ayant accès à VMnet1), en ciblant désormais les IPs
   admin finales :

```bash
ssh root@192.168.3.21 "echo ok"
ssh root@192.168.3.22 "echo ok"
ssh root@192.168.3.23 "echo ok"
```

> Si tu préfères continuer à utiliser `inventory.ini` avec Ansible pour les
> phases suivantes, mets à jour les `ansible_host` avec les IPs `192.168.3.21
> /22/23` à ce moment-là.

### Étape 7 — (MANUEL) Création du cluster Proxmox

Le rôle `pve_cluster` existe dans le repo mais **n'est plus appelé par le
playbook** : la création du cluster se fait main, en se connectant en SSH à
chaque noeud sur son IP cluster (`vmbr2`, réseau `192.168.254.0/24`).

**Sur le master (`pve-01`) :**

```bash
ssh root@192.168.3.21
pvecm create ynov-lab --link0 192.168.254.21
pvecm status   # vérifier que le cluster est bien créé
```

**Sur chaque slave (`pve-02` puis `pve-03`, l'un après l'autre) :**

```bash
ssh root@192.168.3.22
pvecm add 192.168.254.21 --link0 192.168.254.22 --use_ssh
# saisir le mot de passe root de pve-01 si demandé
# répondre "yes" à la confirmation de fingerprint SSH

pvecm status   # vérifier que le noeud a bien rejoint le cluster
```

Puis la même chose sur `pve-03` avec `--link0 192.168.254.23`.

Vérifie l'état global depuis le master :

```bash
ssh root@192.168.3.21 "pvecm status"
```

Tu dois voir les 3 noeuds avec `Quorate: Yes`.

### Étape 8 — Phase 3 : vérification du cluster (automatique)

```bash
ansible-playbook playbook-bootstrap.yml --tags phase3
```

Cette phase tourne sur `cluster_master` (`pve-01`) et lance `pvecm status` ;
elle **échoue volontairement** si le cluster n'a pas été créé manuellement à
l'étape précédente.

### Étape 9 — Phase 4 : Ceph (automatique)

```bash
ansible-playbook playbook-bootstrap.yml --tags phase4
```

Ce que fait cette phase (rôle `pve_ceph`) sur les 3 noeuds :
1. Ajoute le dépôt Ceph no-subscription (`ceph_release: squid`).
2. Installe `ceph`, `ceph-osd`, `ceph-mon`, `ceph-mgr`.
3. `pveceph init` sur le master, avec réseaux public (`vmbr1`) et cluster (`vmbr2`).
4. Crée un MON sur chaque noeud (séquentiel, avec retries).
5. Crée un MGR sur chaque noeud.
6. Crée un OSD sur `ceph_disk_path` (`/dev/sdb` par défaut) sur chaque noeud
   (échoue si le disque n'existe pas).
7. Crée le pool RBD `ceph_vm` (size=2, min_size=1, pg_num=32) sur le master.

⏱️ ~10-15 minutes.

### Étape 10 — Phase 5 : résumé (automatique)

```bash
ansible-playbook playbook-bootstrap.yml --tags phase5
```

Affiche `pvecm status` et `ceph -s` finaux.

### Tout enchaîner d'un coup (hors étapes manuelles 6 et 7)

```bash
ansible-playbook playbook-bootstrap.yml --tags phase1
ansible-playbook playbook-bootstrap.yml --tags phase2
#  -> suppression de la LXC de déploiement + création manuelle du cluster ici
ansible-playbook playbook-bootstrap.yml --tags phase3,phase4,phase5
```

(Lancer `playbook-bootstrap.yml` sans `--tags` exécute les 5 phases dans
l'ordre ; la phase 3 plantera si le cluster n'a pas été créé manuellement
entre-temps.)

## Idempotence

Le playbook peut être relancé sans risque :
- Si la config réseau est déjà en place, rien ne change (`ifreload` n'est
  déclenché que si le template change).
- Phase 3 ne fait que vérifier l'existence du cluster, jamais ne le crée.
- Phase 4 vérifie systématiquement avant de créer : Ceph installé ?
  `ceph.conf` présent ? MON/MGR existants ? disque déjà formaté (`blkid`) ?
  pool déjà créé ?

## Vérification après déploiement

```bash
# Cluster
ssh root@192.168.3.21 "pvecm status"

# Ceph
ssh root@192.168.3.21 "ceph -s"
ssh root@192.168.3.21 "ceph osd tree"
ssh root@192.168.3.21 "ceph osd pool ls"

# Interface web Proxmox
# https://192.168.3.21:8006
```

## Prochaines étapes

Une fois le bootstrap terminé :

1. **Accéder à Proxmox** : https://192.168.3.21:8006
2. **Créer la VM 100 OPNsense** (manuellement, depuis l'ISO) :
   ```bash
   cd /var/lib/vz/template/iso
   wget https://mirror.ams1.nl.leaseweb.net/opnsense/releases/26.1/OPNsense-26.1-dvd-amd64.iso.bz2
   bunzip2 OPNsense-26.1-dvd-amd64.iso.bz2
   ```
3. **Configurer OPNsense** : LAN sur `vmbr1`, WAN sur `vmbr0`, OPT1 trunk sur `vmbr3`.
4. **Restaurer la conf XML** OPNsense (règles, VLANs, etc.).
5. **Provisionner les LXC** via Terraform.
6. **Configurer les LXC** via Ansible (playbook séparé).

## Troubleshooting

### « Il faut au moins 4 interfaces physiques »

→ Vérifie dans les paramètres de l'hyperviseur que les 4 Network Adapters
sont présents et connectés sur chaque VM Proxmox.

### « Permission denied » sur `ssh-copy-id`

→ Vérifie que SSH root est autorisé sur Proxmox (`PermitRootLogin yes` dans
`/etc/ssh/sshd_config`).

### Ansible perd la connexion après la Phase 1

→ Ne devrait normalement pas arriver : `vmbr0` (utilisé pour la connexion
Ansible) garde son IP DHCP. Si ça arrive quand même, attends ~30 secondes
que `ifreload -a` termine et relance la commande de la phase concernée.

### La Phase 3 échoue avec « cluster_check.rc != 0 »

→ C'est normal si tu n'as pas encore fait l'étape manuelle 7 (création du
cluster). Connecte-toi en SSH sur `pve-01` et lance `pvecm status` pour
vérifier ; crée le cluster avec `pvecm create` si besoin.

### « Le disque /dev/sdb n'existe pas »

→ Vérifie que le 2e disque (30+ Go) est bien attaché à chaque VM Proxmox.
→ Pour utiliser un autre disque, modifie `ceph_disk_path` dans
`group_vars/all.yml`.

### `pvecm add` échoue (mauvais mot de passe)

→ Le mot de passe root des 3 PVE doit être identique, ou en tout cas connu
au moment du `pvecm add --use_ssh`.
→ Vérifie que tu peux te connecter en SSH avec ce mot de passe avant de
relancer la commande.

### Je ne peux plus joindre les noeuds après avoir supprimé la LXC de déploiement

→ Vérifie que tu lances bien les commandes suivantes (manuelles ou via
Ansible) depuis une machine ayant accès à VMnet1 (`192.168.3.0/24`), et que
tu cibles bien les IPs admin finales (`192.168.3.21/22/23`) et non plus les
anciennes IPs DHCP.
