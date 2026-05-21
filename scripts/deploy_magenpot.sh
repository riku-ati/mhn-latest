#!/bin/bash

set -e
set -x

if [ $# -ne 2 ]
    then
        echo "Wrong number of arguments supplied."
        echo "Usage: $0 <server_url> <deploy_key>."
        exit 1
fi

server_url=$1
deploy_key=$2

apt-get update
apt-get -y install git supervisor curl

####################################################################
# Install Go (current stable)
GO_VERSION="1.22.4"
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  GO_PACKAGE="go${GO_VERSION}.linux-amd64.tar.gz" ;;
    aarch64) GO_PACKAGE="go${GO_VERSION}.linux-arm64.tar.gz" ;;
    armv7l|armv6l) GO_PACKAGE="go${GO_VERSION}.linux-armv6l.tar.gz" ;;
    *) GO_PACKAGE="go${GO_VERSION}.linux-386.tar.gz" ;;
esac

rm -rf /usr/local/go
cd /usr/local/
wget "https://go.dev/dl/${GO_PACKAGE}"
tar zxf "${GO_PACKAGE}" && rm "${GO_PACKAGE}"

export PATH="/usr/local/go/bin:$PATH"
ln -sf /usr/local/go/bin/go /usr/bin/go 2>/dev/null || true
ln -sf /usr/local/go/bin/gofmt /usr/bin/gofmt 2>/dev/null || true
####################################################################

export GO111MODULE=on
export GOPATH=/root/go

# Get the magenpot source
cd /opt
git clone https://github.com/trevorleake/magenpot.git
cd magenpot

go build

# Register the sensor with the MHN server.
wget $server_url/static/registration.txt -O registration.sh
chmod 755 registration.sh
# Note: this will export the HPF_* variables
. ./registration.sh $server_url $deploy_key "agave"

cat > config.toml<<EOF
# magenpot Configuration File

[magento]
# Port to server the honeypot webserver on.
# Note: Ports under 1024 require sudo.
port = 80

site_name = "Magenpot"
name_randomizer = true

# Allows you to set the magento_version file content to spoof different versions.
# Always served as "http[s]://server/magento_version"
magento_version_text = "Magento/2.3 (Enterprise)"

[hpfeeds]
enabled = true
host = "$HPF_HOST"
port = $HPF_PORT
ident = "$HPF_IDENT"
auth = "$HPF_SECRET"
channel = "agave.events"

[fetch_public_ip]
enabled = true
urls = ["http://icanhazip.com/", "http://ifconfig.me/ip"]

EOF

# Config for supervisor.
cat > /etc/supervisor/conf.d/magenpot.conf <<EOF
[program:magenpot]
command=/opt/magenpot/magenpot
directory=/opt/magenpot
stdout_logfile=/opt/magenpot/magenpot.out
stderr_logfile=/opt/magenpot/magenpot.err
autostart=true
autorestart=true
redirect_stderr=true
stopsignal=QUIT
EOF

supervisorctl update
supervisorctl start magenpot
