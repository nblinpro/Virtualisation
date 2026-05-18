# Projet Infrastructure as Code - dns-01

Déploiement automatisé de **dns-01** (résolveur DNS interne Unbound) via :
- **Terraform** : provisionnement du LXC sur Proxmox
- **Ansible** : installation et configuration d'Unbound

## Architecture cible

- **Container** : dns-01 (VMID 201)
- **Hyperviseur** : pve-02
- **Stockage** : ceph-vm
- **Réseau** : VLAN 20 (CORE)
- **IP** : 10.0.20.10/24
- **Gateway** : 10.0.20.1 (OPNsense)

## Prérequis

### Sur deploy-01 (bastion)

```bash
# Terraform
sudo apt update
sudo apt install -y wget gnupg software-properties-common
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update
sudo apt install -y terraform

# Ansible
sudo apt install -y ansible

# Verifier
terraform version
ansible --version
```

### Clé SSH

```bash
# Generer la cle SSH
ssh-keygen -t ed25519 -f ~/.ssh/proxmox_lab -N ""

# Copier la cle sur les 3 noeuds Proxmox
for ip in 192.168.3.21 192.168.3.22 192.168.3.23; do
    ssh-copy-id -i ~/.ssh/proxmox_lab.pub root@$ip
done
```

### Token API Proxmox

Sur l'interface web Proxmox :

1. **Datacenter → Permissions → API Tokens → Add**
   - User : `root@pam`
   - Token ID : `terraform-token`
   - ☐ Privilege Separation (decoche pour heriter des droits root)
   - Note bien le secret affiche !

2. **Datacenter → Permissions → Add → API Token Permission**
   - Path : `/`
   - API Token : `root@pam!terraform-token`
   - Role : `Administrator`

## Déploiement

### Étape 1 : Configuration

```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
# Adapter : proxmox_api_token_secret, lxc_root_password
```

### Étape 2 : Provisionnement Terraform

```bash
terraform init
terraform plan
terraform apply
```

Cela va :
1. Creer le LXC 201 sur pve-02
2. L'attacher au VLAN 20 (BACKEND_WEB)
3. Configurer l'IP 10.0.20.10
4. Generer l'inventaire Ansible (../ansible/inventory.ini)

### Étape 3 : Configuration Ansible

```bash
cd ../ansible/
ansible-playbook playbook-dns.yml
```

Cela va :
1. Installer Unbound + dnsutils
2. Télécharger les root hints
3. Déployer la configuration `/etc/unbound/unbound.conf.d/infra-lan.conf`
4. Désactiver systemd-resolved
5. Démarrer et activer Unbound
6. Tester une résolution interne et externe

## Vérification

```bash
# Depuis deploy-01
dig @10.0.20.10 pve-01.infra.lan
# Doit retourner : 192.168.3.21

dig @10.0.20.10 google.com
# Doit retourner une IP publique

dig @10.0.20.10 -x 192.168.3.250
# Doit retourner : fw-01.infra.lan
```

## Hostnames résolus

| Nom DNS | IP |
|---------|-----|
| pve-01.infra.lan | 192.168.3.21 |
| pve-02.infra.lan | 192.168.3.22 |
| pve-03.infra.lan | 192.168.3.23 |
| fw-01.infra.lan | 192.168.3.250 |
| dns-01.infra.lan | 10.0.20.10 |
| web.infra.lan (VIP) | 10.0.40.10 |
| web-01/02/03.infra.lan | 10.0.40.11-13 |
| pgsql-01.infra.lan | 10.0.50.10 |
| prometheus/grafana/loki.infra.lan | 10.0.60.x |
| pbs-01.infra.lan | 10.0.99.10 |

## Destruction

```bash
cd terraform/
terraform destroy
```
