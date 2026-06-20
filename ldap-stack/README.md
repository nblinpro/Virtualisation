# Stack OpenLDAP + integration NetBox

Deploiement automatise d'un service d'authentification centralisee.

## Architecture

```
[ldap-01]                    [netbox-01]
10.0.20.40                   10.0.20.30
slapd:389                    NetBox + django-auth-ldap
  └── dc=infra,dc=lan          └── REMOTE_AUTH_ENABLED=True
      ├── ou=people                  └── LDAPBackend
      │   ├── uid=admin
      │   ├── uid=teacher
      │   └── uid=student
      └── ou=groups
          ├── cn=admins
          ├── cn=teachers
          └── cn=students
```

## Specifications

| Parametre | Valeur |
|-----------|--------|
| VMID | 800 |
| Hostname | ldap-01 |
| Hote | pve-03 |
| vCPU | 1 |
| RAM | 256 MB |
| Disque | 2 GB sur ceph_vm |
| IP | 10.0.20.40/24 |
| VLAN | 20 (CORE) |

## Identifiants

| User LDAP | Password | Groupe |
|-----------|----------|--------|
| `admin`   | `Ynov2026!` | admins |
| `teacher` | `Ynov2026!` | teachers |
| `student` | `Ynov2026!` | students |

**Admin LDAP (bind technique)** : `cn=admin,dc=infra,dc=lan` / `LdapAdmin2026!`

## Procedure de deploiement (3 phases)

### Phase 1 - Provisionner ldap-01

```bash
cd ~/Virtualisation/
tar -xzf ldap-stack.tar.gz
cd ldap-stack/terraform/

cp ~/Virtualisation/netbox-stack/terraform/terraform.tfvars .
cp -r ~/Virtualisation/netbox-stack/terraform/.terraform .
cp ~/Virtualisation/netbox-stack/terraform/.terraform.lock.hcl .

terraform init
terraform apply -auto-approve
```

⏱ ~1 minute.

### Phase 2 - Echange SSH

```bash
ssh-keygen -f ~/.ssh/known_hosts -R 10.0.20.40 2>/dev/null
ssh -i ~/.ssh/proxmox_lab -o StrictHostKeyChecking=no root@10.0.20.40 "hostname"
```

### Phase 3 - Installer OpenLDAP

```bash
cd ../ansible/
ansible-playbook -i inventory.ini playbook-ldap.yml
```

⏱ ~3 minutes.

A la fin, tu vois les 4 tests valides :
- Anonymous bind OK
- Admin bind OK
- User bind OK
- List users OK

### Phase 4 - Integrer NetBox <-> LDAP

```bash
ansible-playbook -i inventory.ini playbook-netbox-ldap.yml
```

⏱ ~3 minutes.

## Tests manuels post-deploiement

### Sur ldap-01

```bash
# Tester un bind utilisateur
ssh root@10.0.20.40
ldapwhoami -x -H ldap://localhost -D "uid=teacher,ou=people,dc=infra,dc=lan" -w "Ynov2026!"
# → renvoie : dn:uid=teacher,ou=people,dc=infra,dc=lan

# Lister tous les utilisateurs
ldapsearch -x -H ldap://localhost -b "ou=people,dc=infra,dc=lan" \
  -D "cn=admin,dc=infra,dc=lan" -w "LdapAdmin2026!" "(objectClass=inetOrgPerson)" uid cn mail

# Lister les groupes
ldapsearch -x -H ldap://localhost -b "ou=groups,dc=infra,dc=lan" \
  -D "cn=admin,dc=infra,dc=lan" -w "LdapAdmin2026!"
```

### Depuis Windows (NetBox)

1. Ouvrir : http://192.168.80.141:8095
2. Se connecter avec :
   - User : `teacher`
   - Password : `Ynov2026!`
3. NetBox cree automatiquement le compte avec :
   - first_name = Teacher
   - last_name = Teacher
   - email = teacher@infra.lan

## Architecture LDAP

```
dc=infra,dc=lan                          (suffix racine)
│
├── cn=admin,dc=infra,dc=lan             (admin LDAP technique)
│
├── ou=people,dc=infra,dc=lan            (utilisateurs)
│   ├── uid=admin
│   ├── uid=teacher
│   └── uid=student
│
└── ou=groups,dc=infra,dc=lan            (groupes)
    ├── cn=admins (memberUid: admin)
    ├── cn=teachers (memberUid: teacher)
    └── cn=students (memberUid: student)
```

## Mode read-only (decision)

L'integration NetBox <-> LDAP est **read-only** :

- ✅ Les utilisateurs LDAP peuvent se connecter a NetBox
- ✅ Leurs informations (nom, email) sont synchronisees depuis LDAP
- ✅ Les droits NetBox sont geres dans NetBox (admin, staff, superuser)
- ❌ Pas de mapping de groupes LDAP -> NetBox (simplicite)

Pour ajouter le mapping de groupes plus tard, voir `AUTH_LDAP_GROUP_SEARCH` 
dans la documentation django-auth-ldap.

## Troubleshooting

### Connexion echoue dans NetBox

Logs Django :
```bash
ssh root@10.0.20.30
tail -f /var/log/netbox/*.log
# ou
journalctl -u netbox -f
```

### Tester connectivite NetBox -> LDAP

```bash
ssh root@10.0.20.30
# Test reseau
nc -zv 10.0.20.40 389
# Test ldap search
ldapsearch -x -H ldap://10.0.20.40 -b "dc=infra,dc=lan" -D "cn=admin,dc=infra,dc=lan" -w "LdapAdmin2026!"
```

### Recharger uniquement la config LDAP de NetBox

```bash
ssh root@10.0.20.30 "systemctl restart netbox netbox-rq"
```

## Acces direct via LDAP (sans NetBox)

### Browser LDAP graphique

- **Apache Directory Studio** (Windows/Linux/Mac)
- **JXplorer**

Connexion :
- Host : `10.0.20.40` (ou `192.168.80.141` via NAT)
- Port : `389`
- Bind DN : `cn=admin,dc=infra,dc=lan`
- Password : `LdapAdmin2026!`

### NAT inbound OPNsense (acces depuis Windows)

| Champ | Valeur |
|-------|--------|
| Interface | WAN |
| Protocol | TCP |
| Destination port | 389 |
| Redirect IP | 10.0.20.40 |
| Redirect port | 389 |

⚠️ LDAP en clair sur Internet = mauvaise pratique. Pour la prod, utiliser LDAPS (636) ou STARTTLS.

## Pour le rapport

Points valorisants :

- ✅ **Authentification centralisee** : un mot de passe pour plusieurs services
- ✅ **Annuaire RFC 2307** : structure standard (inetOrgPerson, posixAccount, posixGroup)
- ✅ **Integration NetBox** : exemple concret d'usage SSO basique
- ✅ **Read-only mode** : separation des responsabilites (LDAP = identite, NetBox = autorisations)
- ✅ **Tests automatises** : 4 tests valides a chaque deploiement
- ✅ **IaC complet** : Terraform + Ansible

## Structure du projet

```
ldap-stack/
├── README.md
├── terraform/
│   ├── main.tf
│   └── terraform.tfvars.example
└── ansible/
    ├── inventory.ini
    ├── playbook-ldap.yml
    ├── playbook-netbox-ldap.yml
    └── roles/
        ├── openldap/
        │   ├── defaults/main.yml         Users + groupes
        │   ├── handlers/main.yml
        │   ├── tasks/main.yml            Install + LDIF + 4 tests
        │   └── templates/
        │       └── structure.ldif.j2     Structure LDAP
        └── netbox_ldap/
            ├── tasks/main.yml            django-auth-ldap + config
            └── templates/
                └── ldap_config.py.j2     Config Django LDAP backend
```
