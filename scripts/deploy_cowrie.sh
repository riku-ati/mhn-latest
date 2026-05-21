#!/bin/bash
# deploy_cowrie.sh — Modern Cowrie SSH/Telnet honeypot
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

# Install dependencies
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    git python3 python3-pip python3-venv \
    supervisor authbind \
    build-essential libssl-dev libffi-dev \
    iptables

# Move SSH daemon to port 2222 so Cowrie can take port 22
if ! grep -qE "^Port 2222" /etc/ssh/sshd_config; then
    sed -i 's/^#\?Port 22$/Port 2222/' /etc/ssh/sshd_config
    grep -q "^Port " /etc/ssh/sshd_config || echo "Port 2222" >> /etc/ssh/sshd_config
fi
systemctl restart ssh || service ssh restart

# Redirect external port 22 to cowrie's 2222 via iptables
iptables -t nat -A PREROUTING -p tcp --dport 22 -j REDIRECT --to-port 2222
iptables -t nat -A PREROUTING -p tcp --dport 23 -j REDIRECT --to-port 2223

# Save iptables rules across reboots
DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
iptables-save > /etc/iptables/rules.v4

# Create cowrie system user
id cowrie &>/dev/null || useradd -r -d /opt/cowrie -m -s /sbin/nologin cowrie

# Clone current Cowrie
rm -rf /opt/cowrie
git clone https://github.com/cowrie/cowrie.git /opt/cowrie
cd /opt/cowrie

# Create virtualenv and install
python3 -m venv cowrie-env
source cowrie-env/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# Register sensor with MHN server
wget "$server_url/static/registration.txt" -O /tmp/registration.sh
chmod 755 /tmp/registration.sh
. /tmp/registration.sh "$server_url" "$deploy_key" "cowrie"

# Base config from template
cd /opt/cowrie/etc
cp cowrie.cfg.dist cowrie.cfg

# hpfeeds output — appended so it doesn't conflict with commented examples
cat >> cowrie.cfg << EOF

[output_hpfeeds]
enabled = true
server = ${HPF_HOST}
port = ${HPF_PORT}
identifier = ${HPF_IDENT}
secret = ${HPF_SECRET}
debug = false
EOF

# Set listen ports (iptables redirects 22→2222, 23→2223 externally)
sed -i 's/^#\?listen_endpoints = .*/listen_endpoints = tcp:2222:interface=0.0.0.0/' cowrie.cfg

# Fix permissions
chown -R cowrie:cowrie /opt/cowrie

mkdir -p /opt/cowrie/var/log/cowrie /opt/cowrie/var/run
chown -R cowrie:cowrie /opt/cowrie/var

# Supervisor config — run twistd directly so supervisor tracks the process
cat > /etc/supervisor/conf.d/cowrie.conf << EOF
[program:cowrie]
command=/opt/cowrie/cowrie-env/bin/twistd -n --umask=0022 --pidfile= -y /opt/cowrie/cowrie/core/app.py
directory=/opt/cowrie
user=cowrie
stdout_logfile=/opt/cowrie/var/log/cowrie/cowrie.out
stderr_logfile=/opt/cowrie/var/log/cowrie/cowrie.err
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
EOF

supervisorctl reread
supervisorctl update
supervisorctl start cowrie
