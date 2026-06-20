# Stack HTTPS - step-ca + HAProxy (v1.2)

PKI interne avec step-ca + HTTPS sur le cluster web HA.

## v1.2 - Reproductible from scratch

Tous les bugs des versions precedentes corriges et integres :

1. ✅ Versions step-ca/cli 0.29.0 (format `-1_amd64.deb`)
2. ✅ `ansible_facts.architecture` (au lieu de deprecated)
3. ✅ Adresse `:8443` (toutes interfaces)
4. ✅ Claims TLS 2160h (90 jours)
5. ✅ Boucle Jinja pour les SAN
6. ✅ `--ca-url` avec IP reelle de lb-01
7. ✅ **Service systemd step-ca cree correctement**
8. ✅ **flush_handlers pour appliquer le restart avant verifications**
9. ✅ **Verification des claims actifs en fin de stepca_init**
10. ✅ **Pre-check step-ca dans haproxy_https avant generation du cert**

## Architecture

```
[lb-01 (10.0.10.11)]                      [lb-02 (10.0.10.12)]
├── step-ca PKI (port 8443)                ├── HAProxy + cert (BACKUP)
└── HAProxy + cert HTTPS:443               └── Recoit cert via Ansible
        ↑                                          ↑
        └────── VIP Keepalived 10.0.10.100 ────────┘
                            │
                            ↓ Backend HTTP:80
                      [web-01/02/03]
```

## Procedure de deploiement

### Pre-requis

CT lb-01 et lb-02 deployes avec HAProxy + Keepalived. Pour tester from scratch :

```bash
# Nettoyer lb-01
ssh -i ~/.ssh/proxmox_lab root@10.0.10.11 << 'EOF'
systemctl stop step-ca 2>/dev/null
systemctl disable step-ca 2>/dev/null
rm -rf /root/.step
rm -f /etc/systemd/system/step-ca.service
rm -rf /etc/haproxy/certs
apt remove -y step-cli step-ca 2>/dev/null
systemctl daemon-reload
EOF

# Nettoyer lb-02
ssh -i ~/.ssh/proxmox_lab root@10.0.10.12 \
  "rm -rf /etc/haproxy/certs"
```

### Phase 1 - step-ca sur lb-01

```bash
cd ~/Virtualisation/
tar -xzf https-stack.tar.gz
cd https-stack/ansible/

ansible-playbook -i inventory.ini playbook-stepca.yml
```

⏱ ~5 min.

A la fin tu dois voir :
```
TASK [stepca_init : Resume step-ca init]
ok: [lb-01] => {
  "msg": [
    "step-ca initialise avec succes !",
    "Max TLS dur : 2160h (claims actifs)",
    "Health      : HTTP 200"
  ]
}
```

⚠️ Si `Max TLS dur` n'est pas 2160h, le playbook s'arrete (failed_when).

### Phase 2 - HAProxy HTTPS

```bash
ansible-playbook -i inventory.ini playbook-haproxy-https.yml
```

⏱ ~3 min.

## Verifications manuelles

```bash
# 1. step-ca repond
ssh -i ~/.ssh/proxmox_lab root@10.0.10.11 "curl -sk https://10.0.10.11:8443/health"

# 2. Voir le cert
ssh -i ~/.ssh/proxmox_lab root@10.0.10.11 \
  "openssl x509 -in /etc/haproxy/certs/web.crt -text -noout | grep -E 'Not After|Subject Alternative' -A 5"

# 3. Test HTTPS local
ssh -i ~/.ssh/proxmox_lab root@10.0.10.11 \
  "curl -sI --cacert /etc/haproxy/certs/root_ca.crt https://127.0.0.1 | head -3"

# 4. Test HTTPS via VIP
ssh -i ~/.ssh/proxmox_lab root@10.0.10.11 \
  "curl -sI --cacert /etc/haproxy/certs/root_ca.crt https://10.0.10.100 | head -3"
```

## Installer le root CA sur Windows

### Recuperer + deposer sur le NAS

```bash
scp -i ~/.ssh/proxmox_lab root@10.0.10.11:/root/.step/certs/root_ca.crt /tmp/ynov-root-ca.crt
scp -i ~/.ssh/proxmox_lab /tmp/ynov-root-ca.crt root@10.0.99.10:/srv/shares/public/
```

### Sur Windows

1. Explorateur : `\\192.168.80.141\public\ynov-root-ca.crt`
2. Double-clic > **Installer un certificat** > Magasin utilisateur
3. **Placer** > Parcourir > **Autorites de certification racines de confiance**
4. Suivant > Terminer > Oui

### hosts Windows (pour web.infra.lan)

`C:\Windows\System32\drivers\etc\hosts` (en admin) :
```
192.168.80.141    web.infra.lan
```

### Tester

Chrome/Edge : `https://web.infra.lan` → cadenas vert sans warning !

## Mots de passe

| Element | Valeur |
|---------|--------|
| step-ca | `StepCa2026YnovChangeMe!` |
| HAProxy stats | `admin` / `Stats2026!` |

## Structure

```
https-stack/
├── README.md
└── ansible/
    ├── inventory.ini
    ├── playbook-stepca.yml
    ├── playbook-haproxy-https.yml
    └── roles/
        ├── stepca_install/
        │   ├── defaults/main.yml
        │   └── tasks/main.yml
        ├── stepca_init/
        │   ├── defaults/main.yml
        │   ├── handlers/main.yml
        │   ├── files/
        │   │   └── configure_claims.py
        │   └── tasks/main.yml
        └── haproxy_https/
            ├── defaults/main.yml
            ├── handlers/main.yml
            ├── tasks/main.yml
            └── templates/
                └── haproxy.cfg.j2
```

## Pour le rapport

> "**PKI interne reproductible** : Une CA interne (`step-ca` v0.29.0) est deployee de
> facon idempotente via Ansible. Le rôle integre la creation du service systemd,
> la configuration des claims TLS (90 jours au lieu des 24h par defaut), et un
> mecanisme de verification post-deploiement qui valide que les claims sont bien
> charges en memoire avant de declarer le deploiement reussi. La sequence est
> robuste meme en cas de re-execution (idempotence via `creates` et tests
> conditionnels). Le cert serveur est ensuite distribue automatiquement entre les
> deux load balancers, garantissant la haute disponibilite TLS."
