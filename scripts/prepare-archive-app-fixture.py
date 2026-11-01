#!/usr/bin/env python3
"""Seed only the dedicated 8762 archive App fixture through public endpoints."""
import json
import time
import urllib.request
from pathlib import Path

BASE = 'http://127.0.0.1:8762'
headers = {'Content-Type': 'application/json'}
def call(path, method='GET', body=None):
    request = urllib.request.Request(BASE + path, data=None if body is None else json.dumps(body).encode(), headers=headers, method=method)
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)
login = call('/api/v1/auth/login', 'POST', {'passphrase': 'archive-app-isolated-only'})
headers['Authorization'] = 'Bearer ' + login['access_token']
info = call('/api/v1/info')
headers['X-Management-Epoch'] = info['management_epoch']
call('/api/v1/roots/packs', 'PUT', {'name':'图包测试目录', 'path':'/media/packs', 'kind':'pack'})
for n in range(25):
    call('/api/v1/roots', 'POST', {'name':f'分页目录{n:02d}', 'path':f'/media/videos/目录{n:02d}', 'kind':'pack' if n % 2 else 'video', 'enabled': n % 3 != 0})
for path, name in (('tags','视频独立标签'), ('pack-tags','图包独立标签')):
    call('/api/v1/' + path, 'POST', {'name':name, 'request_id':'archive-initial-' + path})
job = call('/api/v1/scans', 'POST', {})
for _ in range(100):
    job = call('/api/v1/tasks/' + job['id'])
    if job['status'] in ('completed', 'failed'): break
    time.sleep(.1)
assert job['status'] == 'completed', job
proof = {'roots':len(call('/api/v1/roots')['items']), 'packs':call('/api/v1/packs')['total'], 'max_bytes':info['management_backups']['max_bytes']}
assert proof['roots'] == 27 and proof['packs'] == 1, proof
Path('/tmp/lf7-archive-fixture-prepared.json').write_text(json.dumps(proof, indent=2)+'\n')
print(json.dumps(proof))
