# GLPI - Gestion de parc IT et helpdesk

Deploiement automatise de GLPI 10 pour le projet M1 Virtualisation Ynov.

## Architecture

```
glpi-01 (LXC, VLAN 20 - 10.0.20.50) :
  - Apache 2.4
  - PHP 8.3
  - MariaDB 11
  - GLPI 10.0.18
```

## Ressources

- CPU : 1 vCPU
- RAM : 512 MB + 512 MB swap
- Disque : 3 GB sur ceph_vm

## Deploiement

### 1. Terraform : creer le LXC

```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
# Editer terraform.tfvars (token API)

terraform init
terraform apply
```

### 2. Ansible : installer GLPI

```bash
cd ../ansible/
ansible-playbook -i inventories/hosts.ini playbooks/deploy-glpi.yml
```

## Acces

| Acces       | Valeur                          |
|-------------|---------------------------------|
| URL         | http://10.0.20.50               |
| Login       | glpi / glpi                     |
|             | tech / tech                     |
|             | normal / normal                 |
|             | post-only / postonly            |
| BDD root    | root / Ynov2026!Root            |
| BDD glpi    | glpi / Ynov2026!GlpiDB          |

## Premiere connexion

⚠️ **Changer immediatement les mots de passe par defaut** :

1. Se connecter avec glpi/glpi
2. Menu utilisateur (en haut a droite) → "Mes preferences"
3. Changer le mot de passe

GLPI cree 4 comptes par defaut :
- glpi / glpi (super-admin)
- tech / tech (technicien)
- normal / normal (utilisateur normal)
- post-only / postonly (utilisateur post-only)

## NAT pour acces depuis Windows

Dans OPNsense, ajouter une regle NAT inbound :
- Source : any
- Destination : WAN address port 8080 (par exemple)
- Redirect to : 10.0.20.50 port 80

Acces : http://192.168.80.141:8080
