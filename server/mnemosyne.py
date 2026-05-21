#!/usr/bin/env python3
"""
mnemosyne.py — Lightweight hpfeeds collector for MHN.

Subscribes to the local hpfeeds broker, normalises honeypot events, and
writes them to MongoDB in the schema Clio/MHN expects.

Supported channels: cowrie.sessions, dionaea.connections, glastopf.events,
  kippo.sessions, amun.events, conpot.events, snort.alerts,
  suricata.events, wordpot.events, elastichoney.events, p0f.events

Run: python mnemosyne.py
Env vars:
  HPF_HOST      hpfeeds broker host (default: hpfeeds-broker)
  HPF_PORT      hpfeeds broker port (default: 10000)
  HPF_IDENT     subscriber identity  (default: mnemosyne)
  HPF_SECRET    subscriber secret    (default: mnemosyne-secret)
  MONGODB_HOST  (default: mongodb)
  MONGODB_PORT  (default: 27017)
"""
import os
import sys
import json
import logging
import datetime
import time

import pymongo
import hpfeeds

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(name)s %(levelname)s %(message)s'
)
logger = logging.getLogger('mnemosyne')

HPF_HOST   = os.environ.get('HPF_HOST',   'hpfeeds-broker')
HPF_PORT   = int(os.environ.get('HPF_PORT',   10000))
HPF_IDENT  = os.environ.get('HPF_IDENT',  'mnemosyne')
HPF_SECRET = os.environ.get('HPF_SECRET', 'mnemosyne-secret')

MONGO_HOST = os.environ.get('MONGODB_HOST', 'mongodb')
MONGO_PORT = int(os.environ.get('MONGODB_PORT', 27017))

SUBSCRIBE_CHANNELS = [
    'cowrie.sessions',
    'kippo.sessions',
    'dionaea.connections',
    'dionaea.capture',
    'glastopf.events',
    'amun.events',
    'conpot.events',
    'snort.alerts',
    'suricata.events',
    'wordpot.events',
    'elastichoney.events',
    'p0f.events',
    'shockpot.events',
    'drupot.events',
]


def get_mongo():
    client = pymongo.MongoClient(MONGO_HOST, MONGO_PORT)
    return client.hpfeeds


def ensure_auth_key(db, ident, secret, channels):
    """Ensure the subscriber auth key exists in MongoDB."""
    db.auth_key.update_one(
        {'identifier': ident},
        {'$set': {
            'identifier': ident,
            'secret': secret,
            'publish': [],
            'subscribe': channels,
        }},
        upsert=True
    )
    logger.info('Ensured auth key for %s', ident)


def normalise(identifier, channel, payload):
    """
    Parse a raw hpfeeds payload and return a list of session dicts
    in the schema Clio expects (source_ip, destination_port, honeypot, timestamp…).
    Returns empty list on parse failure.
    """
    if isinstance(payload, bytes):
        payload = payload.decode('utf-8', errors='replace')
    try:
        data = json.loads(payload)
    except Exception:
        logger.warning('Non-JSON payload on %s from %s', channel, identifier)
        return []

    now = datetime.datetime.utcnow()
    sessions = []

    # ── cowrie / kippo SSH honeypots ─────────────────────────────────────────
    if channel in ('cowrie.sessions', 'kippo.sessions'):
        honeypot = 'cowrie' if channel.startswith('cowrie') else 'kippo'
        for rec in (data if isinstance(data, list) else [data]):
            ts_raw = rec.get('startTime') or rec.get('start_time') or str(now)
            try:
                ts = datetime.datetime.fromisoformat(ts_raw.replace('Z', '+00:00'))
            except Exception:
                ts = now
            sessions.append({
                'source_ip':        rec.get('peerIP') or rec.get('src_host', ''),
                'source_port':      rec.get('peerPort') or rec.get('src_port', 0),
                'destination_port': rec.get('hostPort', 22),
                'honeypot':         honeypot,
                'identifier':       identifier,
                'timestamp':        ts,
                'protocol':         'tcp',
            })

    # ── dionaea malware collector ────────────────────────────────────────────
    elif channel in ('dionaea.connections', 'dionaea.capture'):
        for rec in (data if isinstance(data, list) else [data]):
            sessions.append({
                'source_ip':        rec.get('src_host', ''),
                'source_port':      rec.get('src_port', 0),
                'destination_port': rec.get('dst_port', 0),
                'honeypot':         'dionaea',
                'identifier':       identifier,
                'timestamp':        now,
                'protocol':         rec.get('connection', 'tcp'),
            })

    # ── glastopf web honeypot ────────────────────────────────────────────────
    elif channel == 'glastopf.events':
        for rec in (data if isinstance(data, list) else [data]):
            sessions.append({
                'source_ip':        rec.get('source', ['', 0])[0],
                'source_port':      rec.get('source', ['', 0])[1] if len(rec.get('source', [])) > 1 else 0,
                'destination_port': 80,
                'honeypot':         'glastopf',
                'identifier':       identifier,
                'timestamp':        now,
                'protocol':         'tcp',
            })

    # ── conpot ICS honeypot ──────────────────────────────────────────────────
    elif channel == 'conpot.events':
        for rec in (data if isinstance(data, list) else [data]):
            sessions.append({
                'source_ip':        rec.get('remote', ['', 0])[0] if rec.get('remote') else '',
                'source_port':      rec.get('remote', ['', 0])[1] if rec.get('remote') and len(rec['remote']) > 1 else 0,
                'destination_port': rec.get('public_port', 502),
                'honeypot':         'conpot',
                'identifier':       identifier,
                'timestamp':        now,
                'protocol':         'tcp',
            })

    # ── snort / suricata IDS ─────────────────────────────────────────────────
    elif channel in ('snort.alerts', 'suricata.events'):
        honeypot = 'snort' if 'snort' in channel else 'suricata'
        for rec in (data if isinstance(data, list) else [data]):
            sessions.append({
                'source_ip':        rec.get('src_ip', ''),
                'source_port':      rec.get('src_port', 0),
                'destination_port': rec.get('dst_port', 0),
                'honeypot':         honeypot,
                'identifier':       identifier,
                'timestamp':        now,
                'protocol':         rec.get('proto', 'tcp').lower(),
            })

    # ── generic fallback for amun, wordpot, elastichoney, shockpot, p0f, drupot
    else:
        honeypot = channel.split('.')[0]
        for rec in (data if isinstance(data, list) else [data]):
            src = rec.get('source_ip') or rec.get('src_ip') or rec.get('remote_host', '')
            sessions.append({
                'source_ip':        src,
                'source_port':      rec.get('source_port') or rec.get('src_port', 0),
                'destination_port': rec.get('destination_port') or rec.get('dst_port', 0),
                'honeypot':         honeypot,
                'identifier':       identifier,
                'timestamp':        now,
                'protocol':         'tcp',
            })

    return sessions


def run():
    db = get_mongo()
    ensure_auth_key(db, HPF_IDENT, HPF_SECRET, SUBSCRIBE_CHANNELS)

    while True:
        logger.info('Connecting to hpfeeds broker %s:%s as %s', HPF_HOST, HPF_PORT, HPF_IDENT)
        try:
            hpc = hpfeeds.new(HPF_HOST, HPF_PORT, HPF_IDENT, HPF_SECRET)
        except Exception as e:
            logger.error('Connection failed: %s — retrying in 10s', e)
            time.sleep(10)
            continue

        logger.info('Connected: %s', hpc.brokername)

        inserted = [0]

        def on_message(identifier, channel, payload):
            recs = normalise(identifier, channel, payload)
            if recs:
                db.session.insert_many(recs)
                inserted[0] += len(recs)
                logger.info('[%s] %s → %d session(s) stored (total: %d)',
                            channel, identifier, len(recs), inserted[0])

        def on_error(payload):
            logger.error('hpfeeds error: %s', payload)
            hpc.stop()

        hpc.subscribe(SUBSCRIBE_CHANNELS)
        try:
            hpc.run(on_message, on_error)
        except Exception as e:
            logger.error('hpfeeds run error: %s — reconnecting in 10s', e)
            time.sleep(10)
        finally:
            try:
                hpc.close()
            except Exception:
                pass


if __name__ == '__main__':
    run()
