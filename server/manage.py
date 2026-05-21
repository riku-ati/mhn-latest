#!/usr/bin/env python3
import os
from urllib.parse import urlparse

try:
    import config
except ImportError:
    print('It seems like this is the first time running the server.')
    print('First let us generate a proper configuration file.')
    try:
        from generateconfig import generate_config
        generate_config()
        import config
        from app import create_clean_db
        print('Initializing database "{}".'.format(config.SQLALCHEMY_DATABASE_URI))
        create_clean_db()
    except Exception as e:
        print(e)
        print('An error occurred. Please fix the errors and try again.')
        print('Deleting "config.py" file.')
        try:
            os.remove('config.py')
        except FileNotFoundError:
            pass
        finally:
            raise SystemExit('Exiting now.')

from app import mhn, db
from app.tasks.rules import fetch_sources


def run():
    """Run server with celery workers."""
    serverurl = urlparse(config.SERVER_BASE_URL)
    port = serverurl.port or 8000
    os.system('celery -A app.tasks --config=config beat &')
    os.system('celery -A app.tasks --config=config worker &')
    mhn.run(debug=config.DEBUG, host='0.0.0.0', port=port)


def runlocal():
    """Run server locally without celery."""
    serverurl = urlparse(config.SERVER_BASE_URL)
    port = serverurl.port or 8000
    mhn.run(debug=config.DEBUG, host='0.0.0.0', port=port)


def fetch_rules():
    """Fetch and import snort rules from configured sources."""
    fetch_sources()


if __name__ == '__main__':
    import sys
    commands = {
        'run': run,
        'runlocal': runlocal,
        'fetch_rules': fetch_rules,
    }
    if len(sys.argv) < 2 or sys.argv[1] not in commands:
        print('Usage: manage.py <command>')
        print('Commands: {}'.format(', '.join(commands.keys())))
        sys.exit(1)
    commands[sys.argv[1]]()
