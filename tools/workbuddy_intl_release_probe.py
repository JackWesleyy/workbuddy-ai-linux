#!/usr/bin/env python3
"""Read-only probe for Tencent WorkBuddy AI international update feeds.

This file does not install software, modify applications, or download binaries.
It only GETs published version metadata and reports relevant fields.
"""
import argparse
import json
import sys
import urllib.error
import urllib.request
from urllib.parse import urlsplit

HOST = 'https://www.workbuddy.ai/v2/update?platform='
CHANNELS = {
    'linux-deb': 'workbuddy-linux-x64-deb',
    'linux-rpm': 'workbuddy-linux-x64-rpm',
    'mac-x64': 'workbuddy-darwin-x64',
}


def find_fields(obj):
    keys = {'version','name','notes','url','sha256hash','sha256','build','buildid','platform'}
    if isinstance(obj, dict):
        for key, value in obj.items():
            if key.lower() in keys and isinstance(value, (str, int, float)):
                if key.lower() == 'url':
                    parts = urlsplit(str(value))
                    if parts.scheme not in ('http','https'):
                        print(f'  {key}: [unexpected URL scheme]')
                        continue
                    host = parts.hostname or '[unknown host]'
                    if parts.port:
                        host += f':{parts.port}'
                    print(f'  {key}: {parts.scheme}://{host}/[path and query omitted]')
                    continue
                print(f'  {key}: {value}')
        for key, value in obj.items():
            if isinstance(value, (dict, list)):
                find_fields(value)
    elif isinstance(obj, list):
        for item in obj[:4]:
            find_fields(item)


def run(channel, timeout):
    url = HOST + CHANNELS[channel]
    print(f'\n=== {channel} ===\nUpdate API: {url}')
    req = urllib.request.Request(url, headers={
        'User-Agent': 'Mozilla/5.0 WorkBuddy-Release-Probe/1.0',
        'Accept': 'application/json, text/plain, */*',
    })
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            data = response.read(300000)
            code = response.status
            content_type = response.headers.get('Content-Type', '')
            print(f'HTTP: {code}  Content-Type: {content_type}')
    except (urllib.error.URLError, TimeoutError, OSError) as err:
        print(f'Unavailable: {type(err).__name__}: {err}')
        return False
    try:
        obj = json.loads(data)
    except (ValueError, UnicodeError):
        print('Not a JSON feed. First 200 chars (sanitized):')
        print(repr(data[:200].decode('utf-8', 'replace')))
        return False
    if isinstance(obj, dict):
        if obj.get('error') or obj.get('message'):
            print('Service response:', str(obj.get('error') or obj.get('message'))[:180])
        print('Top-level keys:', ', '.join(map(str, obj.keys())))
    else:
        print('JSON type:', type(obj).__name__)
    find_fields(obj)
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--timeout', type=int, default=15)
    parser.add_argument('--channel', choices=[*CHANNELS, 'all'], default='all')
    args = parser.parse_args()
    chosen = CHANNELS if args.channel == 'all' else [args.channel]
    good = 0
    for c in chosen:
        good += bool(run(c, args.timeout))
    print('\nIMPORTANT: Linux feed availability and binary authenticity are NOT proven by version alone.')
    print('Do not publish authentication credentials or download/install a package from an unverified URL.')
    return 0 if good else 1

if __name__ == '__main__':
    sys.exit(main())
