"""
Runtime config — reads all settings from environment variables so no
manual template substitution is needed in Docker or local dev.
"""

import os
from celery.schedules import crontab

_basedir = os.path.abspath(os.path.dirname(__file__))

MHN_SERVER_HOME = _basedir

# Core app settings
DEBUG = os.environ.get('DEBUG', 'false').lower() == 'true'
SECRET_KEY = os.environ.get('SECRET_KEY') or 'changeme-set-SECRET_KEY-env-var'
SUPERUSER_EMAIL = os.environ.get('SUPERUSER_EMAIL', 'admin@example.com')
SUPERUSER_PASSWORD = os.environ.get('SUPERUSER_PASSWORD', 'mhnpassword')
SERVER_BASE_URL = os.environ.get('SERVER_BASE_URL', 'http://localhost:8080')
HONEYMAP_URL = os.environ.get('HONEYMAP_URL', '')
DEPLOY_KEY = os.environ.get('DEPLOY_KEY', '')
LOG_FILE_PATH = os.environ.get('LOG_FILE_PATH', '/var/log/mhn/mhn.log')

# Mail settings
MAIL_SERVER = os.environ.get('MAIL_SERVER', '')
MAIL_PORT = int(os.environ.get('MAIL_PORT', '25'))
MAIL_USE_TLS = os.environ.get('MAIL_USE_TLS', 'false').lower() == 'true'
MAIL_USE_SSL = os.environ.get('MAIL_USE_SSL', 'false').lower() == 'true'
MAIL_USERNAME = os.environ.get('MAIL_USERNAME', '')
MAIL_PASSWORD = os.environ.get('MAIL_PASSWORD', '')
DEFAULT_MAIL_SENDER = os.environ.get('DEFAULT_MAIL_SENDER', '')
MAIL_DEBUG = DEBUG

# Database — /app/db is a named Docker volume so the DB survives container restarts
SQLALCHEMY_DATABASE_URI = os.environ.get(
    'SQLALCHEMY_DATABASE_URI',
    'sqlite:///' + os.path.join(_basedir, 'db', 'mhn.db')
)

# Set TESTING=true to skip Snort rules download in initdatabase.py
TESTING = os.environ.get('TESTING', 'false').lower() == 'true'

# Honeypot deploy scripts directory (set by Docker COPY scripts/ /scripts/)
SCRIPTS_DIR = os.environ.get('SCRIPTS_DIR', '/scripts')
SQLALCHEMY_TRACK_MODIFICATIONS = False

# Flask-Security
SECURITY_PASSWORD_HASH = 'bcrypt'
SECURITY_PASSWORD_SALT = SECRET_KEY
SECURITY_LOGIN_URL = '/ui/login/'

# MongoDB (used by Clio)
MONGODB_HOST = os.environ.get('MONGODB_HOST', 'localhost')
MONGODB_PORT = int(os.environ.get('MONGODB_PORT', '27017'))

# Celery / Redis
BROKER_URL = os.environ.get('REDIS_URL', 'redis://localhost:6379/0')
CELERY_RESULT_BACKEND = BROKER_URL

# Misc
FEED_AUTH_REQUIRED = False
RENDERED_RULES_PATH = os.path.join(_basedir, 'app/static/mhn.rules')

CELERYBEAT_SCHEDULE = {
    'fetch-emerging-rules': {
        'task': 'app.tasks.rules.fetch_sources',
        'schedule': crontab(hour=12),
        'args': ()
    }
}

SNORT_RULES_SOURCE = {
    'name': 'Emerging Threats',
    'uri': 'https://rules.emergingthreats.net/open/snort-2.9.0/emerging.rules.tar.gz'
}

HONEYPOT_CHANNELS = {
    'dionaea': [
        'mwbinary.dionaea.sensorunique',
        'dionaea.capture',
        'dionaea.capture.anon',
        'dionaea.caputres',
        'dionaea.connections'
    ],
    'conpot': ['conpot.events'],
    'snort': ['snort.alerts'],
    'kippo': ['kippo.sessions'],
    'cowrie': ['cowrie.sessions'],
    'thug': ['thug.files', 'thug.events'],
    'glastopf': ['glastopf.files', 'glastopf.events'],
    'amun': ['amun.events'],
    'wordpot': ['wordpot.events'],
    'shockpot': ['shockpot.events'],
    'p0f': ['p0f.events'],
    'suricata': ['suricata.events'],
    'elastichoney': ['elastichoney.events'],
    'drupot': ['drupot.events'],
    'agave': ['agave.events'],
}
