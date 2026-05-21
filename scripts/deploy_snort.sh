#!/bin/bash
# deploy_snort.sh — Snort 3 IDS with hpfeeds bridge
# Tested on Ubuntu 20.04 / 22.04

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
    echo "Could not detect network interface. Provide as third argument."
    exit 1
fi

server_url=$1
deploy_key=$2

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    snort3 \
    python3 python3-pip \
    supervisor || {

    # Fallback: build snort3 from source if not in apt
    # Resolve the latest release tag from GitHub
    SNORT3_VERSION=$(curl -s https://api.github.com/repos/snort3/snort3/releases/latest \
        | grep -oP '"tag_name":\s*"\K[^"]+' | head -1)
    # Strip leading 'v' if present
    SNORT3_VERSION=${SNORT3_VERSION#v}

    if [ -z "$SNORT3_VERSION" ]; then
        # Hard-coded fallback if GitHub API is unreachable
        SNORT3_VERSION="3.12.2.0"
    fi

    echo "Building Snort3 ${SNORT3_VERSION} from source..."

    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        build-essential libpcap-dev libpcre3-dev libdnet-dev \
        libdumbnet-dev bison flex zlib1g-dev liblzma-dev \
        openssl libssl-dev pkg-config libhwloc-dev cmake \
        cpputest libsqlite3-dev uuid-dev libluajit-5.1-dev \
        libunwind-dev libfl-dev curl

    cd /tmp
    # Use the GitHub auto-generated source archive (always present for every tag;
    # the releases/download/ URL only works if a tarball asset was manually attached)
    wget "https://github.com/snort3/snort3/archive/refs/tags/${SNORT3_VERSION}.tar.gz" \
         -O "snort3-${SNORT3_VERSION}.tar.gz"
    tar xzf "snort3-${SNORT3_VERSION}.tar.gz"
    cd "snort3-${SNORT3_VERSION}"
    ./configure_cmake.sh --prefix=/usr/local/snort
    cd build && make -j$(nproc) && make install
    ln -sf /usr/local/snort/bin/snort /usr/bin/snort3
}

# Install hpfeeds Python client for bridge
pip3 install hpfeeds

mkdir -p /var/log/snort /etc/snort/rules

# Write minimal snort3 config with JSON alert output
cat > /etc/snort/snort.lua << EOF
HOME_NET = 'any'
EXTERNAL_NET = 'any'

ips =
{
    include = RULE_PATH .. '/snort.rules',
    enable_builtin_rules = false,
    mode = 'alert'
}

alert_json =
{
    file = true,
    output = '/var/log/snort/alert.json',
    fields = 'seconds action class b64_data dir dst_addr dst_port eth_dst eth_len eth_src eth_type gid iface ip_id ip_len msg mpls pkt_gen pkt_len pkt_num priority proto rule service sid src_addr src_port tos ttl udp_len vlan rev'
}
EOF

mkdir -p /etc/snort/rules
touch /etc/snort/rules/snort.rules

# Register sensor with MHN server
wget "$server_url/static/registration.txt" -O /tmp/registration.sh
chmod 755 /tmp/registration.sh
. /tmp/registration.sh "$server_url" "$deploy_key" "snort"

# Write hpfeeds bridge script (tails alert.json and publishes to hpfeeds)
cat > /opt/snort-hpfeeds.py << EOF
#!/usr/bin/env python3
"""Tail snort3 alert_json output and publish to hpfeeds."""
import json
import time
import os
import hpfeeds

HPF_HOST    = "${HPF_HOST}"
HPF_PORT    = ${HPF_PORT}
HPF_IDENT   = "${HPF_IDENT}"
HPF_SECRET  = "${HPF_SECRET}"
ALERT_LOG   = "/var/log/snort/alert.json"
CHANNEL     = "snort.alerts"

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
    while not os.path.exists(ALERT_LOG):
        print("Waiting for alert.json...")
        time.sleep(3)

    while True:
        try:
            hpc = hpfeeds.new(HPF_HOST, HPF_PORT, HPF_IDENT, HPF_SECRET)
            print(f"Connected to hpfeeds broker {HPF_HOST}:{HPF_PORT}")
            for line in tail(ALERT_LOG):
                try:
                    rec = json.loads(line)
                    hpc.publish(CHANNEL, json.dumps(rec))
                except Exception as e:
                    print(f"Parse error: {e}")
        except Exception as e:
            print(f"hpfeeds error: {e} — reconnecting in 10s")
            time.sleep(10)

if __name__ == "__main__":
    main()
EOF
chmod +x /opt/snort-hpfeeds.py

# Pull MHN rules
wget "$server_url/static/mhn.rules" -O /etc/snort/rules/snort.rules 2>/dev/null || true

# Supervisor config
cat > /etc/supervisor/conf.d/snort.conf << EOF
[program:snort]
command=/usr/bin/snort3 -c /etc/snort/snort.lua -i ${INTERFACE} --daq-dir /usr/lib/x86_64-linux-gnu/daq
directory=/var/log/snort
stdout_logfile=/var/log/snort/snort.out
stderr_logfile=/var/log/snort/snort.err
autostart=true
autorestart=true
stopsignal=QUIT

[program:snort-hpfeeds]
command=/usr/bin/python3 /opt/snort-hpfeeds.py
stdout_logfile=/var/log/snort/hpfeeds.out
stderr_logfile=/var/log/snort/hpfeeds.err
autostart=true
autorestart=true
EOF

# Daily rule update cron
cat > /etc/cron.daily/update_snort_rules << 'CRON'
#!/bin/bash
wget -q "$server_url/static/mhn.rules" -O /etc/snort/rules/snort.rules.tmp && \
    mv /etc/snort/rules/snort.rules.tmp /etc/snort/rules/snort.rules && \
    supervisorctl restart snort
CRON
chmod 755 /etc/cron.daily/update_snort_rules

supervisorctl reread
supervisorctl update
supervisorctl start snort
sleep 3
supervisorctl start snort-hpfeeds

echo ""
echo "=== Snort3 deploy complete ==="
echo "Manage with supervisorctl, not service/systemctl:"
echo "  supervisorctl status"
echo "  supervisorctl restart snort"
echo "  supervisorctl tail -f snort"
