#!/usr/bin/env python3
"""
Populate DeployScript records from the bundled /scripts/ directory.

Usage:
  python load_scripts.py           # skip scripts already present by name
  python load_scripts.py --reload  # overwrite ALL scripts with current file content
"""
import sys
from os import path
from app import mhn, db
from app.api.models import DeployScript
from app.auth.models import User

DEPLOY_SCRIPTS = [
    ['Ubuntu - Cowrie',                  'deploy_cowrie.sh'],
    ['Ubuntu/Raspberry Pi - Dionaea',    'deploy_dionaea.sh'],
    ['Ubuntu - Conpot',                  'deploy_conpot.sh'],
    ['Ubuntu - Glastopf',                'deploy_glastopf.sh'],
    ['Ubuntu - Snort',                   'deploy_snort.sh'],
    ['Ubuntu - Suricata',                'deploy_suricata.sh'],
    ['Ubuntu - ElasticHoney',            'deploy_elastichoney.sh'],
    ['Ubuntu - Amun',                    'deploy_amun.sh'],
    ['Ubuntu - Wordpot',                 'deploy_wordpot.sh'],
    ['Ubuntu - Shockpot',                'deploy_shockpot.sh'],
    ['Ubuntu - Shockpot Sinkhole',       'deploy_shockpot_sinkhole.sh'],
    ['Ubuntu - p0f',                     'deploy_p0f.sh'],
    ['Ubuntu/Raspberry Pi - Drupot',     'deploy_drupot.sh'],
    ['Ubuntu/Raspberry Pi - Magenpot',   'deploy_magenpot.sh'],
]

force_reload = '--reload' in sys.argv

with mhn.app_context():
    scripts_dir = mhn.config.get('SCRIPTS_DIR', '/scripts')
    print(f"Scripts directory: {scripts_dir}")
    if force_reload:
        print("Mode: RELOAD (overwriting existing records)")
    else:
        print("Mode: SKIP existing (use --reload to overwrite)")

    superuser = User.query.first()
    if not superuser:
        print("ERROR: No users found — run initdatabase.py first.")
        sys.exit(1)

    loaded = updated = skipped = missing = 0
    for name, filename in DEPLOY_SCRIPTS:
        deploy_abs = path.join(scripts_dir, filename)

        if not path.exists(deploy_abs):
            print(f"  MISSING  {deploy_abs}")
            missing += 1
            continue

        with open(deploy_abs, 'r') as f:
            script_text = f.read()

        existing = DeployScript.query.filter_by(name=name).first()

        if existing:
            if force_reload:
                existing.script = script_text
                db.session.add(existing)
                print(f"  UPDATED  {name}")
                updated += 1
            else:
                print(f"  EXISTS   {name}")
                skipped += 1
        else:
            ds = DeployScript()
            ds.name = name
            ds.script = script_text
            ds.notes = f'Deploy script for {name}'
            ds.user = superuser
            db.session.add(ds)
            print(f"  LOADED   {name}")
            loaded += 1

    db.session.commit()
    print(f"\nDone — {loaded} loaded, {updated} updated, {skipped} skipped, {missing} files missing.")
