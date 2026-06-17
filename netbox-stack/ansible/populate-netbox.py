#!/usr/bin/env python3
"""
=============================================================================
Script de pre-remplissage NetBox - Infrastructure M1 Virtualisation Ynov
=============================================================================

Peuple NetBox avec :
- Site, Cluster Type, Cluster
- VLAN Groups + 7 VLANs
- 8 Prefixes IPv4
- Manufacturer + Device Type + Device Role
- 3 Devices (PVE)
- 13 Virtual Machines (tous les CTs/VMs)
- Adresses IP assignees aux interfaces
- Services (DNS, HTTP, HTTPS, PostgreSQL, etc.)

Usage :
    pip install pynetbox
    NETBOX_URL=http://10.0.20.30 NETBOX_TOKEN=xxx python3 populate-netbox.py

Pour obtenir un token NetBox :
    Connecte-toi a NetBox -> Admin (en haut a droite) -> API Tokens -> + Add
    Cocher "Write enabled" pour ce script
=============================================================================
"""

import os
import sys

try:
    import pynetbox
except ImportError:
    print("ERREUR : pynetbox manquant")
    print("Installe avec : pip install pynetbox")
    sys.exit(1)

# =============================================================================
# CONFIGURATION
# =============================================================================
NETBOX_URL = os.environ.get("NETBOX_URL", "http://10.0.20.30")
NETBOX_TOKEN = os.environ.get("NETBOX_TOKEN", "4d7b82a7b740ebac40ecc9dd6ebc9a050b276b34")

if not NETBOX_TOKEN:
    print("ERREUR : NETBOX_TOKEN manquant")
    print("Cree un token dans NetBox > Admin > API Tokens")
    print("Puis : NETBOX_TOKEN=xxx python3 populate-netbox.py")
    sys.exit(1)

nb = pynetbox.api(NETBOX_URL, token=NETBOX_TOKEN)
nb.http_session.verify = False  # Lab self-signed

# =============================================================================
# HELPERS
# =============================================================================
def get_or_create(endpoint, name_field='name', **kwargs):
    """Recupere ou cree un objet (idempotent)."""
    query = {name_field: kwargs.get(name_field)}
    existing = endpoint.get(**query)
    if existing:
        print(f"  [=] Existe deja : {kwargs.get(name_field)}")
        return existing
    obj = endpoint.create(**kwargs)
    print(f"  [+] Cree : {kwargs.get(name_field)}")
    return obj


def slugify(text):
    return text.lower().replace(' ', '-').replace('.', '-').replace('_', '-')


# =============================================================================
# 1. SITE
# =============================================================================
print("=" * 70)
print("1. Site")
print("=" * 70)

site = get_or_create(
    nb.dcim.sites,
    name="Ynov Lab",
    slug="ynov-lab",
    description="Datacenter prive M1 Virtualisation - VMware Workstation",
    status="active",
)

# =============================================================================
# 2. CLUSTER TYPE + CLUSTER
# =============================================================================
print("\n" + "=" * 70)
print("2. Cluster Proxmox VE")
print("=" * 70)

cluster_type = get_or_create(
    nb.virtualization.cluster_types,
    name="Proxmox VE",
    slug="proxmox-ve",
    description="Hyperviseur Proxmox VE 9 avec stockage Ceph",
)

cluster = get_or_create(
    nb.virtualization.clusters,
    name="ynov-lab",
    slug="ynov-lab",
    type=cluster_type.id,
    site=site.id,
    description="Cluster 3 nœuds + Ceph",
    status="active",
)

# =============================================================================
# 3. VLANS
# =============================================================================
print("\n" + "=" * 70)
print("3. VLANs")
print("=" * 70)

vlan_group = get_or_create(
    nb.ipam.vlan_groups,
    name="Ynov Lab",
    slug="ynov-lab",
    description="VLANs du datacenter Ynov",
    scope_type="dcim.site",
    scope_id=site.id,
)

VLANS = [
    {"vid": 10, "name": "DMZ", "description": "Zone demilitarisee - LB et bastion"},
    {"vid": 20, "name": "CORE", "description": "Services internes - DNS, GLPI, NetBox"},
    {"vid": 30, "name": "LAN_USERS", "description": "Postes administrateurs"},
    {"vid": 40, "name": "BACKEND_WEB", "description": "Serveurs web applicatifs"},
    {"vid": 50, "name": "BACKEND_DB", "description": "Bases de donnees"},
    {"vid": 60, "name": "MONITORING", "description": "Supervision out-of-band"},
    {"vid": 99, "name": "BACKUP", "description": "Sauvegardes et NAS"},
]

vlans = {}
for v in VLANS:
    vlan = get_or_create(
        nb.ipam.vlans,
        name=v["name"],
        vid=v["vid"],
        group=vlan_group.id,
        status="active",
        description=v["description"],
    )
    vlans[v["vid"]] = vlan

# =============================================================================
# 4. PREFIXES
# =============================================================================
print("\n" + "=" * 70)
print("4. Prefixes IPv4")
print("=" * 70)

PREFIXES = [
    {"prefix": "192.168.80.0/24", "description": "WAN VMware NAT", "vlan": None},
    {"prefix": "192.168.3.0/24",  "description": "LAN admin Proxmox", "vlan": None},
    {"prefix": "192.168.254.0/24","description": "Cluster Corosync + Ceph", "vlan": None},
    {"prefix": "10.0.10.0/24", "description": "VLAN 10 DMZ", "vlan": 10},
    {"prefix": "10.0.20.0/24", "description": "VLAN 20 CORE", "vlan": 20},
    {"prefix": "10.0.30.0/24", "description": "VLAN 30 LAN_USERS", "vlan": 30},
    {"prefix": "10.0.40.0/24", "description": "VLAN 40 BACKEND_WEB", "vlan": 40},
    {"prefix": "10.0.50.0/24", "description": "VLAN 50 BACKEND_DB", "vlan": 50},
    {"prefix": "10.0.60.0/24", "description": "VLAN 60 MONITORING", "vlan": 60},
    {"prefix": "10.0.99.0/24", "description": "VLAN 99 BACKUP", "vlan": 99},
]

for p in PREFIXES:
    existing = nb.ipam.prefixes.get(prefix=p["prefix"])
    if existing:
        print(f"  [=] Existe deja : {p['prefix']}")
        continue
    data = {
        "prefix": p["prefix"],
        "site": site.id,
        "status": "active",
        "description": p["description"],
    }
    if p["vlan"]:
        data["vlan"] = vlans[p["vlan"]].id
    nb.ipam.prefixes.create(**data)
    print(f"  [+] Cree : {p['prefix']}")

# =============================================================================
# 5. MANUFACTURER + DEVICE TYPE + DEVICE ROLE
# =============================================================================
print("\n" + "=" * 70)
print("5. Manufacturer + Device Type + Device Role")
print("=" * 70)

manufacturer = get_or_create(
    nb.dcim.manufacturers,
    name="Proxmox",
    slug="proxmox",
    description="Proxmox Server Solutions GmbH",
)

device_type = get_or_create(
    nb.dcim.device_types,
    model="PVE Node",
    slug="pve-node",
    manufacturer=manufacturer.id,
    u_height=1,
    description="Nœud Proxmox VE virtualise sur VMware",
)

device_role = get_or_create(
    nb.dcim.device_roles,
    name="Hypervisor",
    slug="hypervisor",
    color="2196f3",
    description="Hyperviseur Proxmox VE",
)

# =============================================================================
# 6. DEVICES (les 3 PVE)
# =============================================================================
print("\n" + "=" * 70)
print("6. Devices physiques (PVE)")
print("=" * 70)

DEVICES = [
    {"name": "pve-01", "ip": "192.168.3.21", "cluster_ip": "192.168.254.21"},
    {"name": "pve-02", "ip": "192.168.3.22", "cluster_ip": "192.168.254.22"},
    {"name": "pve-03", "ip": "192.168.3.23", "cluster_ip": "192.168.254.23"},
]

devices = {}
for d in DEVICES:
    device = get_or_create(
        nb.dcim.devices,
        name=d["name"],
        site=site.id,
        device_type=device_type.id,
        role=device_role.id,
        status="active",
    )
    devices[d["name"]] = device

    # Creer interface eth0 (LAN admin)
    iface = nb.dcim.interfaces.get(device_id=device.id, name="eth0")
    if not iface:
        iface = nb.dcim.interfaces.create(
            device=device.id,
            name="eth0",
            type="1000base-t",
            description="LAN admin",
        )
        print(f"    [+] Interface eth0 sur {d['name']}")

    # Assigner l'IP
    ip = nb.ipam.ip_addresses.get(address=f"{d['ip']}/24")
    if not ip:
        ip = nb.ipam.ip_addresses.create(
            address=f"{d['ip']}/24",
            assigned_object_type="dcim.interface",
            assigned_object_id=iface.id,
            description=f"IP management {d['name']}",
        )
        print(f"    [+] IP {d['ip']} assignee a {d['name']}.eth0")

    # Definir comme IP primaire
    if not device.primary_ip4 or device.primary_ip4.address != f"{d['ip']}/24":
        device.primary_ip4 = ip.id
        device.save()

# =============================================================================
# 7. VIRTUAL MACHINES
# =============================================================================
print("\n" + "=" * 70)
print("7. Virtual Machines (LXC + VMs)")
print("=" * 70)

VMS = [
    # nom, vcpu, ram(MB), disk(GB), ip, vlan_vid, role, comments
    ("fw-01",         2, 1024,  4, "192.168.3.250", None, "Firewall",    "OPNsense"),
    ("deploy-bastion",1, 256,   2, "10.0.10.50",    10,   "Management",  "Bastion Terraform + Ansible (Alpine)"),
    ("dns-rec-01",    1, 512,   1, "10.0.20.10",    20,   "DNS",         "AdGuard Home (recursif + filtrage)"),
    ("dns-auth-01",   1, 512,   1, "10.0.20.11",    20,   "DNS",         "BIND9 (autoritaire infra.lan)"),
    ("netbox-01",     2, 1024,  4, "10.0.20.30",    20,   "IPAM",        "NetBox 4.1"),
    ("glpi-01",       1, 512,   3, "10.0.20.50",    20,   "ITSM",        "GLPI 10 (helpdesk)"),
    ("web-01",        1, 512,   4, "10.0.40.11",    40,   "Web Backend", "Nginx + PHP-FPM"),
    ("web-02",        1, 512,   4, "10.0.40.12",    40,   "Web Backend", "Nginx + PHP-FPM"),
    ("web-03",        1, 512,   4, "10.0.40.13",    40,   "Web Backend", "Nginx + PHP-FPM"),
    ("lb-01",         1, 512,   4, "10.0.10.11",    10,   "Load Balancer","HAProxy + Keepalived MASTER"),
    ("lb-02",         1, 512,   4, "10.0.10.12",    10,   "Load Balancer","HAProxy + Keepalived BACKUP"),
    ("pgsql-01",      2, 1024,  8, "10.0.50.10",    50,   "Database",    "PostgreSQL 17"),
    ("monitoring-01", 2, 1536,  6, "10.0.60.10",    60,   "Monitoring",  "Prometheus + Grafana + Loki + Promtail"),
]

# Creer roles VM
ROLES_VM = ["Firewall", "Management", "DNS", "IPAM", "ITSM",
            "Web Backend", "Load Balancer", "Database", "Monitoring"]
roles = {}
for r in ROLES_VM:
    role = get_or_create(
        nb.dcim.device_roles,
        name=r,
        slug=slugify(r),
        vm_role=True,
        color="9c27b0",
    )
    roles[r] = role

# Creer VMs
for name, vcpu, ram, disk, ip, vlan_vid, role_name, comment in VMS:
    vm = nb.virtualization.virtual_machines.get(name=name)
    if not vm:
        vm = nb.virtualization.virtual_machines.create(
            name=name,
            cluster=cluster.id,
            site=site.id,
            role=roles[role_name].id,
            status="active",
            vcpus=vcpu,
            memory=ram,
            disk=disk,
            comments=comment,
        )
        print(f"  [+] VM cree : {name}")
    else:
        print(f"  [=] VM existe : {name}")

    # Interface eth0
    iface = nb.virtualization.interfaces.get(virtual_machine_id=vm.id, name="eth0")
    if not iface:
        iface_data = {
            "virtual_machine": vm.id,
            "name": "eth0",
            "enabled": True,
        }
        if vlan_vid:
            iface_data["mode"] = "access"
            iface_data["untagged_vlan"] = vlans[vlan_vid].id
        iface = nb.virtualization.interfaces.create(**iface_data)
        print(f"    [+] Interface eth0 sur {name}")

    # Assigner IP
    # Calculer le prefix correspondant
    if ip.startswith("192.168.3."):
        prefix = "/24"
    elif ip.startswith("192.168.80."):
        prefix = "/24"
    else:
        prefix = "/24"

    full_ip = f"{ip}{prefix}"
    ip_obj = nb.ipam.ip_addresses.get(address=full_ip)
    if not ip_obj:
        ip_obj = nb.ipam.ip_addresses.create(
            address=full_ip,
            assigned_object_type="virtualization.vminterface",
            assigned_object_id=iface.id,
            description=f"IP de {name}",
        )
        print(f"    [+] IP {ip} assignee a {name}")

    # Definir IP primaire
    if not vm.primary_ip4 or vm.primary_ip4.address != full_ip:
        vm.primary_ip4 = ip_obj.id
        vm.save()

# =============================================================================
# 8. SERVICES
# =============================================================================
print("\n" + "=" * 70)
print("8. Services")
print("=" * 70)

SERVICES = [
    # (vm_name, name, protocol, ports, description)
    ("dns-rec-01",   "DNS recursif",   "udp", [53],   "AdGuard Home DNS recursif"),
    ("dns-rec-01",   "AdGuard UI",     "tcp", [3001], "Interface AdGuard Home"),
    ("dns-auth-01",  "DNS authoritative","udp",[53], "BIND9 autoritaire infra.lan"),
    ("pgsql-01",     "PostgreSQL",     "tcp", [5432],"Base de donnees applicative"),
    ("web-01",       "HTTP backend",   "tcp", [80],  "Nginx web-01"),
    ("web-02",       "HTTP backend",   "tcp", [80],  "Nginx web-02"),
    ("web-03",       "HTTP backend",   "tcp", [80],  "Nginx web-03"),
    ("lb-01",        "HAProxy stats",  "tcp", [8404],"Statistiques HAProxy"),
    ("lb-01",        "HTTPS",          "tcp", [443], "Frontal HTTPS"),
    ("lb-01",        "HTTP",           "tcp", [80],  "Frontal HTTP"),
    ("monitoring-01","Prometheus",     "tcp", [9090],"Metriques"),
    ("monitoring-01","Grafana",        "tcp", [3000],"Dashboards"),
    ("monitoring-01","Loki",           "tcp", [3100],"Agregation logs"),
    ("glpi-01",      "GLPI HTTP",      "tcp", [80],  "Helpdesk"),
    ("netbox-01",    "NetBox HTTP",    "tcp", [80],  "IPAM via Nginx"),
]

for vm_name, svc_name, proto, ports, desc in SERVICES:
    vm = nb.virtualization.virtual_machines.get(name=vm_name)
    if not vm:
        print(f"  [!] VM introuvable : {vm_name}")
        continue

    existing = nb.ipam.services.filter(virtual_machine_id=vm.id, name=svc_name)
    if list(existing):
        print(f"  [=] Service existe : {svc_name} sur {vm_name}")
        continue

    nb.ipam.services.create(
        virtual_machine=vm.id,
        name=svc_name,
        protocol=proto,
        ports=ports,
        description=desc,
    )
    print(f"  [+] Service : {svc_name} sur {vm_name} ({proto.upper()}:{','.join(map(str,ports))})")

# =============================================================================
# RESUME
# =============================================================================
print("\n" + "=" * 70)
print("RESUME")
print("=" * 70)
print(f"Sites          : {nb.dcim.sites.count()}")
print(f"Clusters       : {nb.virtualization.clusters.count()}")
print(f"VLANs          : {nb.ipam.vlans.count()}")
print(f"Prefixes       : {nb.ipam.prefixes.count()}")
print(f"Devices        : {nb.dcim.devices.count()}")
print(f"VMs            : {nb.virtualization.virtual_machines.count()}")
print(f"IPs            : {nb.ipam.ip_addresses.count()}")
print(f"Services       : {nb.ipam.services.count()}")
print()
print(f"Voir le resultat : {NETBOX_URL}")
print("Termine.")
