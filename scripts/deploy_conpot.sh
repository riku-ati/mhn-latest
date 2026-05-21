#!/bin/bash
# deploy_conpot.sh — Conpot ICS/SCADA honeypot
# Tested on Ubuntu 20.04 / 22.04

set -e
set -x

if [ $# -ne 2 ]; then
    echo "Wrong number of arguments supplied."
    echo "Usage: $0 <server_url> <deploy_key>"
    exit 1
fi

server_url=$1
deploy_key=$2

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3 python3-pip python3-venv python3-dev \
    git supervisor \
    libxslt1-dev libxml2-dev libffi-dev libssl-dev \
    build-essential pkg-config

# Create virtualenv for conpot
python3 -m venv /opt/conpot/env
source /opt/conpot/env/bin/activate
pip install --upgrade pip setuptools wheel

# Install conpot (Python 3, available on PyPI)
pip install conpot

# Register sensor with MHN server
wget "$server_url/static/registration.txt" -O /tmp/registration.sh
chmod 755 /tmp/registration.sh
. /tmp/registration.sh "$server_url" "$deploy_key" "conpot"

mkdir -p /opt/conpot/etc /var/log/conpot

# Write conpot config
cat > /opt/conpot/etc/conpot.cfg << EOF
[common]
sensorid = default

[session]
timeout = 30

[daemon]
; user = conpot
; group = conpot

[json]
enabled = True
filename = /var/log/conpot/conpot.json

[sqlite]
enabled = False

[mysql]
enabled = False

[syslog]
enabled = False
device = /dev/log
host = localhost
port = 514
facility = local0
socket = dev

[hpfriends]
enabled = True
host = ${HPF_HOST}
port = ${HPF_PORT}
ident = ${HPF_IDENT}
secret = ${HPF_SECRET}
channels = ["conpot.events", ]

[fetch_public_ip]
enabled = True
urls = ["http://icanhazip.com/", "http://ifconfig.me/ip"]
EOF

# Supervisor config
cat > /etc/supervisor/conf.d/conpot.conf << EOF
[program:conpot]
command=/opt/conpot/env/bin/conpot --template default -c /opt/conpot/etc/conpot.cfg -l /var/log/conpot/conpot.log
directory=/opt/conpot
stdout_logfile=/var/log/conpot/conpot.out
stderr_logfile=/var/log/conpot/conpot.err
autostart=true
autorestart=true
redirect_stderr=false
stopsignal=QUIT
EOF

supervisorctl reread
supervisorctl update
supervisorctl start conpot
