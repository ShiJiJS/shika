"""Offline consistency check of recorded fixture facts, not a new device test."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def read(name):
    return json.loads((ROOT / name).read_text())


def same(before, after):
    a, b = read(before + '-all-catalog.json'), read(after + '-all-catalog.json')
    assert len(a['tables']) == len(b['tables']) == 35
    for key in ['tables', 'opaque_table_digests', 'setting_key_sha256']:
        assert a[key] == b[key], (before, after, key)


for before, after in [
    ('before-navigation', 'after-navigation'),
    ('before-confirm-cancel', 'after-confirm-cancel'),
    ('before-default-cancel', 'after-default-cancel'),
    ('before-cold-starts', 'after-cold-starts'),
    ('before-rollback23', 'after-rollback23'),
    ('after-rollback23', 'after-forward23'),
]:
    same(before, after)

nav = read('navigation-checks.json')
assert len(nav) == 15
assert sum(x['back'] == 'edge gesture' for x in nav) == 5
assert all(x['returns'] == ['settings', 'library'] and not x['old_browse_visible'] for x in nav)
cover = read('cover-install.json')
assert cover['before']['versionCode'].split()[0] == '5'
assert cover['after']['versionCode'].split()[0] == '23'
assert cover['device_apk_sha256'] == '2e7b2d7079894e4b27cbd36327a31e9307acadcd0ed9c119159802f062244e89'
assert read('media-before.json') == read('media-after.json')
assert len(read('media-after.json')) == 13
for key in ['firstInstallTime', 'dataDir', 'appId']:
    assert cover['before'][key] == cover['after'][key]
for cycle in read('cover-cycle-checks.json')['cycles']:
    for key in ['firstInstallTime', 'dataDir', 'appId']:
        assert cycle['before'][key] == cycle['after'][key]
    assert cycle['after']['versionCode'].split()[0] == '23'
for name in ['before-rollback23', 'after-rollback23', 'after-forward23']:
    assert read(name + '-preferences.json') == {'file_absent': True}
for start in read('cold-start-checks.json')['starts']:
    assert start['previous_pid'] != start['new_pid']
    assert start['library'] and not start['password_prompt']

# The action verifier checks the allowed target generation/tasks/trash changes
# and the exact last-delete pointer; it reads recorded snapshots only.
exec(compile((ROOT / 'verify-trash-undo.py').read_text(), 'verify-trash-undo.py', 'exec'))
print('Recorded snapshot/package/media/navigation consistency: PASS. Device execution is historical.')
