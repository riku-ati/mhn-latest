#!/bin/bash
# deploy_suricata.sh — Suricata IDS with hpfeeds bridge
# Tested on Ubuntu 20.04 / 22.04
# Uses OISF PPA for current Suricata; a Python3 bridge tails eve.json → hpfeeds.

INTERFACE=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'dev \K\S+' | head -1)

set -e
set -x

if [ $# -lt 2 ]; then
    echo "Wrong number of arguments supplied."
    echo "Usage: $0 <server_url> <deploy_key> [interface]"
    exit 1
fi

[ $# -ge 3 ] && INTERFACE=$3

if [ -z "$INTERFACE" ]; then
    echo "Could not detect network interface. Provide it as third argument."
    echo "Usage: $0 <server_url> <deploy_key> <interface>"
    exit 1
fi

server_url=$1
deploy_key=$2

# Install Suricata from OISF PPA (current stable)
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y software-properties-common
add-apt-repository -y ppa:oisf/suricata-stable
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y suricata suricata-update \
    python3 python3-pip supervisor

# Install hpfeeds Python client for bridge
pip3 install hpfeeds

# Update Suricata rules
suricata-update

# Configure Suricata to write EVE JSON (used by hpfeeds bridge)
cat > /etc/suricata/suricata.yaml << EOF
%YAML 1.1
---
vars:
  address-groups:
    HOME_NET: "[192.168.0.0/16,10.0.0.0/8,172.16.0.0/12]"
    EXTERNAL_NET: "!\$HOME_NET"
  port-groups:
    HTTP_PORTS: "80"
    SHELLCODE_PORTS: "!80"
    ORACLE_PORTS: 1521
    SSH_PORTS: 22
    DNP3_PORTS: 20000
    MODBUS_PORTS: 502

default-log-dir: /var/log/suricata/

outputs:
  - eve-log:
      enabled: yes
      filetype: regular
      filename: eve.json
      types:
        - alert:
            payload: yes
            payload-buffer-size: 4kb
            http-body: yes
            http-body-printable: yes
            metadata: yes
            tagged-packets: yes
        - drop:
            alerts: yes
        - http:
            extended: yes
        - dns:
        - tls:
            extended: yes
        - ssh
        - stats:
            totals: yes
            threads: no
            deltas: no
        - flow
  - fast:
      enabled: no

af-packet:
  - interface: ${INTERFACE}
    cluster-id: 99
    cluster-type: cluster_flow
    defrag: yes

app-layer:
  protocols:
    tls:
      enabled: yes
    dns:
      enabled: yes
    http:
      enabled: yes
    ftp:
      enabled: yes
    ssh:
      enabled: yes
    smtp:
      enabled: yes

detect:
  profile: medium
  custom-values:
    toclient-groups: 3
    toserver-groups: 25
  sgh-mpm-context: auto
  inspection-recursion-limit: 3000

default-rule-path: /var/lib/suricata/rules
rule-files:
  - suricata.rules

EOF

# Register sensor with MHN server
wget "$server_url/static/registration.txt" -O /tmp/registration.sh
chmod 755 /tmp/registration.sh
. /tmp/registration.sh "$server_url" "$deploy_key" "suricata"

# Write hpfeeds bridge script (tails eve.json and publishes alerts to hpfeeds)
cat > /opt/suricata-hpfeeds.py << EOF
#!/usr/bin/env python3
"""Tail suricata eve.json and publish alert events to hpfeeds."""
import json
import time
import os
import hpfeeds

HPF_HOST    = "${HPF_HOST}"
HPF_PORT    = ${HPF_PORT}
HPF_IDENT   = "${HPF_IDENT}"
HPF_SECRET  = "${HPF_SECRET}"
EVE_LOG     = "/var/log/suricata/eve.json"
CHANNEL     = "suricata.events"

def tail(filename):
    with open(filename) as f:
        f.seek(0, 2)
        while True:
            line = f.readline()
            if not line:
                time.sleep(0.1)
                continue
            yield line.strip()

def main():
    while not os.path.exists(EVE_LOG):
        print("Waiting for eve.json...")
        time.sleep(3)

    while True:
        try:
            hpc = hpfeeds.new(HPF_HOST, HPF_PORT, HPF_IDENT, HPF_SECRET)
            print(f"Connected to hpfeeds broker {HPF_HOST}:{HPF_PORT}")
            for line in tail(EVE_LOG):
                try:
                    rec = json.loads(line)
                    if rec.get("event_type") == "alert":
                        hpc.publish(CHANNEL, json.dumps(rec))
                except Exception as e:
                    print(f"Parse error: {e}")
        except Exception as e:
            print(f"hpfeeds error: {e} — reconnecting in 10s")
            time.sleep(10)

if __name__ == "__main__":
    main()
EOF
chmod +x /opt/suricata-hpfeeds.py

# Supervisor: run suricata + hpfeeds bridge
cat > /etc/supervisor/conf.d/suricata.conf << EOF
[program:suricata]
command=/usr/bin/suricata -c /etc/suricata/suricata.yaml -i ${INTERFACE}
directory=/var/log/suricata
stdout_logfile=/var/log/suricata/suricata.out
stderr_logfile=/var/log/suricata/suricata.err
autostart=true
autorestart=true
stopsignal=QUIT

[program:suricata-hpfeeds]
command=/usr/bin/python3 /opt/suricata-hpfeeds.py
stdout_logfile=/var/log/suricata/hpfeeds.out
stderr_logfile=/var/log/suricata/hpfeeds.err
autostart=true
autorestart=true
EOF

supervisorctl reread
supervisorctl update
supervisorctl start suricata
sleep 5
supervisorctl start suricata-hpfeeds
