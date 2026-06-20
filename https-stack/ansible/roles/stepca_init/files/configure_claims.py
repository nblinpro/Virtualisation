#!/usr/bin/env python3
"""
Configure les claims TLS dans ca.json de step-ca
Usage : configure_claims.py <ca.json> <min> <max> <default>
"""
import json
import sys

if len(sys.argv) != 5:
    print(f"Usage: {sys.argv[0]} <ca.json> <min> <max> <default>")
    sys.exit(1)

ca_json_path = sys.argv[1]
min_duration = sys.argv[2]
max_duration = sys.argv[3]
default_duration = sys.argv[4]

with open(ca_json_path) as f:
    config = json.load(f)

# Verifier si deja configures (idempotence)
current_max = config.get('authority', {}).get('claims', {}).get('maxTLSCertDuration')
if current_max == max_duration:
    # Verifier aussi tous les provisioners
    all_ok = True
    for p in config.get('authority', {}).get('provisioners', []):
        if p.get('claims', {}).get('maxTLSCertDuration') != max_duration:
            all_ok = False
            break
    if all_ok:
        print("ALREADY_CONFIGURED")
        sys.exit(0)

# Claims globaux
config['authority']['claims'] = {
    "minTLSCertDuration": min_duration,
    "maxTLSCertDuration": max_duration,
    "defaultTLSCertDuration": default_duration
}

# Claims par provisioner
for p in config['authority']['provisioners']:
    p['claims'] = {
        "minTLSCertDuration": min_duration,
        "maxTLSCertDuration": max_duration,
        "defaultTLSCertDuration": default_duration
    }

with open(ca_json_path, 'w') as f:
    json.dump(config, f, indent=2)

print("CHANGED")
