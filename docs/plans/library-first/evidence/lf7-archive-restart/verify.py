"""Independently check fixed-source native process and read-only evidence."""
import hashlib
import json
from pathlib import Path
import subprocess

folder = Path(__file__).resolve().parent
root = folder.parents[4]
source = json.loads((folder / 'source.json').read_text())
manifest = json.loads((folder / 'manifest.json').read_text())
for name, digest in manifest['inputs'].items():
    assert hashlib.sha256((folder / name).read_bytes()).hexdigest() == digest, name
    tracked = subprocess.check_output(['git', 'ls-files', '--error-unmatch', str((folder / name).relative_to(root))], cwd=root)
    assert tracked
for name, digest in source['files'].items():
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == digest, name
    raw = subprocess.check_output(['git', 'show', source['commit'] + ':' + name], cwd=root)
    assert hashlib.sha256(raw).hexdigest() == digest, name
for name, digest in source['production_trees'].items():
    for ref in (source['commit'], source['base'], 'HEAD'):
        actual = subprocess.check_output(['git', 'rev-parse', ref + ':' + name], cwd=root, text=True).strip()
        assert actual == digest, (ref, name)
for ref in ('HEAD', source['commit'], 'design-lf-2026-10-23'):
    actual = subprocess.check_output(['git', 'rev-parse', ref + ':design/reference/library-first'], cwd=root, text=True).strip()
    assert actual == '1cbf605af8f03fa067a4ce8e914bb809e3a487ca'
assert 'No issues found!' in (folder / 'analyze.log').read_text()
assert '24 passed, 1 warning' in (folder / 'server-targeted.log').read_text()
assert (folder / 'ruff.log').read_text().strip() == 'All checks passed!'
assert 'Python syntax: 2 files passed' in (folder / 'compile.log').read_text()
phases = ['snapshot_written', 'after_replace_before_commit', 'restore_committed']
summary = []
for n, phase in enumerate(phases, 1):
    base = folder / f'round-{n}'
    read = lambda name: json.loads((base / name).read_text())
    result, events = read('result.json'), read('events.json')
    assert result['source'] == source['commit'] and result['source_files'] == source['files']
    assert result['phase'] == phase
    assert result['viewport'] == ([360, 740] if n == 1 else [390, 844])
    assert result['scale'] == (2 if n == 1 else 1)
    assert not events['errors'] and events['events'] == result['events']
    assert events['restored_viewport'] == {'size':'Physical size: 1080x2400', 'density':'Physical density: 420'}
    assert events['font_scale'] == '1.0'
    rows = events['events']
    named = {v['event']: v for v in rows if v['event'] not in ('runner', 'screenshot')}
    stop, done, reopen = [named[v] for v in ('force-stop', 'restore-completed', 'new-process')]
    assert stop['old_pid'] == reopen['old_pid'] and reopen['new_pid'] != stop['old_pid']
    assert stop['absent'] and done['absent'] and stop['old_pid'] and reopen['new_pid']
    assert rows.index(stop) < rows.index(done) < rows.index(reopen)
    runners = [v for v in rows if v['event'] == 'runner']
    assert [(v['phase'],v['intentional_stop']) for v in runners] == [(0,True),(1,False)]
    assert runners[0]['exit_code'] != 0 and runners[1]['exit_code'] == 0
    assert 'All tests passed!' in (base / 'phase-1.log').read_text()
    assert 'ARCHIVE_RESTART_STOP_READY:' in (base / 'phase-0.log').read_text()
    original, completed = read('before-stop-status.json'), read('completed-while-absent.json')
    verified = result['verified']
    assert original['armed'] == phase and original['hit'] == phase and original['response_held']
    assert original['request_id'] == stop['request_id'] == verified['request_id']
    assert original['task_id'] == original['original_task_id'] == completed['task']['id'] == done['task_id'] == verified['restore_id']
    assert completed['task']['status'] == 'completed' and completed['task']['error'] is None
    assert completed['task']['result']['restored'] is True
    assert completed['task']['result']['historical_operations_replayed'] == 0
    assert len(completed['task']['result']['root_mapping']) == 27
    assert completed['epoch'] == verified['current_epoch'] != verified['original_epoch']
    if n < 3:
        assert original['epoch'] == verified['original_epoch']
    else:
        assert original['epoch'] == verified['current_epoch']
    assert verified['retained_intents'] == 6 and verified['file_bytes'] > 0 and len(verified['file_sha256']) == 64
    assert read('media-before.json') == read('media-after.json')
    assert len(read('media-before.json')) == 2
    trace, resumed = read('requests.json'), read('resumed-requests.json')
    before_resume = read('before-resume-requests.json')
    assert trace == before_resume + resumed
    assert all(v['method'] == 'GET' or (v['method'] == 'POST' and v['path'] == '/api/v1/scan') for v in resumed)
    for path in ('/api/v1/auth/login', '/api/v1/management-backups/restores'):
        assert sum(v['method'] == 'POST' and v['path'] == path for v in trace) == 1
    assert any(v['method'] == 'GET' and v['path'] == '/api/v1/management-backups/requests/restore/' + verified['request_id'] for v in resumed)
    assert len(verified['graphs']) == 2
    assert len({v['id'] for v in verified['graphs']}) == 2
    for graph in verified['graphs']:
        assert any(v['method'] == 'GET' and v['path'] == '/api/v1/management-history/tasks/' + graph['id'] + '/items' and v['query'].get('graph_id') == graph['graph_id'] for v in resumed)
    for name in ('restart-confirmed', 'restart-unknown-before-stop', 'restart-historical-intents', 'restart-original-restore', 'restart-readonly-selection'):
        assert (base / (name + '.png')).read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
        assert any('mCurrentFocus=' in row and 'io.github.shijijs.video_viewer' in row for row in (base / (name + '-window.txt')).read_text().splitlines())
    assert (base / 'snapshot-system-save.png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n')
    assert any('mCurrentFocus=' in row and 'com.google.android.documentsui' in row for row in (base / 'snapshot-system-save-window.txt').read_text().splitlines())
    summary.append({'phase':phase,'elapsed_seconds':result['elapsed_seconds'],'old_pid':stop['old_pid'],'new_pid':reopen['new_pid'],'restore_id':verified['restore_id']})
print(json.dumps({'verified':True,'source':source['commit'],'native_rounds':3,'targeted_server_tests':24,'rounds':summary},ensure_ascii=False,indent=2))
