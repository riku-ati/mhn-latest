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
DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-pip supervisor

# ── Try apt install first ───────────────────────────────────────────────────
SNORT_BIN=""
if DEBIAN_FRONTEND=noninteractive apt-get install -y snort3 2>/dev/null; then
    # apt package installs the binary as 'snort' (not 'snort3')
    SNORT_BIN=$(command -v snort3 2>/dev/null || command -v snort 2>/dev/null || true)
fi

# ── Source build fallback ───────────────────────────────────────────────────
if [ -z "$SNORT_BIN" ]; then
    echo "snort3 not in apt — building from source..."

    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        build-essential cmake pkg-config autoconf libtool \
        libpcap-dev libpcre3-dev \
        libdnet-dev libdumbnet-dev \
        bison flex \
        zlib1g-dev liblzma-dev \
        openssl libssl-dev \
        libhwloc-dev \
        cpputest libsqlite3-dev uuid-dev \
        libluajit-5.1-dev libunwind-dev libfl-dev curl

    # ── Build libdaq (provides DAQ_Msg_h etc.) ──────────────────────────────
    # Keep the raw tag for the URL (GitHub uses the exact tag string, e.g. v3.0.27);
    # strip the leading 'v' only for the extracted directory name (GitHub drops it).
    LIBDAQ_TAG=$(curl -s https://api.github.com/repos/snort3/libdaq/releases/latest \
        | grep -oP '"tag_name":\s*"\K[^"]+' | head -1)
    LIBDAQ_VERSION=${LIBDAQ_TAG#v}
    if [ -z "$LIBDAQ_VERSION" ]; then
        LIBDAQ_TAG="v3.0.16"
        LIBDAQ_VERSION="3.0.16"
    fi

    cd /tmp
    wget "https://github.com/snort3/libdaq/archive/refs/tags/${LIBDAQ_TAG}.tar.gz" \
         -O "libdaq-${LIBDAQ_VERSION}.tar.gz"
    tar xzf "libdaq-${LIBDAQ_VERSION}.tar.gz"
    cd "libdaq-${LIBDAQ_VERSION}"
    ./bootstrap
    ./configure --prefix=/usr/local
    make -j$(nproc)
    make install
    ldconfig

    # ── Build snort3 ────────────────────────────────────────────────────────
    SNORT3_TAG=$(curl -s https://api.github.com/repos/snort3/snort3/releases/latest \
        | grep -oP '"tag_name":\s*"\K[^"]+' | head -1)
    SNORT3_VERSION=${SNORT3_TAG#v}
    if [ -z "$SNORT3_VERSION" ]; then
        SNORT3_TAG="3.12.2.0"
        SNORT3_VERSION="3.12.2.0"
    fi

    echo "Building Snort3 ${SNORT3_VERSION}..."
    cd /tmp
    # Use GitHub auto-generated source archive (releases/download has no tarball asset)
    wget "https://github.com/snort3/snort3/archive/refs/tags/${SNORT3_TAG}.tar.gz" \
         -O "snort3-${SNORT3_VERSION}.tar.gz"
    tar xzf "snort3-${SNORT3_VERSION}.tar.gz"
    cd "snort3-${SNORT3_VERSION}"
    ./configure_cmake.sh --prefix=/usr/local/snort
    cd build && make -j$(nproc) && make install
    ldconfig

    SNORT_BIN=/usr/local/snort/bin/snort
fi

echo "Snort binary: ${SNORT_BIN}"

# ── Detect DAQ plugin directory (varies by install method and arch) ─────────
DAQ_DIR=$(find /usr/lib /usr/local/lib -type d -name "daq" 2>/dev/null | head -1 || true)
DAQ_FLAG=""
[ -n "$DAQ_DIR" ] && DAQ_FLAG="--daq-dir ${DAQ_DIR}"

# ── Install hpfeeds bridge ──────────────────────────────────────────────────
pip3 install hpfeeds

mkdir -p /var/log/snort /etc/snort/rules

# Write minimal snort3 config with JSON alert output
cat > /etc/snort/snort.lua << 'LUAEOF'
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
LUAEOF

touch /etc/snort/rules/snort.rules

# Register sensor with MHN server
wget "$server_url/static/registration.txt" -O /tmp/registration.sh
chmod 755 /tmp/registration.sh
. /tmp/registration.sh "$server_url" "$deploy_key" "snort"

# Write hpfeeds bridge script
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

# Supervisor config — use detected binary and DAQ path
cat > /etc/supervisor/conf.d/snort.conf << EOF
[program:snort]
command=${SNORT_BIN} -c /etc/snort/snort.lua -i ${INTERFACE} ${DAQ_FLAG}
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
cat > /etc/cron.daily/update_snort_rules << CRON
#!/bin/bash
wget -q "${server_url}/static/mhn.rules" -O /etc/snort/rules/snort.rules.tmp && \
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
echo "Binary: ${SNORT_BIN}"
echo "Manage with supervisorctl (not service/systemctl):"
echo "  supervisorctl status"
echo "  supervisorctl restart snort"
echo "  supervisorctl tail -f snort"
