import os
import socket
import struct

import requests
from flask import current_app as app
try:
    from cachelib import SimpleCache
except ImportError:
    from werkzeug.contrib.cache import SimpleCache

from app.ui import constants
from app.api.models import Sensor

try:
    import geoip2.database
    _geoip2_available = True
except ImportError:
    _geoip2_available = False

flag_cache = SimpleCache(threshold=1000, default_timeout=300)
sensor_cache = SimpleCache(threshold=1000, default_timeout=300)

_geoip2_reader = None


def _get_geoip2_reader():
    global _geoip2_reader
    if _geoip2_reader is None and _geoip2_available:
        try:
            import config
            mmdb_path = os.path.join(config.MHN_SERVER_HOME, '../../GeoLite2-City.mmdb')
            if os.path.exists(mmdb_path):
                _geoip2_reader = geoip2.database.Reader(mmdb_path)
        except Exception:
            pass
    return _geoip2_reader


def is_RFC1918_addr(ip):
    # 10.0.0.0 = 167772160
    # 172.16.0.0 = 2886729728
    # 192.168.0.0 = 3232235520
    RFC1918_net_bits = ((167772160, 8), (2886729728, 12), (3232235520, 16))

    try:
        # ip to decimal
        ip_int = struct.unpack("!L", socket.inet_aton(ip))[0]

        for net, mask_bits in RFC1918_net_bits:
            ip_masked = ip_int & (2 ** 32 - 1 << (32 - mask_bits))
            if ip_masked == net:
                return True
    except Exception as e:
        app.logger.error('Error ({}) on is_RFC1918_addr: {}'.format(e, ip))

    return False


def get_flag_ip(ipaddr):
    if not ipaddr:
        return constants.DEFAULT_FLAG_URL
    if is_RFC1918_addr(ipaddr):
        return constants.DEFAULT_FLAG_URL

    flag = flag_cache.get(ipaddr)
    if not flag:
        flag = _get_flag_ip_localdb(ipaddr)
        flag_cache.set(ipaddr, flag)
    return flag


def get_sensor_name(sensor_id):
    sensor_name = sensor_cache.get(sensor_id)
    if not sensor_name:
        for s in Sensor.query:
            if s.uuid == sensor_id:
                sensor_name = s.hostname
                sensor_cache.set(sensor_id, sensor_name)
                break
    return sensor_name


def _get_flag_ip_localdb(ipaddr):
    flag_path = '/static/img/flags-iso/shiny/64/{}.png'
    reader = _get_geoip2_reader()
    if reader is None:
        return constants.DEFAULT_FLAG_URL
    try:
        import config
        r = reader.city(ipaddr)
        ccode = r.country.iso_code
    except Exception:
        app.logger.warning("Could not determine flag for ip (LOCALDB): {}".format(ipaddr))
        return constants.DEFAULT_FLAG_URL
    else:
        # Constructs the flag source using country code
        flag = flag_path.format(ccode.upper())
        try:
            import config
            mhn_home = config.MHN_SERVER_HOME
        except Exception:
            mhn_home = ''
        if os.path.exists(os.path.join(mhn_home, 'app' + flag)):
            return flag
        else:
            return constants.DEFAULT_FLAG_URL


def _get_flag_ip_remote(ipaddr):
    """
    Returns a static address where the flag is located.
    Defaults to static image: '/static/img/unknown.png'
    Uses remote geolocation API.
    """
    flag_path = '/static/img/flags-iso/shiny/64/{}.png'
    geo_api = 'https://geospray.threatstream.com/ip/{}'
    try:
        r = requests.get(geo_api.format(ipaddr))
        ccode = r.json()['countryCode']
    except Exception:
        app.logger.warning("Could not determine flag for ip: {}".format(ipaddr))
        return constants.DEFAULT_FLAG_URL
    else:
        flag = flag_path.format(ccode.upper())
        try:
            import config
            mhn_home = config.MHN_SERVER_HOME
        except Exception:
            mhn_home = ''
        if os.path.exists(os.path.join(mhn_home, 'app' + flag)):
            return flag
        else:
            return constants.DEFAULT_FLAG_URL
