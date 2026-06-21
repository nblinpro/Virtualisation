# 📸 Checklist Captures - Rapport Final M1 Virtualisation

> Document de travail interne pour préparer les captures d'écran du rapport final et de la soutenance.
> **Cocher au fur et à mesure**. Total : ~30 captures critiques + bonus.

---

## 🎯 Méthode de capture professionnelle

### Avant chaque session de captures

- [ ] Mode plein écran navigateur (**F11** sur Chrome/Edge)
- [ ] Zoom 100% (**Ctrl+0**)
- [ ] Désactiver les bookmarks visibles
- [ ] Thème **clair** (les screenshots sombres sont moins lisibles à l'impression)
- [ ] Fermer les notifications/popups parasites
- [ ] Mode **incognito** pour éviter les extensions visibles

### Outils recommandés

- **Windows natif** : `Win + Shift + S` (capture rectangulaire rapide)
- **Greenshot** (gratuit) : annotations flèches + encadrés rouges
- **ShareX** (gratuit) : capture + édition + upload auto
- **Format** : PNG (lossless, fond transparent possible)
- **Résolution** : laisser native (pas de compression)

### Convention de nommage

```
fig-XX-nom-explicite.png

Exemples :
fig-01-proxmox-cluster-overview.png
fig-02-opnsense-vlans-list.png
fig-03-netbox-login-teacher-ldap.png
```

→ Le préfixe numérique permet de garder l'ordre logique dans ton dossier `captures/`.

---

## 📂 Organisation recommandée des dossiers

```
captures/
├── 01-architecture/          # Vue d'ensemble Proxmox + cluster
├── 02-network/               # OPNsense, VLANs, firewall
├── 03-services/              # NetBox, GLPI, NAS, etc.
├── 04-ha-loadbalancing/      # HAProxy, Keepalived
├── 05-monitoring/            # Prometheus, Grafana, Loki
├── 06-backup/                # PBS
├── 07-security/              # LDAP, PKI, HTTPS
├── 08-iac/                   # Terraform, Ansible
└── 09-bonus/                 # Failover, tests, démos
```

---

## 🔥 Section 1 — Architecture & Cluster Proxmox

### Captures critiques

- [ ] **fig-01** : Datacenter Proxmox vue d'ensemble
  - URL : `https://192.168.3.21:8006`
  - Vue : Datacenter (racine) → onglet **Summary**
  - Doit montrer : 3 nœuds verts (pve-01/02/03), ressources globales (vCPU/RAM/Stockage)
  - 💡 Capturer aussi l'onglet **Cluster** qui montre le quorum

- [ ] **fig-02** : Liste complète des CTs/VMs
  - Vue : Datacenter → **Search**
  - Filtrer Type = `lxc` puis `qemu`
  - Doit montrer : tous tes CTs (~14) + VMs (OPNsense + PBS) avec leur statut

- [ ] **fig-03** : Détail d'un nœud (pve-01)
  - Datacenter → pve-01 → onglet **Summary**
  - Montre : CPU/RAM/Disque utilisation en temps réel + graphiques

- [ ] **fig-04** : Stockage Ceph
  - Datacenter → Ceph → **Status**
  - Doit montrer : `HEALTH_OK`, 3 OSDs up/in, pool `ceph_vm`

- [ ] **fig-05** : Réseau Proxmox (bridges + VLAN)
  - pve-01 → System → **Network**
  - Doit montrer : vmbr0 (WAN), vmbr1 (ADMIN), vmbr3 (Trunk VLAN), interfaces VLAN

### Captures bonus

- [ ] **fig-06** : Cluster Corosync membres
  - Datacenter → onglet **Cluster**
  - Montre les liens Corosync entre les 3 nœuds

- [ ] **fig-07** : Pool Ceph utilisation
  - Datacenter → Ceph → **Pools**
  - Montre `ceph_vm` avec % utilisé

---

## 🔥 Section 2 — Réseau OPNsense & VLANs

### Captures critiques

- [ ] **fig-08** : Dashboard OPNsense
  - URL : `https://192.168.3.250`
  - Vue : Lobby → **Dashboard**
  - Montre : Interfaces, trafic temps réel

- [ ] **fig-09** : Liste des Interfaces (les 7 VLANs)
  - Interfaces → **Assignments** OU **Overview**
  - Doit montrer : WAN, LAN_ADMIN, DMZ, CORE, LAN_USERS, BACKEND_WEB, BACKEND_DB, MONITORING, BACKUP

- [ ] **fig-10** : Configuration d'un VLAN (ex: CORE)
  - Interfaces → **[CORE]**
  - Montre : tag VLAN 20, IP gateway 10.0.20.1/24, parent vmbr3

- [ ] **fig-11** : Règles firewall WAN (NAT inbound)
  - Firewall → NAT → **Port Forward**
  - Montre toutes tes règles NAT (HTTPS, NetBox, GLPI, Grafana, PBS...)

- [ ] **fig-12** : Règles firewall d'un VLAN interne (ex: CORE)
  - Firewall → Rules → **CORE**
  - Montre les 6 règles types : OPNsense, ping gw, DNS, métier, internet, block inter-vlan

- [ ] **fig-13** : Alias firewall (DNS_SERVERS, LDAP_SERVERS...)
  - Firewall → **Aliases**
  - Montre les groupes que tu as définis pour les règles

### Captures bonus

- [ ] **fig-14** : Logs firewall live
  - Firewall → Log Files → **Live View**
  - Filtrer par interface, montrer le trafic en temps réel

- [ ] **fig-15** : DHCP Kea (leases)
  - Services → DHCPv4 (Kea) → **Leases**

---

## 🔥 Section 3 — Services applicatifs

### NetBox (IPAM)

- [ ] **fig-16** : NetBox - Login en `teacher` (LDAP)
  - URL : `http://192.168.80.141:8095`
  - **IMPORTANT** : capturer l'écran de login + après connexion → indique en bas "Authentication backend: LDAPBackend"

- [ ] **fig-17** : NetBox - Vue IPAM des préfixes
  - IPAM → **Prefixes**
  - Montre les 7 subnets 10.0.X.0/24 documentés

- [ ] **fig-18** : NetBox - Devices déclarés
  - Devices → **Devices**
  - Liste de tous tes services renseignés

### GLPI (ITSM)

- [ ] **fig-19** : GLPI - Login en `teacher` (LDAP)
  - URL : `http://192.168.80.141:8080`
  - Login : teacher / Ynov2026!
  - Source : "Annuaire LDAP" (visible dans le dropdown)

- [ ] **fig-20** : GLPI - Configuration LDAP
  - Setup → Authentification → **Annuaires LDAP**
  - Montre la config (URL, base DN, filtres)

### NAS Samba

- [ ] **fig-21** : Explorateur Windows accédant au NAS
  - `\\192.168.80.141\public` ou `\\10.0.99.10\public`
  - Montrer les partages visibles

### AdGuard

- [ ] **fig-22** : AdGuard Dashboard
  - URL : `http://192.168.80.141:3001`
  - Page d'accueil avec stats (requêtes DNS traitées, bloquées)

---

## 🔥 Section 4 — Haute disponibilité (HAProxy + Keepalived)

### Captures critiques

- [ ] **fig-23** : HAProxy stats (3 backends UP)
  - URL : `http://192.168.80.141:8404/stats`
  - Login : admin / Stats2026!
  - **CAPTURER en mode étendu (?stats refresh=5;up)** pour voir tous les détails
  - Doit montrer : 3/3 web servers UP, queue 0, healthy

- [ ] **fig-24** : Détail backend HAProxy
  - Sur la même page, capturer la section `backend web_backend`
  - Montre les 3 serveurs web-01/02/03 verts

### Captures bonus (test failover)

- [ ] **fig-25** : Keepalived MASTER (avant test)
  ```bash
  ssh -i ~/.ssh/proxmox_lab root@10.0.10.11 "ip a | grep 10.0.10.100"
  ```
  - Capturer la sortie : la VIP 10.0.10.100 est sur lb-01

- [ ] **fig-26** : Simulation de panne lb-01
  ```bash
  ssh -i ~/.ssh/proxmox_lab root@10.0.10.11 "systemctl stop keepalived"
  # Sur lb-02 :
  ssh -i ~/.ssh/proxmox_lab root@10.0.10.12 "ip a | grep 10.0.10.100"
  ```
  - La VIP a basculé sur lb-02 !

- [ ] **fig-27** : Restauration
  ```bash
  ssh -i ~/.ssh/proxmox_lab root@10.0.10.11 "systemctl start keepalived"
  ssh -i ~/.ssh/proxmox_lab root@10.0.10.11 "ip a | grep 10.0.10.100"
  ```
  - La VIP est revenue sur lb-01

→ **Test failover = très valorisant pour la soutenance** !

---

## 🔥 Section 5 — Supervision

### Captures critiques

- [ ] **fig-28** : Prometheus - Targets (tous UP)
  - URL : `http://192.168.80.141:9090`
  - Status → **Targets**
  - Doit montrer : tous les exporters (node, pve, haproxy) en `UP`

- [ ] **fig-29** : Grafana - Dashboard Node Exporter
  - URL : `http://192.168.80.141:3000`
  - Login : admin / Ynov2026!
  - Dashboard "Node Exporter Full" (ou équivalent)
  - Sélectionner un host (ex: pve-01) → CPU/RAM/Disque visibles

- [ ] **fig-30** : Grafana - Dashboard cluster Proxmox
  - Si tu as un dashboard PVE Exporter
  - Sinon : Node Exporter avec sélection pve-01/02/03

- [ ] **fig-31** : Loki / Grafana Explore - Logs en live
  - Grafana → Explore → datasource **Loki**
  - Requête : `{host="lb-01"}` ou `{job="syslog"}`
  - Montre les logs centralisés

### Captures bonus

- [ ] **fig-32** : Grafana - Liste des datasources
  - Configuration → Data sources
  - Montre Prometheus + Loki configurés

---

## 🔥 Section 6 — Backup (PBS)

### Captures critiques

- [ ] **fig-33** : PBS - Dashboard
  - URL : `https://192.168.80.141:8007`
  - Login : root@pam / Ynov2026!
  - Vue d'accueil avec stats du datastore

- [ ] **fig-34** : PBS - Datastore avec snapshots
  - Datastore → ton datastore → **Snapshots**
  - Montre les backups disponibles (au moins 1 ou 2)

- [ ] **fig-35** : Proxmox - Backup configuré
  - Datacenter → Backup
  - Montre la configuration du job de backup (storage = pbs, schedule, retention)

### Captures bonus (test de restauration)

- [ ] **fig-36** : Test restauration en cours
  - Datacenter → CT (ex: 201) → Backup → sélectionner snapshot → **Restore**
  - Capturer la fenêtre de progression

- [ ] **fig-37** : Service restauré fonctionnel
  - Après restauration : capture browser sur l'AdGuard restauré (http://10.0.20.10:3001)

---

## 🔥 Section 7 — Sécurité (LDAP, PKI, HTTPS)

### Captures critiques

- [ ] **fig-38** : OpenLDAP - Recherche `ldapsearch`
  ```bash
  ssh -i ~/.ssh/proxmox_lab root@10.0.10.50 \
    "ldapsearch -x -H ldap://10.0.20.40 -b 'ou=people,dc=infra,dc=lan' '(objectClass=inetOrgPerson)' uid cn mail"
  ```
  - Capturer la sortie terminal : les 3 users (admin, teacher, student) listés

- [ ] **fig-39** : Cert HTTPS - Browser avec cadenas vert
  - Naviguer vers `https://web.infra.lan` (après config /etc/hosts ou DNS)
  - Cliquer sur le cadenas → **Certificat**
  - Capturer la fenêtre montrant la chaîne : Root CA Ynov → cert serveur
  - **Très valorisant**

- [ ] **fig-40** : OpenSSL - Détails du certificat
  ```bash
  ssh -i ~/.ssh/proxmox_lab root@10.0.10.11 \
    "openssl x509 -in /etc/haproxy/certs/web.crt -noout -text | head -30"
  ```
  - Capturer : Subject, Issuer (step-ca), Validity, SAN

- [ ] **fig-41** : step-ca - Health endpoint
  ```bash
  curl -k https://10.0.10.11:8443/health
  ```
  - Retourne `{"status":"ok"}`

### Captures bonus

- [ ] **fig-42** : NetBox Admin - Config LDAP active
  - Admin → Users → en bas, info sur le backend LDAP

- [ ] **fig-43** : GLPI Setup - LDAP
  - Setup → Authentification → Annuaires LDAP → ton serveur

---

## 🔥 Section 8 — Infrastructure as Code

### Captures critiques

- [ ] **fig-44** : Terraform apply réussi
  ```bash
  cd ~/Virtualisation/<un-stack>/terraform
  terraform plan
  ```
  - Capturer la sortie complète avec `Plan: X to add, 0 to change, 0 to destroy`
  - OU capturer un `terraform apply` complet qui passe

- [ ] **fig-45** : Ansible playbook complet sans erreur
  ```bash
  ansible-playbook -i inventory.ini playbook-XX.yml
  ```
  - Capturer le **PLAY RECAP** final : `ok=XX changed=YY unreachable=0 failed=0`
  - Surligner `failed=0`

- [ ] **fig-46** : Structure du repo Git
  ```bash
  cd ~/Virtualisation/
  tree -L 2 -d
  ```
  - Capturer l'arborescence : les 10 stacks visibles

- [ ] **fig-47** : Un fichier Ansible exemple
  - Ouvrir un `roles/xxx/tasks/main.yml` représentatif
  - Capturer une vingtaine de lignes montrant la qualité du code

### Captures bonus

- [ ] **fig-48** : Idempotence (re-run Ansible)
  - Relancer un playbook déjà passé
  - Doit montrer : `changed=0` → preuve d'idempotence
  - **TRÈS valorisant pour la soutenance**

- [ ] **fig-49** : Git log
  ```bash
  git log --oneline | head -20
  ```
  - Montre l'historique des commits → tracabilité

---

## 🎯 Section 9 - Démos en vidéo (optionnel mais impact++)

Si tu peux capturer **3-5 courtes vidéos** (30s à 2 min chacune), c'est ultra impactant :

- [ ] **vid-01** : Déploiement complet d'un service from-scratch
  - `terraform apply` → `ansible-playbook` → service fonctionnel
  - Durée : ~3 min en accéléré

- [ ] **vid-02** : Failover Keepalived en direct
  - Stop lb-01 → la VIP bascule sur lb-02 → site web toujours accessible
  - Durée : ~1 min

- [ ] **vid-03** : Restauration PBS
  - Suppression CT → Restauration depuis PBS → service à nouveau OK
  - Durée : ~3 min

- [ ] **vid-04** : SSO LDAP
  - Login `teacher` dans NetBox → puis même login dans GLPI sans re-saisir
  - Durée : ~30s

- [ ] **vid-05** : Monitoring temps réel
  - Stress test sur un CT → Grafana affiche le pic CPU → résolution
  - Durée : ~1 min

→ Outil : **OBS Studio** (gratuit) ou **ShareX** pour capture vidéo.

---

## 📋 Récap final

### Captures absolument essentielles (le minimum vital)

```
fig-01  Proxmox cluster overview
fig-02  Liste CTs/VMs
fig-08  OPNsense dashboard
fig-09  Liste des 7 VLANs
fig-11  NAT inbound WAN
fig-16  NetBox connecté en teacher (LDAP)
fig-19  GLPI connecté en teacher (LDAP)
fig-23  HAProxy stats 3/3 UP
fig-28  Prometheus targets UP
fig-29  Grafana Node Exporter
fig-33  PBS datastore
fig-39  HTTPS cadenas vert browser
fig-44  Terraform apply OK
fig-45  Ansible PLAY RECAP failed=0
```

→ **14 captures minimum** = ton rapport est déjà solide.

### Toutes les captures recommandées : ~30
### Avec bonus + vidéos : ~50

---

## 🎓 Tip soutenance — Tableau récap pour l'exposé

Tu peux inclure cette diapositive en intro de ta présentation :

| Domaine | Compétences démontrées | Captures |
|---------|------------------------|----------|
| Virtualisation | Cluster Proxmox + Ceph distribué | fig-01 à 07 |
| Réseau | 7 VLANs + firewall + NAT | fig-08 à 15 |
| HA | HAProxy + Keepalived + failover | fig-23 à 27 |
| Sécurité | LDAP SSO + PKI step-ca + HTTPS | fig-38 à 43 |
| Supervision | Prometheus + Grafana + Loki | fig-28 à 32 |
| Backup | PBS + test de DR | fig-33 à 37 |
| IaC | Terraform + Ansible idempotent | fig-44 à 49 |

---

## ⚡ Action rapide

1. **Cocher** au fur et à mesure que tu fais les captures
2. **Annoter** chaque capture (Greenshot) avec flèches/encadrés rouges sur les zones clés
3. **Renommer** correctement (fig-XX-description.png)
4. **Trier** dans les dossiers thématiques
5. **Compresser** les images si > 500 KB (TinyPNG)
6. **Insérer** dans ton rapport avec une légende numérotée :
   ```
   *Figure 12 - Règles firewall OPNsense sur le VLAN CORE : les 6 règles
   appliquent le principe du moindre privilège.*
   ```

🚀 **Bonne capture !** Une fois fait, tu auras de quoi faire un rapport ultra solide.
