"""Independently check saved public HTTP, file, process and native results."""

import hashlib
import json
import re
import struct
import subprocess
from pathlib import Path

BASE = Path(__file__).resolve().parent
ROOT = BASE.parents[4]


def read(path):
    return json.loads(path.read_text())


def verify_round(directory, strong):
    events = read(directory / 'events.json')
    assert not events['watcher_errors']
    assert events['restored_viewport'] == {
        'size': 'Physical size: 1080x2400',
        'density': 'Physical density: 420', 'font_scale': '1.0',
    }
    phases = {v['phase']: v for v in events['events']}
    for phase in ['authority-before', 'authority-history', 'authority-selection', 'authority-current']:
        assert phase in phases
        focus = (directory / f'{phase}-window.txt').read_text()
        assert any('mCurrentFocus=' in line and 'io.github.shijijs.video_viewer' in line for line in focus.splitlines())
        raw = (directory / f'{phase}.png').read_bytes()
        assert raw[:8] == b'\x89PNG\r\n\x1a\n'
        width, height = struct.unpack('>II', raw[16:24])
        viewport = phases['viewport']
        assert (width, height) == (viewport['width_dp'] * 3, viewport['height_dp'] * 3)
    if strong:
        assert phases['verified-force-stop']['absent']
        assert phases['restored-while-absent']['absent']
        process = phases['verified-new-process']
        assert process['old_pid'] and process['new_pid'] and process['old_pid'] != process['new_pid']
        assert phases['runner-0']['intentional_stop']
        assert phases['runner-0']['exit_code'] != 0
        assert phases['runner-1']['exit_code'] == 0
        assert 'All tests passed!' in (directory / 'phase-1.log').read_text()
    else:
        assert phases['runner-0']['exit_code'] == 0
        assert 'All tests passed!' in (directory / 'phase-0.log').read_text()
    stats = read(directory / 'final-stats.json')
    old, new = stats['prepared']['old_epoch'], stats['completed']['new_epoch']
    assert old != new and all(re.fullmatch('[a-f0-9]{32}', value) for value in [old, new])
    assert stats['files'] == stats['prepared']['files'] == stats['completed']['files']
    assert len(stats['files']) == 27
    trace = read(directory / 'final-requests.json')['items']
    assert len(trace) < 2000, 'Trace wrapped; full command proof is unavailable'
    actor = [v for v in trace if v['fixture_actor'] == 'authority-host']
    app = [v for v in trace if v['fixture_actor'] is None]
    restores = [v for v in actor if v['method'] == 'POST' and v['path'] == '/api/v1/backup-restores']
    assert len(restores) == 1 and restores[0]['status'] == 202
    logins = [v for v in app if v['path'] == '/api/v1/auth/login']
    assert len(logins) == 1 and logins[0]['status'] == 200
    assert trace.index(logins[0]) < trace.index(restores[0])
    writes = [v for v in app if v['method'] in {'POST', 'PUT', 'PATCH', 'DELETE'} and v['path'] != '/api/v1/auth/login']
    assert len(writes) == 1
    assert writes[0]['path'] == '/api/v1/backups' and writes[0]['management_epoch'] == new and writes[0]['status'] == 202
    originals = {
        '/api/v1/file-requests/authority-video-old',
        '/api/v1/pack-file-requests/authority-pack-old',
        '/api/v1/pack-restore-requests/authority-plan-old',
        '/api/v1/pack-missing-requests/authority-missing-old',
        '/api/v1/backup-requests/export/authority-export-old',
    }
    for path in originals:
        found = [v for v in app if v['path'] == path]
        assert found and all(v['method'] == 'GET' and v['status'] == 404 and v['management_epoch'] == new for v in found), path
    downloads = [v for v in app if v['path'].endswith('/download')]
    assert len(downloads) == 1 and downloads[0]['status'] == 200 and downloads[0]['management_epoch'] == new
    return {'native_seconds': re.findall(r'(\d\d:\d\d) \+1: All tests passed!', (directory / ('phase-1.log' if strong else 'phase-0.log')).read_text())[-1],
            'strong_stop': strong, 'source_files': len(stats['files']), 'old_receipts_get_only': len(originals),
            'app_logins': len(logins), 'current_export_posts': len(writes), 'requests': len(trace), 'checkpoints': 4}


def main():
    manifest = BASE / 'evidence-sha256.json'
    if manifest.exists():
        for path, expected in read(manifest).items():
            assert hashlib.sha256((BASE / path).read_bytes()).hexdigest() == expected, path
    source = read(BASE / 'source-sha256.json')
    for path, expected in source['files'].items():
        raw = subprocess.check_output(['git', 'show', f"{source['commit']}:{path}"], cwd=ROOT)
        assert hashlib.sha256(raw).hexdigest() == expected, path
    assert '+398: All tests passed!' in (BASE / 'client-full.log').read_text()
    assert 'No issues found!' in (BASE / 'analyze.log').read_text()
    assert 'All checks passed!' in (BASE / 'ruff.log').read_text()
    expected_tree = '1cbf605af8f03fa067a4ce8e914bb809e3a487ca'
    tree = subprocess.check_output(['git', 'rev-parse', f"{source['commit']}:design/reference/library-first"], cwd=ROOT, text=True).strip()
    assert tree == expected_tree
    result = {'source_commit': source['commit'], 'client_tests': 398, 'prototype_tree': tree,
              'rounds': {name: verify_round(BASE / name, strong) for name, strong in [
                  ('round-1-live-390', False), ('round-2-stop-360', True), ('round-3-stop-390', True)]}}
    (BASE / 'proof.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
