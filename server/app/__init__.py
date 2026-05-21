from urllib.parse import urljoin

from flask import Flask, request, jsonify, abort, url_for
from flask_sqlalchemy import SQLAlchemy
from flask_security import Security, SQLAlchemyUserDatastore
from flask_security.utils import hash_password
from flask_mail import Mail
from feedgen.feed import FeedGenerator
import uuid
import random
import string
from flask_wtf.csrf import CSRFProtect

csrf = CSRFProtect()

db = SQLAlchemy()
# After defining `db`, import auth models due to
# circular dependency.
from app.auth.models import User, Role, ApiKey
user_datastore = SQLAlchemyUserDatastore(db, User, Role)


mhn = Flask(__name__)
mhn.config.from_object('config')
csrf.init_app(mhn)

# Email app setup.
mail = Mail()
mail.init_app(mhn)

# Registering app on db instance.
db.init_app(mhn)

# Setup flask-security for auth.
Security(mhn, user_datastore)

# Registering blueprints.
from app.api.views import api
mhn.register_blueprint(api)

from app.ui.views import ui
mhn.register_blueprint(ui)

from app.auth.views import auth
mhn.register_blueprint(auth)

# Trigger templatetag register.
from app.common.templatetags import format_date
mhn.jinja_env.filters['fdate'] = format_date

from app.auth.contextprocessors import user_ctx
mhn.context_processor(user_ctx)

from app.common.contextprocessors import config_ctx
mhn.context_processor(config_ctx)

import logging
from logging.handlers import RotatingFileHandler

mhn.logger.setLevel(logging.INFO)
formatter = logging.Formatter(
      '%(asctime)s -  %(pathname)s - %(message)s')

log_file_path = mhn.config.get('LOG_FILE_PATH', '/var/log/mhn/mhn.log')
try:
    handler = RotatingFileHandler(
            log_file_path, maxBytes=10240, backupCount=5)
    handler.setLevel(logging.INFO)
    handler.setFormatter(formatter)
    mhn.logger.addHandler(handler)
except (IOError, OSError):
    pass

if mhn.config.get('DEBUG'):
    console = logging.StreamHandler()
    console.setLevel(logging.INFO)
    console.setFormatter(formatter)
    mhn.logger.addHandler(console)


@mhn.route('/feed.json')
def json_feed():
    import xmltodict
    fg = get_feed()
    feed_str = fg.atom_str(pretty=True)
    return jsonify(xmltodict.parse(feed_str))


@mhn.route('/feed.xml')
def xml_feed():
    from flask import Response
    fg = get_feed()
    return Response(fg.atom_str(pretty=True), mimetype='application/atom+xml')


def makeurl(uri):
    baseurl = mhn.config['SERVER_BASE_URL']
    return urljoin(baseurl, uri)


def get_feed():
    from app.common.clio import Clio
    from app.auth import current_user
    authfeed = mhn.config.get('FEED_AUTH_REQUIRED', False)
    if authfeed and not current_user.is_authenticated:
        abort(404)

    fg = FeedGenerator()
    fg.id(request.url_root)
    fg.title('MHN HpFeeds Report')
    fg.link(href=request.url, rel='self')
    fg.link(href=request.url_root, rel='alternate')
    fg.language('en')

    sessions = Clio().session.get(options={'limit': 1000})
    for s in sessions:
        feedtext = 'Sensor "{identifier}" '
        feedtext += '{source_ip}:{source_port} on sensorip:{destination_port}.'
        feedtext = feedtext.format(**s.to_dict())
        fe = fg.add_entry()
        session_url = makeurl(url_for('api.get_session', session_id=str(s._id)))
        fe.id(session_url)
        fe.title('Feed')
        fe.link(href=session_url)
        fe.content(feedtext, type='text')
        if s.timestamp:
            import datetime
            ts = s.timestamp
            if isinstance(ts, str):
                from dateutil.parser import parse as parse_date
                ts = parse_date(ts)
            if ts.tzinfo is None:
                import pytz
                ts = pytz.utc.localize(ts)
            fe.published(ts)
            fe.updated(ts)

    return fg


def create_clean_db():
    """
    Use from a python shell to create a fresh database.
    """
    with mhn.test_request_context():
        db.create_all()
        # Creating superuser entry.
        superuser = user_datastore.create_user(
                email=mhn.config.get('SUPERUSER_EMAIL'),
                password=hash_password(mhn.config.get('SUPERUSER_PASSWORD')))
        adminrole = user_datastore.create_role(name='admin', description='')
        user_datastore.add_role_to_user(superuser, adminrole)
        user_datastore.create_role(name='user', description='')
        db.session.flush()

        apikey = ApiKey(user_id=superuser.id, api_key=str(uuid.uuid4()).replace("-", ""))
        db.session.add(apikey)
        db.session.flush()

        from os import path

        from app.api.models import DeployScript, RuleSource
        from app.tasks.rules import fetch_sources
        # Creating initial deploy scripts.
        # Reading initial deploy script should be: ../../scripts/
        # Scripts dir is configured via SCRIPTS_DIR (defaults to /scripts in Docker)
        scripts_dir = mhn.config.get('SCRIPTS_DIR', '/scripts')
        deployscripts = [
            ['Ubuntu - Conpot', 'deploy_conpot.sh'],
            ['Ubuntu/Raspberry Pi - Drupot', 'deploy_drupot.sh'],
            ['Ubuntu/Raspberry Pi - Magenpot', 'deploy_magenpot.sh'],
            ['Ubuntu - Wordpot', 'deploy_wordpot.sh'],
            ['Ubuntu - Shockpot', 'deploy_shockpot.sh'],
            ['Ubuntu - p0f', 'deploy_p0f.sh'],
            ['Ubuntu - Suricata', 'deploy_suricata.sh'],
            ['Ubuntu - Glastopf', 'deploy_glastopf.sh'],
            ['Ubuntu - ElasticHoney', 'deploy_elastichoney.sh'],
            ['Ubuntu - Amun', 'deploy_amun.sh'],
            ['Ubuntu - Snort', 'deploy_snort.sh'],
            ['Ubuntu - Cowrie', 'deploy_cowrie.sh'],
            ['Ubuntu/Raspberry Pi - Dionaea', 'deploy_dionaea.sh'],
            ['Ubuntu - Shockpot Sinkhole', 'deploy_shockpot_sinkhole.sh'],
        ]
        for honeypot, deploypath in reversed(deployscripts):
            deploy_abs = path.join(scripts_dir, deploypath)
            if path.exists(deploy_abs):
                with open(deploy_abs, 'r') as deployfile:
                    initdeploy = DeployScript()
                    initdeploy.script = deployfile.read()
                    initdeploy.notes = 'Initial deploy script for {}'.format(honeypot)
                    initdeploy.user = superuser
                    initdeploy.name = honeypot
                    db.session.add(initdeploy)

        # Creating an initial rule source.
        rules_source = mhn.config.get('SNORT_RULES_SOURCE')
        if not mhn.config.get('TESTING') and rules_source:
            rulesrc = RuleSource()
            rulesrc.name = rules_source['name']
            rulesrc.uri = rules_source['uri']
            rulesrc.name = 'Default rules source'
            db.session.add(rulesrc)
            db.session.commit()
            fetch_sources()
        else:
            db.session.commit()
