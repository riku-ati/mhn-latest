#!/bin/bash
# ============================================================
# WARNING: Glastopf is DEPRECATED and Python 2.7 only.
# The upstream project (mushorg/glastopf) has not been updated
# since 2017 and requires Python 2.7, which is end-of-life.
# This script is preserved for historical reference but is NOT
# expected to work on Ubuntu 20.04+.
# Consider using a maintained alternative such as:
#   - SNARE/TANNER  (https://github.com/mushorg/snare)
#   - Glutton       (https://github.com/mushorg/glutton)
# ============================================================

set -e
set -x

if [ $# -ne 2 ]
    then
        echo "Wrong number of arguments supplied."
        echo "Usage: $0 <server_url> <deploy_key>."
        exit 1
fi

# Check if Ubuntu 18.04 or 16.04 (only supported releases)
UBUNTU_VER=$(lsb_release -r -s 2>/dev/null || echo "unknown")
if [ "$UBUNTU_VER" != "18.04" ] && [ "$UBUNTU_VER" != "16.04" ]; then
    echo "WARNING: Glastopf is only tested on Ubuntu 16.04/18.04."
    echo "This script is likely to fail on $UBUNTU_VER."
    echo "Continue? (y/n)"
    read PROMPT
    if [ "$PROMPT" == "n" ] || [ "$PROMPT" == "N" ]; then
        exit 1
    fi
fi

server_url=$1
deploy_key=$2
GLASTOPF_HOME=/opt/glastopf

# Update repository
apt-get update

# Install Prerequisites — Python 2.7 packages (Ubuntu 16.04/18.04 only)
apt-get install -y \
    apache2 \
    python2.7 \
    python-openssl \
    python-gevent \
    libevent-dev \
    python2.7-dev \
    build-essential \
    make \
    python-chardet \
    python-requests \
    python-sqlalchemy \
    python-lxml \
    python-beautifulsoup \
    python-pip \
    python-dev \
    python-setuptools \
    g++ \
    git \
    php \
    php-dev \
    liblapack-dev \
    gfortran \
    libmysqlclient-dev \
    libxml2-dev \
    libxslt-dev \
    supervisor

pip install -e git+https://github.com/pwnlandia/hpfeeds.git#egg=hpfeeds-dev

# Install and configure the PHP sandbox
cd /opt
git clone git://github.com/mushorg/BFR.git
cd BFR
phpize
./configure --enable-bfr
make && make install

# Update php.ini to add bfr.so
BFR_BUILD_OUTPUT=$(find /usr/lib/php/ -type f -name "bfr.so" | awk -F"/" '{print $5}')
echo "zend_extension = /usr/lib/php/$BFR_BUILD_OUTPUT/bfr.so" >> /etc/php/7.0/fpm/php.ini

# Stop apache2 and disable it from start up
service apache2 stop
update-rc.d -f apache2 remove

# Upgrade python-greenlet
pip install --upgrade greenlet

# Install glastopf
pip install --upgrade pgen
pip install --upgrade cython
pip uninstall --yes setuptools
git clone https://github.com/mushorg/glastopf.git $GLASTOPF_HOME
cd $GLASTOPF_HOME
python setup.py install

# Register the sensor with the MHN server.
wget $server_url/static/registration.txt -O registration.sh
chmod 0755 registration.sh
# Note: This will export the HPF_* variables
. ./registration.sh $server_url $deploy_key "glastopf"

# Add the modified glastopf.cfg
cat > $GLASTOPF_HOME/glastopf.cfg <<EOF
[webserver]
host = 0.0.0.0
port = 80
uid = nobody
gid = nogroup
proxy_enabled = False

[ssl]
enabled = False
certfile =
keyfile =

#Generic logging for general monitoring
[logging]
consolelog_enabled = False
filelog_enabled = True
logfile = log/glastopf.log

[dork-db]
enabled = True
pattern = rfi
#Extracts dorks from a online dorks service operated by The Honeynet Project
mnem_service = True

[hpfeed]
enabled = True
host = $HPF_HOST
port = $HPF_PORT
secret = $HPF_SECRET
# channels comma separated
chan_events = glastopf.events
chan_files = glastopf.files
ident = $HPF_IDENT

[main-database]
enabled = True
connection_string = sqlite:///db/glastopf.db

[surfcertids]
enabled = False
host = localhost
port = 5432
user =
password =
database = idsserver

[syslog]
enabled = False
socket = /dev/log

[mail]
enabled = False
patterns = rfi,lfi
user =
pwd =
mail_from =
mail_to =
smtp_host = smtp.gmail.com
smtp_port = 587

[taxii]
enabled = False
host = taxiitest.mitre.org
port = 80
inbox_path = /services/inbox/default/
use_https = False
use_auth_basic = False
auth_basic_username = your_username
auth_basic_password = your_password
use_auth_certificate = False
auth_certificate_keyfile = full_path_to_keyfile
auth_certificate_certfile = full_path_to_certfile
include_contact_info = False
contact_name = ...
contact_email = ...

[logstash]
enabled = False
host = localhost
port = 5659
handler = AMQP/TCP/UDP

[misc]
banner = Apache/2.0.48

[surface]
google_meta =
bing_meta =

[sensor]
sensorid = None

[profiler]
enabled = False

[s3storage]
enabled = False
endpoint = http://localhost:8080/
aws_access_key_id = YOUR_aws_access_key_id
aws_secret_access_key = YOUR_aws_access_key_id
bucket = glastopf
region = eu-west-1
signature_version = s3
EOF

# Set up supervisor
cat > /etc/supervisor/conf.d/glastopf.conf <<EOF
[program:glastopf]
command=/usr/bin/python /usr/local/bin/glastopf-runner
directory=$GLASTOPF_HOME
stdout_logfile=/var/log/glastopf.out
stderr_logfile=/var/log/glastopf.err
autostart=true
autorestart=true
redirect_stderr=true
stopsignal=QUIT
EOF

supervisorctl update
supervisorctl restart all
