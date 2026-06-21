# Infrastructure applicative : DNS + PostgreSQL + Cluster Web HA

Déploiement automatisé d'une chaîne applicative complète, en aval du cluster
Proxmox/Ceph (voir le projet `ansible-bootstrap`), via :

- **Terraform** (`terraform/`) : provisionnement des 8 conteneurs LXC sur le
  cluster Proxmox (DNS x2, PostgreSQL, Web x3, Load Balancer x2), génère
  automatiquement l'inventaire Ansible.
- **Ansible** (`ansible/`) : installation et configuration des services sur
  ces LXC (BIND9, AdGuard Home, PostgreSQL 17, Nginx+PHP, HAProxy+Keepalived).

## Architecture déployée

| Service | Rôle | IP | VLAN | Noeud Proxmox | VMID |
|---------|------|-----|------|----------------|------|
| **dns-rec-01** | DNS récursif AdGuard Home (filtrage pub) | 10.0.20.10 | 20 (CORE) | pve-02 | 201 |
| **dns-auth-01** | DNS autoritaire BIND9 (zone `infra.lan`) | 10.0.20.11 | 20 (CORE) | pve-02 | 202 |
| **pgsql-01** | PostgreSQL 17 | 10.0.50.10 | 50 (BACKEND_DB) | pve-03 | 301 |
| **web-01/02/03** | Cluster web (Nginx + PHP-FPM 8.4) | 10.0.40.11-13 | 40 (BACKEND_WEB) | pve-01/02/03 | 401-403 |
| **lb-01** (MASTER) | HAProxy + Keepalived | 10.0.10.11 | 10 (DMZ) | pve-01 | 411 |
| **lb-02** (BACKUP) | HAProxy + Keepalived | 10.0.10.12 | 10 (DMZ) | pve-02 | 412 |
| **VIP** | Adresse virtuelle frontale (Keepalived/VRRP) | 10.0.10.100 | 10 (DMZ) | — | — |

Tous les LXC sont rattachés au bridge **`vmbr3`** (trunk VLAN-aware, voir le
projet `ansible-bootstrap`) avec un `vlan_id` Terraform différent par
service — c'est OPNsense qui route entre les VLANs.

### Ordre de dépendance (encodé dans `main.tf` via `depends_on`)

```
dns-rec-01 + dns-auth-01  →  pgsql-01  →  web-01/02/03  →  lb-01/lb-02
```

BIND9 (autoritaire) doit être **configuré** avant AdGuard (récursif), car
AdGuard forwarde la zone `infra.lan` vers BIND9 — c'est pour ça que
`playbook-dns.yml` joue le rôle `dns_bind9_auth` avant `dns_adguard_recursive`,
même si Terraform crée les deux LXC dans n'importe quel ordre relatif l'un à
l'autre (seul leur ordre vs. PostgreSQL/web/lb est contraint).

### Architecture DNS

```
[Tous les clients]
   │ DNS configuré : 10.0.20.10
   ▼
[dns-rec-01 - AdGuard Home]
   │ Filtre les pubs/trackers (filtres AdGuard + AdAway)
   │ Si zone "infra.lan" → forward conditionnel
   ▼
[dns-auth-01 - BIND9]   →   réponse autoritaire pour *.infra.lan
   │ (recursion no : refuse tout le reste)
   │
   (sinon, depuis AdGuard) → DoT vers 1.1.1.1 / 1.0.0.1 / 9.9.9.9
```

### Chemin applicatif HTTP

```
Client  →  VIP 10.0.10.100:80 (portée par lb-01 ou lb-02 via VRRP)
        →  HAProxy (roundrobin, cookie SERVERID, health-check /health.txt)
        →  web-01 / web-02 / web-03 (Nginx + PHP-FPM)
        →  PostgreSQL pgsql-01:5432 (table "messages")
```

## Structure du projet

```
dns-pgsql-web-lb/
├── terraform/
│   ├── main.tf                  # 8 conteneurs LXC (dns x2, pgsql, web x3, lb x2)
│   ├── variables.tf             # variables Terraform (token API, mdp, noeuds cibles...)
│   ├── outputs.tf               # résumé + génère ansible/inventory.ini automatiquement
│   ├── terraform.tfvars.example # modèle à copier en terraform.tfvars
│   └── terraform.tfvars         # valeurs réelles (secrets -> ne pas committer)
└── ansible/
    ├── ansible.cfg
    ├── inventory.ini            # généré par Terraform (resource local_file), NE PAS ÉDITER À LA MAIN
    ├── playbook-all.yml         # importe playbook-dns.yml + playbook-db.yml UNIQUEMENT
    ├── playbook-dns.yml         # BIND9 (autoritaire) puis AdGuard (récursif)
    ├── playbook-db.yml          # PostgreSQL 17
    ├── playbook-web.yml         # web_servers (Nginx/PHP) PUIS load_balancers (HAProxy/Keepalived)
    └── roles/
        ├── dns_bind9_auth/      # zone infra.lan, ~25 enregistrements A pré-déclarés
        ├── dns_adguard_recursive/
        ├── db_postgres/         # création DB/user applicatif + pg_hba.conf
        ├── web_nginx/           # appli PHP de démo (formulaire + PostgreSQL)
        └── lb_haproxy/          # HAProxy (LB L7) + Keepalived (VRRP/VIP)
```

> ℹ️ **`playbook-all.yml` ne joue que `playbook-dns.yml` + `playbook-db.yml`.**
> Pour le cluster web et les load balancers, il faut lancer
> `playbook-web.yml` séparément (voir Étape 6 plus bas).

## Pré-requis

### Sur le bastion de déploiement (CT Alpine Linux, `192.168.80.131`)

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

### Collections Ansible requises

Le rôle `db_postgres` installe `community.postgresql` tout seul (en
pré-tâche, sur le bastion). En revanche **`ansible.posix`** (utilisé par
`lb_haproxy` pour le module `sysctl`) n'est jamais installé automatiquement :
à faire une fois, à la main :

```bash
ansible-galaxy collection install ansible.posix community.postgresql
```

### Paire de clés SSH (réutilisée par Terraform pour injecter la clé publique dans les LXC)

```bash
ssh-keygen -t ed25519 -f ~/.ssh/proxmox_lab -N ""
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

### Pré-requis côté infrastructure

- Le cluster Proxmox + Ceph (`ansible-bootstrap`) doit déjà être opérationnel.
- Le pool de stockage Ceph cible (`ceph_pool` dans `terraform.tfvars`, ex.
  `ceph_vm`) doit exister.
- Le template LXC Debian 13 référencé par `lxc_template` doit être présent
  sur Proxmox (`local:vztmpl/...`), sinon adapter la variable.
- OPNsense doit déjà router les VLANs 10/20/40/50 utilisés ici (le bridge
  `vmbr3` est en trunk côté Proxmox, le tagging VLAN par service est fait
  côté Terraform via `vlan_id`).

## Variables principales

### `terraform/variables.tf`

| Variable | Description | Défaut |
|---|---|---|
| `proxmox_api_url` | URL API Proxmox | — (obligatoire) |
| `proxmox_api_token_id` / `proxmox_api_token_secret` | Token API Terraform | — (obligatoire) |
| `proxmox_ssh_private_key` / `ssh_public_key` | Clés SSH (déploiement + injection cloud-init) | `~/.ssh/proxmox_lab[.pub]` |
| `lxc_root_password` | Mot de passe root des LXC | — (obligatoire, sensible) |
| `dns_node` | Noeud Proxmox pour les 2 LXC DNS | `pve-02` |
| `db_node` | Noeud Proxmox pour `pgsql-01` | `pve-03` |
| `ceph_pool` | Pool de stockage Ceph | `ceph-vm` |
| `lxc_template` | Template LXC Debian | `local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst` |
| `postgres_db_name` / `postgres_db_user` / `postgres_db_password` | Base/utilisateur applicatif (informatif côté Terraform, repris par Ansible) | `webapp_db` / `webapp` / `WebApp2026!ChangeMe` |

Les noeuds des LXC web (`web-01/02/03` → `pve-01/02/03`) et LB
(`lb-01` → `pve-01`, `lb-02` → `pve-02`) sont codés en dur dans des `locals`
de `main.tf` (anti-affinité : un conteneur par hyperviseur).

### Variables Ansible par rôle (extraits, `roles/*/defaults/main.yml`)

| Rôle | Variables clés |
|---|---|
| `dns_bind9_auth` | `bind_zone: infra.lan`, `bind_allowed_xfer_clients`, `bind_allowed_query_networks`, `bind_records` (~25 enregistrements A, dont des entrées **pré-déclarées pour des services pas encore provisionnés** : `glpi-01`, `monitoring-01`/Grafana/Prometheus/Loki) |
| `dns_adguard_recursive` | `adguard_version`, `dns_authoritative_ip: 10.0.20.11`, `upstream_dns` (DoT Cloudflare/Quad9), `adguard_admin_password` |
| `db_postgres` | `postgres_version: 17`, `postgres_db_name/user/password`, `postgres_allowed_subnets` (web `10.0.40.0/24`, monitoring `10.0.60.0/24`, admin `192.168.3.0/24`), `postgres_restore_dump` |
| `web_nginx` | `db_host: pgsql-01.infra.lan`, `php_version: 8.4`, `nginx_server_name` |
| `lb_haproxy` | `keepalived_vip: 10.0.10.100`, `haproxy_backends` (web-01/02/03), `haproxy_stats_password` |

## Déploiement de l'infrastructure

### Étape 1 — Initialisation Terraform

```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
# Renseigner : proxmox_api_token_secret, lxc_root_password, chemins de clés SSH

terraform init
```

### Étape 2 — Déploiement ordonnancé

L'ordre est important pour des raisons fonctionnelles (BIND9 avant AdGuard
côté Ansible) et d'anti-affinité. Les `depends_on` dans `main.tf` garantissent
déjà cet ordre même avec un `terraform apply` global ; la méthode ci-dessous
(ciblage par étape) permet en plus de valider chaque brique avec Ansible
avant de passer à la suivante.

> À chaque `terraform apply`, le fichier `ansible/inventory.ini` est
> **régénéré automatiquement** (resource `local_file.ansible_inventory`) —
> il ne faut jamais l'éditer à la main, les modifications seraient écrasées.

#### 1. DNS autoritaire (`dns-auth-01` — BIND9)

```bash
terraform apply -target='proxmox_virtual_environment_container.dns_auth_01' -auto-approve
ssh-copy-id -i ~/.ssh/proxmox_lab.pub root@10.0.20.11
```

#### 2. DNS récursif (`dns-rec-01` — AdGuard Home)

```bash
terraform apply -target='proxmox_virtual_environment_container.dns_rec_01' -auto-approve
ssh-copy-id -i ~/.ssh/proxmox_lab.pub root@10.0.20.10
```

#### 3. Configuration des 2 DNS

```bash
cd ../ansible
ansible-playbook playbook-dns.yml
```

Joue d'abord `dns_bind9_auth` (sur `dns_authoritative`), puis
`dns_adguard_recursive` (sur `dns_recursive`). Chaque bloc se termine par des
vérifications post-tâches (`systemctl is-active`, tests `dig`).

#### 4. Base de données (`pgsql-01`)

```bash
cd ../terraform
terraform apply -target='proxmox_virtual_environment_container.pgsql_01' -auto-approve
ssh-copy-id -i ~/.ssh/proxmox_lab.pub root@10.0.50.10

cd ../ansible
ansible-playbook playbook-db.yml
```

Pour restaurer un dump SQL existant (optionnel) :

```bash
ansible-playbook playbook-db.yml -e restore_dump=true \
  -e postgres_dump_local_path=/chemin/vers/dump.sql
```

(le fichier est cherché **sur le bastion**, pas sur `pgsql-01` ; défaut :
`/home/ynov/backup-final/webapp_db.sql`).

#### 5. Cluster web (`web-01`, `web-02`, `web-03`)

```bash
cd ../terraform
terraform apply -target='proxmox_virtual_environment_container.web' -auto-approve

ssh-copy-id -i ~/.ssh/proxmox_lab.pub root@10.0.40.11
ssh-copy-id -i ~/.ssh/proxmox_lab.pub root@10.0.40.12
ssh-copy-id -i ~/.ssh/proxmox_lab.pub root@10.0.40.13

cd ../ansible
ansible-playbook playbook-web.yml --limit web_servers
```

#### 6. Load Balancers (`lb-01`, `lb-02`)

```bash
cd ../terraform
terraform apply -target='proxmox_virtual_environment_container.lb' -auto-approve

ssh-copy-id -i ~/.ssh/proxmox_lab.pub root@10.0.10.11
ssh-copy-id -i ~/.ssh/proxmox_lab.pub root@10.0.10.12

cd ../ansible
ansible-playbook playbook-web.yml --limit load_balancers
```

### Tout enchaîner d'un coup (après le tout premier `ssh-copy-id` de chaque hôte)

```bash
cd terraform/ && terraform apply -auto-approve && cd ../ansible
ansible-playbook playbook-dns.yml
ansible-playbook playbook-db.yml
ansible-playbook playbook-web.yml
```

## Validation DNS

```bash
# Résolution interne via AdGuard → BIND9
dig @10.0.20.10 pve-01.infra.lan +short
# Attendu : 192.168.3.21

# Résolution externe via AdGuard (DoT Cloudflare/Quad9)
dig @10.0.20.10 google.com +short

# Test direct sur BIND9 (autoritaire)
dig @10.0.20.11 web-01.infra.lan +short
# Attendu : 10.0.40.11

# BIND9 doit REFUSER les requêtes hors zone (recursion no)
dig @10.0.20.11 google.com +short
# Attendu : (vide)

# Vérifier que les pubs sont bloquées
dig @10.0.20.10 doubleclick.net +short
# Attendu : 0.0.0.0 ou NXDOMAIN
```

## Validation PostgreSQL

```bash
ssh root@10.0.50.10 "systemctl is-active postgresql"
ssh root@10.0.50.10 "sudo -u postgres psql -l"
psql -h 10.0.50.10 -U webapp -d webapp_db -c "\dt"   # depuis un hôte autorisé (10.0.40.0/24, 10.0.60.0/24, 192.168.3.0/24)
```

## Validation Web + Load Balancing

```bash
# Accès direct à un backend
curl -s http://10.0.40.11/health.txt        # OK

# Accès via la VIP (HAProxy, roundrobin)
for i in 1 2 3 4 5 6; do
  curl -s -D - http://10.0.10.100/ -o /dev/null | grep X-Served-By
done
# Doit alterner entre web-01, web-02, web-03 (cookie SERVERID en sticky-session sinon)

# Statistiques HAProxy
curl -u admin:Stats2026! http://10.0.10.100:8404/stats
```

### Test de bascule Keepalived (failover VIP)

```bash
ssh root@10.0.10.11 "systemctl stop haproxy"
sleep 5
# La VIP 10.0.10.100 doit basculer vers lb-02 (vérifier via `ip a` sur lb-02
# ou en testant à nouveau curl http://10.0.10.100/)
ip a show eth0 | grep 10.0.10.100   # à lancer sur lb-02

ssh root@10.0.10.11 "systemctl start haproxy"
# La VIP repasse sur lb-01 (priority 110 > 100, état MASTER)
```

## Interface AdGuard Home

URL : <http://10.0.20.10:3001> (depuis le LAN admin ou via NAT inbound)

- Login : `admin`
- Mot de passe : `Ynov2026!`

Statistiques disponibles : requêtes/seconde, top domaines, top clients,
pubs/trackers bloqués, logs de toutes les requêtes.

## Cartographie DNS & plan d'adressage

| Nom DNS | Adresse IPv4 | Zone / VLAN |
|---------|--------------|-------------|
| pve-01/02/03.infra.lan | 192.168.3.21-23 | Management |
| fw-01 / opnsense.infra.lan | 192.168.3.250 | Gateway |
| **dns-rec-01.infra.lan** | **10.0.20.10** | **VLAN 20 (CORE)** |
| **dns-auth-01.infra.lan** | **10.0.20.11** | **VLAN 20 (CORE)** |
| web.infra.lan / lb.infra.lan | 10.0.10.100 (VIP) | VLAN 10 (DMZ) |
| lb-01.infra.lan | 10.0.10.11 | VLAN 10 (DMZ) |
| lb-02.infra.lan | 10.0.10.12 | VLAN 10 (DMZ) |
| web-01/02/03.infra.lan | 10.0.40.11-13 | VLAN 40 |
| pgsql-01.infra.lan / db.infra.lan | 10.0.50.10 | VLAN 50 (DB) |

> Le fichier de zone BIND9 contient aussi des enregistrements pour des
> services **pas encore déployés par Terraform** (`glpi-01` en
> `10.0.20.50`, `monitoring-01`/Grafana/Prometheus/Loki en `10.0.60.10`) :
> ce sont des entrées préparées pour une extension future du lab, pas une
> erreur.

## Identifiants

| Service | Accès |
|---------|--------------|
| AdGuard Home | `http://10.0.20.10:3001` — `admin` / `Ynov2026!` |
| HAProxy stats | `http://10.0.10.100:8404/stats` — `admin` / `Stats2026!` |
| PostgreSQL applicatif | `webapp` / `WebApp2026!ChangeMe` (base `webapp_db`, port 5432) |
| LXC root | mot de passe défini par `lxc_root_password` dans `terraform.tfvars` (+ clé SSH `proxmox_lab`) |

⚠️ Ces mots de passe par défaut sont définis dans des fichiers versionnés
(`defaults/main.yml`, `terraform.tfvars`). En dehors d'un lab, à changer et
à sortir du dépôt Git (Ansible Vault, variables d'environnement...).

## Idempotence — point d'attention

Le playbook DNS (`dns_bind9_auth`) régénère le fichier de zone
`db.infra.lan` avec un `serial` basé sur `ansible_date_time.epoch` : **le
template change donc à chaque exécution**, ce qui redéclenche
systématiquement le handler `restart bind9` même si rien n'a réellement
changé dans les enregistrements. C'est un comportement attendu (le serial
DNS doit changer à chaque modification de zone), pas un bug.

Le reste (PostgreSQL, web, LB) est idempotent normalement : `apt`,
`template`, modules `community.postgresql.*` ne remontent `changed` que s'il
y a une vraie différence.

## Destruction de la plateforme

```bash
cd terraform/
terraform destroy -auto-approve
```

## Troubleshooting

### `terraform apply` échoue avec une erreur d'authentification API

→ Vérifie le token (`proxmox_api_token_id` / `proxmox_api_token_secret`) et
que le rôle `Administrator` est bien attribué sur le path `/`.

### Un LXC ne répond pas en SSH juste après son apply

→ Normal, laisse le temps au cloud-init/boot de se terminer ; les playbooks
ont déjà un `wait_for_connection` (timeout 120s) en pré-tâche.

### `ansible-galaxy collection install community.postgresql` échoue silencieusement

→ C'est volontairement `failed_when: false` dans `playbook-db.yml` (pas de
blocage si le bastion n'a pas Internet et que la collection est déjà
installée). Si `postgresql_user`/`postgresql_db` échouent ensuite avec une
erreur de module introuvable, installe la collection manuellement (cf.
Pré-requis).

### `lb_haproxy` échoue sur le module `sysctl`

→ Installe la collection `ansible.posix` (jamais installée automatiquement,
voir Pré-requis). Le `failed_when: false` sur `ip_nonlocal_bind` masque
seulement les LXC où le sysctl est interdit par le noyau hôte, pas
l'absence de la collection elle-même.

### `dig @10.0.20.11 google.com` répond autre chose que vide

→ Vérifie `recursion no` / `allow-recursion { none; }` dans
`named.conf.options` côté `dns-auth-01` (généré depuis
`named.conf.options.j2`) : BIND9 doit rester strictement autoritaire.

### La VIP `10.0.10.100` ne bascule jamais entre `lb-01` et `lb-02`

→ Vérifie que `keepalived_auth_password` est identique sur les deux noeuds,
que `virtual_router_id` (51) ne rentre pas en conflit avec un autre VRRP du
réseau, et que `net.ipv4.ip_nonlocal_bind` est bien actif (sinon HAProxy ne
peut pas écouter sur une IP qu'il ne possède pas encore).

### `psql` distant refuse la connexion

→ Vérifie le sous-réseau source dans `postgres_allowed_subnets` /
`pg_hba.conf` : seuls `10.0.40.0/24` (web), `10.0.60.0/24` (monitoring) et
`192.168.3.0/24` (admin) sont autorisés par défaut.

