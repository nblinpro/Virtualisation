# Stack de monitoring all-in-one

Deploiement automatise de Prometheus + Grafana + Loki + Promtail
pour le projet M1 Virtualisation Ynov.

## Architecture

```
monitoring-01 (LXC, VLAN 60 - 10.0.60.10) :
  - Prometheus  : :9090 (metriques)
  - Grafana     : :3000 (dashboards)
  - Loki        : :3100 (logs)
  - Promtail    : :9080 (collecteur local de logs)

Sur tous les LXC applicatifs :
  - node_exporter : :9100 (metriques systeme)
  - Promtail      : :9080 (envoi logs vers Loki)

Sur les 3 hyperviseurs Proxmox :
  - pve-exporter  : :9221 (metriques Proxmox)
```

## Pre-requis

- Cluster Proxmox VE 9 fonctionnel avec Ceph
- OPNsense avec VLAN 60 configure (10.0.60.0/24)
- Acces SSH root sur tous les noeuds via cle ~/.ssh/proxmox_lab
- deploy-bastion avec Terraform + Ansible installes

## Deploiement

### 1. Terraform : creer le LXC monitoring-01

```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
# Editer terraform.tfvars avec le token API

terraform init
terraform apply
```

### 2. Ansible : configurer tous les composants

```bash
cd ../ansible/
ansible-playbook -i inventories/hosts.ini playbooks/deploy-monitoring.yml
```

## Acces aux interfaces

| Service      | URL                              | Auth                        |
|--------------|----------------------------------|-----------------------------|
| Prometheus   | http://10.0.60.10:9090           | (aucune)                    |
| Grafana      | http://10.0.60.10:3000           | admin / Ynov2026!           |
| Loki         | http://10.0.60.10:3100/ready     | (aucune)                    |

## Verification du fonctionnement

```bash
# Cibles Prometheus
curl -s http://10.0.60.10:9090/api/v1/targets | python3 -m json.tool

# Pousser un log de test via Loki
curl -X POST -H "Content-Type: application/json" \
  -d '{"streams":[{"stream":{"job":"test"},"values":[["'$(date +%s)'000000000","Test log"]]}]}' \
  http://10.0.60.10:3100/loki/api/v1/push

# Recuperer les logs
curl "http://10.0.60.10:3100/loki/api/v1/query_range?query={job=\"test\"}"
```

## Retentions configurees

- Prometheus : 7 jours, 1.5 GB max
- Loki      : 72 heures (3 jours)
- Grafana   : SQLite local (~50 MB)

## Personnalisation

Les variables sont dans `ansible/roles/*/defaults/main.yml` et peuvent
etre surchargees dans `ansible/inventories/hosts.ini` (group_vars).
