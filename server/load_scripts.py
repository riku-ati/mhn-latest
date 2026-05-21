#!/usr/bin/env python3
"""
Populate DeployScript records from the bundled /scripts/ directory.
Safe to run on an existing DB — skips scripts already present by name.
Does NOT touch rules, users, or any other data.
"""
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

with mhn.app_context():
    scripts_dir = mhn.config.get('SCRIPTS_DIR', '/scripts')
    print(f"Scripts directory: {scripts_dir}")

    superuser = User.query.first()
    if not superuser:
        print("ERROR: No users found — run initdatabase.py first.")
        exit(1)

    loaded = skipped = missing = 0
    for name, filename in DEPLOY_SCRIPTS:
        deploy_abs = path.join(scripts_dir, filename)

        if not path.exists(deploy_abs):
            print(f"  MISSING  {deploy_abs}")
            missing += 1
            continue

        if DeployScript.query.filter_by(name=name).first():
            print(f"  EXISTS   {name}")
            skipped += 1
            continue

        with open(deploy_abs, 'r') as f:
            script_text = f.read()

        ds = DeployScript()
        ds.name = name
        ds.script = script_text
        ds.notes = f'Deploy script for {name}'
        ds.user = superuser
        db.session.add(ds)
        print(f"  LOADED   {name}")
        loaded += 1

    db.session.commit()
    print(f"\nDone — {loaded} loaded, {skipped} already existed, {missing} files missing.")
