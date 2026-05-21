# MHN Latest — Modern Honey Network (Python 3)

A Python 3 port of the Modern Honey Network (MHN) honeypot management platform, featuring a modernised dark SOC dashboard UI, updated dependencies, and full Docker support.

---

## What's New

| Feature | Original MHN | MHN Latest |
|---------|-------------|------------|
| Python version | Python 2.7 | Python 3.11 |
| Flask | 0.x | 2.3.x |
| pymongo | 2.x | 4.6.x |
| Atom feed | werkzeug.contrib.atom | feedgen 0.9.x |
| Auth | Flask-Security | Flask-Security-Too 5.x |
| Dashboard UI | Legacy light theme | Modern dark SOC theme |
| Deployment | Manual bash scripts | Docker + docker-compose |
| Celery broker | - | Redis 7 |

---

## Quick Start

### Docker (recommended)

```bash
# 1. Clone and enter the directory
git clone <repo-url> mhn-latest
cd mhn-latest

# 2. Copy and edit the environment file
cp .env.example .env
# Edit .env — at minimum set SECRET_KEY and SUPERUSER_PASSWORD

# 3. Build and start all services
docker-compose up -d

# 4. Initialise the database (first run only)
docker-compose exec mhn python initdatabase.py

# 5. Open the dashboard
open http://localhost:8080
```

### Manual Setup

```bash
# Prerequisites: Python 3.11+, MongoDB 6.0+, Redis 7+

# 1. Create a virtual environment
python3 -m venv venv
source venv/bin/activate

# 2. Install dependencies
pip install -r server/requirements.txt

# 3. Configure the application
cp server/config.py.template server/config.py
# Edit server/config.py with your settings

# 4. Initialise the database
cd server
python initdatabase.py

# 5. Start the application
gunicorn --bind 0.0.0.0:8080 --workers 4 mhn:app

# 6. (Optional) Start the Celery worker for rule fetching
celery -A app.tasks worker --loglevel=info
```

---

## Architecture

```
mhn-latest/
├── Dockerfile                  # Python 3.11 slim container
├── docker-compose.yml          # MHN + MongoDB + Redis + Celery
├── .env.example                # Environment variable template
├── README.md                   # This file
├── scripts/                    # Honeypot deploy scripts (bash)
│   ├── deploy_cowrie.sh
│   ├── deploy_dionaea.sh
│   ├── deploy_snort.sh
│   ├── deploy_suricata.sh
│   ├── deploy_glastopf.sh
│   ├── deploy_conpot.sh
│   ├── deploy_kippo.sh
│   ├── deploy_wordpot.sh
│   ├── deploy_shockpot.sh
│   ├── deploy_p0f.sh
│   ├── install_mhnserver.sh
│   └── ...
└── server/
    ├── requirements.txt        # Python 3 dependencies
    ├── mhn.py                  # WSGI entry point
    ├── manage.py               # Flask-Migrate CLI
    ├── initdatabase.py         # DB init script
    ├── collector.py            # hpfeeds community relay (Python 3)
    ├── collector_v2.py         # hpfeeds v2 collector (Python 3)
    ├── config.py.template      # Configuration template
    └── app/
        ├── __init__.py         # App factory, blueprints, feed routes
        ├── constants.py        # Shared constants (PAGE_SIZE, etc.)
        ├── api/                # REST API blueprint
        │   ├── views.py        # Sensor, session, rule, feed endpoints
        │   └── models.py       # SQLAlchemy models
        ├── auth/               # Authentication blueprint
        │   ├── views.py        # Login, logout, password reset
        │   └── models.py       # User, Role, ApiKey models
        ├── common/             # Shared utilities
        │   ├── clio.py         # MongoDB/Mnemosyne client
        │   ├── utils.py        # Pagination helpers
        │   ├── ruleutils.py    # Snort rule parser
        │   ├── templatetags.py # Jinja2 filters
        │   └── contextprocessors.py
        ├── tasks/              # Celery tasks
        │   ├── __init__.py     # Celery app setup
        │   └── rules.py        # Rule fetch + render tasks
        ├── ui/                 # UI blueprint
        │   ├── views.py        # Dashboard, attacks, feeds, sensors, rules
        │   ├── utils.py        # GeoIP flag lookup, sensor name cache
        │   └── constants.py    # UI constants
        ├── static/             # CSS, JS, images
        └── templates/          # Jinja2 HTML templates
            ├── base.html       # Dark SOC layout base
            ├── ui/             # Dashboard, attacks, feeds, etc.
            └── security/       # Login, password pages
```

---

## Supported Honeypots

| Honeypot | Protocol | Channel |
|----------|----------|---------|
| Cowrie | SSH/Telnet | `cowrie.sessions` |
| Dionaea | Multi-protocol | `dionaea.capture`, `dionaea.connections` |
| Glastopf | HTTP | `glastopf.events` |
| Snort | IDS/Network | `snort.alerts` |
| Suricata | IDS/Network | `suricata.events` |
| Conpot | ICS/SCADA | `conpot.events` |
| Kippo | SSH | `kippo.sessions` |
| Wordpot | HTTP/WordPress | `wordpot.events` |
| Shockpot | HTTP/ShellShock | `shockpot.events` |
| p0f | Passive OS FP | `p0f.events` |
| ElasticHoney | Elasticsearch | `elastichoney.events` |
| Amun | Multi-exploit | `amun.events` |
| Drupot | HTTP/Drupal | `drupot.events` |

---

## API Usage

### Authentication

```bash
# Get your API key from the dashboard Settings page, then:
export API_KEY=<your-api-key>
```

### List Sensors

```bash
curl -H "Authorization: Token $API_KEY" http://localhost:8080/api/sensors/
```

### List Sessions (attacks)

```bash
# All sessions
curl -H "Authorization: Token $API_KEY" http://localhost:8080/api/sessions/

# Filter by source IP
curl -H "Authorization: Token $API_KEY" \
  "http://localhost:8080/api/sessions/?source_ip=1.2.3.4"

# Filter by honeypot type
curl -H "Authorization: Token $API_KEY" \
  "http://localhost:8080/api/sessions/?honeypot=cowrie"

# Last 24 hours
curl -H "Authorization: Token $API_KEY" \
  "http://localhost:8080/api/sessions/?hours_ago=24"
```

### Register a Sensor

```bash
curl -X POST \
  -H "Authorization: Token $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"hostname": "sensor-01", "ip": "10.0.0.5"}' \
  http://localhost:8080/api/sensor/
```

### Atom/JSON Feed

```bash
# Atom XML feed
curl http://localhost:8080/feed.xml

# JSON feed
curl http://localhost:8080/feed.json
```

### Snort Rules

```bash
# Rendered rules file (for Snort/Suricata)
curl http://localhost:8080/api/rules.txt

# Rule list (JSON)
curl -H "Authorization: Token $API_KEY" http://localhost:8080/api/rules/
```

---

## Python 2 to Python 3 Migration Notes

| Change | Python 2 (original) | Python 3 (this port) |
|--------|---------------------|----------------------|
| Print statement | `print x` | `print(x)` |
| String types | `basestring`, `unicode` | `str` |
| Dict iteration | `.iteritems()`, `.itervalues()` | `.items()`, `.values()` |
| File open | `file(path)` | `open(path)` |
| Integer division | implicit float | explicit `float()` cast |
| StringIO | `from StringIO import StringIO` | `from io import BytesIO` |
| pymongo aggregate | returns `{'ok':1,'result':[...]}` | returns cursor directly |
| pymongo insert | `collection.insert(doc)` | `collection.insert_one(doc)` |
| pymongo remove | `collection.remove(q)` | `collection.delete_many(q)` |
| pymongo count | `collection.find(q).count()` | `collection.count_documents(q)` |
| pymongo update | `collection.update(q, u)` | `collection.update_many(q, u)` |
| pymongo fsync | `client.fsync()` | removed (deprecated) |
| Werkzeug cache | `werkzeug.contrib.cache` | `cachelib.SimpleCache` |
| Atom feed | `werkzeug.contrib.atom` | `feedgen` |
| xrange | `xrange(n)` | `range(n)` |

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SECRET_KEY` | (required) | Flask secret key for sessions |
| `DEBUG` | `false` | Enable Flask debug mode |
| `SQLALCHEMY_DATABASE_URI` | `sqlite:///mhn.db` | SQL database URL |
| `MONGODB_HOST` | `mongodb` | MongoDB hostname |
| `MONGODB_PORT` | `27017` | MongoDB port |
| `REDIS_URL` | `redis://redis:6379/0` | Redis URL for Celery broker |
| `MAIL_SERVER` | `localhost` | SMTP server |
| `MAIL_PORT` | `25` | SMTP port |
| `MAIL_USE_TLS` | `false` | Enable SMTP TLS |
| `MAIL_USERNAME` | (empty) | SMTP username |
| `MAIL_PASSWORD` | (empty) | SMTP password |
| `MAIL_DEFAULT_SENDER` | `mhn@example.com` | From address |
| `SUPERUSER_EMAIL` | `admin@example.com` | Initial admin email |
| `SUPERUSER_PASSWORD` | `changeme123` | Initial admin password |
| `FEED_AUTH_REQUIRED` | `true` | Require auth for Atom/JSON feeds |
| `SERVER_BASE_URL` | `http://localhost:8080` | Public base URL |

---

## License

Based on the original Modern Honey Network project by ThreatStream, licensed under the GNU Lesser General Public License v2.1. This Python 3 port maintains the same license terms.
