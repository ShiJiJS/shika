"""Read-only checks of pinned native purge evidence; run at repository root."""

import hashlib
import json
import struct
import subprocess
from pathlib import Path

root = Path.cwd()
evidence = Path(__file__).resolve().parent


def read(path):
    return json.loads(path.read_text())


def sha(data):
    return hashlib.sha256(data).hexdigest()


def source_check(metadata, current=True):
    for path, digest in metadata['files'].items():
        if current:
            assert sha((root / path).read_bytes()) == digest, path
        assert sha(subprocess.check_output(['git', 'show', f"{metadata['commit']}:{path}"])) == digest, path


states = ['video-confirm', 'selected', 'review', 'members', 'files', 'saved', 'saved-dark',
          'saved-reopened', 'unknown', 'result', 'retry-confirm', 'finished']
source = read(evidence / 'source.json')
proof = []
for profile, size, text13 in [('normal', [390, 844], 13), ('large', [360, 740], 26), ('landscape', [844, 390], 13)]:
    folder = evidence / profile
    assert read(folder / 'source.json') == source
    events = read(folder / 'lf8-purge-host-events.json')
    assert not events['errors']
    assert [e['phase'] for e in events['events'] if e['phase'].startswith('purge-ui-')] == ['purge-ui-' + s for s in states]
    log = (folder / 'lf8-purge-android-test.log').read_text()
    assert 'All tests passed!' in log and 'Some tests failed' not in log
    assert 'PURGE_MANAGEMENT_VERIFIED:108 source files, cancelled video and pack confirmation, exact images, one physical POST, one original retry, 105 preserved files including 27 attachments' in log
    metrics = [json.loads(line.split('PURGE_MANAGEMENT_METRICS:', 1)[1]) for line in log.splitlines() if 'PURGE_MANAGEMENT_METRICS:' in line]
    assert [m['state'] for m in metrics] == ['purge-ui-' + s for s in states]
    assert all(m['window'] == size and m['dpr'] == 3 and m['text13'] == text13 for m in metrics)
    assert all(m['dark'] == (m['state'] == 'purge-ui-saved-dark') and m['keyboard'] == 0 for m in metrics)
    traces, files, stats = {}, {}, {}
    for state in states:
        base = folder / ('lf8-purge-purge-ui-' + state)
        png = base.with_suffix('.png').read_bytes()
        assert png[:8] == b'\x89PNG\r\n\x1a\n'
        assert struct.unpack('>II', png[16:24]) == tuple(n * 3 for n in size)
        focus = Path(str(base) + '-window.txt').read_text()
        assert any('mCurrentFocus=' in line and 'io.github.shijijs.video_viewer' in line for line in focus.splitlines())
        assert 'Application Not Responding' not in focus
        traces[state] = read(Path(str(base) + '-requests.json'))['items']
        files[state] = read(Path(str(base) + '-files.json'))['hashes']
        stats[state] = read(Path(str(base) + '-stats.json'))
    original = files['video-confirm']
    assert len(original) == 108
    assert all(files[s] == original and stats[s]['task'] is None for s in states[:8])
    for state in ['unknown', 'result', 'retry-confirm']:
        assert len(files[state]) == 106
    final = files['finished']
    assert len(final) == 105 and all(original[k] == v for k, v in final.items())
    assert len([k for k in final if k.endswith('/notes.txt')]) == 27
    task = stats['finished']['task']
    assert task['status'] == task['phase'] == 'completed'
    assert task['result']['pages_deleted'] == task['result']['pages_total'] == 3
    assert task['result']['failed'] == 0 and task['result']['succeeded'] == 1
    assert task['result']['needs_attention'] is False
    members = stats['finished']['members']
    assert len(members) == 1 and members[0]['images'] == 3 and members[0]['retained'] == 1
    member = members[0]
    folder_name = member['path'].removeprefix('/media/shorts/图包/')
    assert folder_name != member['path']
    manifest = member['manifest']['files']
    expected = {folder_name + '/' + p['relative_path']: p['sha256'] for p in manifest}
    assert len(expected) == 3 and all(original[k] == v for k, v in expected.items())
    assert set(original) - set(final) == set(expected)
    for state in ['unknown', 'result', 'retry-confirm', 'finished']:
        row = stats[state]['task']
        assert row['id'] == task['id'] and row['plan_id'] == task['plan_id']
        assert row['plan_id'] == stats[state]['preview']['id']
        actual = files[state]
        assert all(original[k] == v for k, v in actual.items())
        deleted = {folder_name + '/' + s['relative_path']: s['sha256'] for s in stats[state]['steps'] if s['kind'] == 'image' and s['outcome'] == 'succeeded'}
        assert set(original) - set(actual) == set(deleted)
        assert all(expected[k] == v for k, v in deleted.items())
        assert row['result']['pages_deleted'] == len(deleted)
        assert len(deleted) == (3 if state == 'finished' else 2)
    dirs = [s for s in stats['finished']['steps'] if s['kind'] == 'directory']
    assert dirs and all(s['outcome'] == 'retained' for s in dirs)
    trace = traces['finished']
    assert all(e['authenticated'] or e['path'] in {'/api/v1/auth/login','/api/v1/info'} for e in trace)
    posts = [e for e in trace if e['method'] == 'POST']
    physical = [e for e in posts if e['path'] == '/api/v1/pack-trash/permanent']
    prepares = [e for e in posts if e['path'] == '/api/v1/pack-purge-plans']
    retries = [e for e in posts if e['path'].endswith('/retry')]
    assert len(physical) == len(retries) == 1 and len(prepares) == 2
    assert [e['status'] for e in prepares] == [503, 202] and physical[0]['status'] == 503 and retries[0]['status'] == 202
    assert prepares[0]['purge_members'] == prepares[1]['purge_members'] == [member['trash_id']]
    assert physical[0]['purge_input'] == {'plan_id': task['plan_id'], 'digest': stats['finished']['preview']['digest'], 'confirmed': True}
    assert retries[0]['path'] == '/api/v1/pack-operations/' + task['id'] + '/retry'
    assert not any(e['path'] == '/api/v1/trash/permanent' for e in posts)
    receipt = [e for e in trace if e['method'] == 'GET' and e['path'].startswith('/api/v1/pack-file-requests/') and not e['path'].endswith('native-purge-logical')]
    preview_receipt = [e for e in trace if e['method'] == 'GET' and e['path'].startswith('/api/v1/pack-purge-requests/')]
    assert len(receipt) == len(preview_receipt) == 1
    assert sha(receipt[0]['path'].split('/')[-1].encode()) == physical[0]['command_hash']
    assert sha(preview_receipt[0]['path'].split('/')[-1].encode()) == prepares[0]['command_hash']
    assert not any(e['path'] == '/api/v1/pack-trash/permanent' and e['method'] == 'POST' for e in traces['saved-reopened'])
    saved_posts = [[e for e in traces[s] if e['method'] == 'POST'] for s in ['saved', 'saved-reopened']]
    assert saved_posts[0] == saved_posts[1]
    restored = read(folder / 'restored-viewport.json')
    assert restored['before'] == restored['after'] == {'size': 'Physical size: 1080x2400', 'density': 'Physical density: 420', 'font_scale': '1.0'}
    proof.append({'profile': profile, 'checkpoints': 12, 'physical_posts': 1, 'retry_posts': 1, 'deleted_images': 3, 'preserved_attachments': 27})

source_check(source)
source_check(read(evidence / 'checks/source.json'))
for index in [1, 2, 3]:
    assert '+90: All tests passed!' in (evidence / f'checks/targeted-{index}.log').read_text()
assert 'No issues found!' in (evidence / 'checks/analyze.log').read_text()
assert '0 changed' in (evidence / 'checks/format.log').read_text()
assert 'All checks passed!' in (evidence / 'checks/ruff.log').read_text()
assert source['prototype_tree'] == '1cbf605af8f03fa067a4ce8e914bb809e3a487ca'
assert subprocess.check_output(['git', 'rev-parse', 'HEAD:design/reference/library-first'], text=True).strip() == source['prototype_tree']
for item in read(evidence / 'reference/source-sha256.json')['files']:
    assert sha((root / 'design/reference/library-first' / item['path']).read_bytes()) == item['sha256']
assert read(evidence / 'reference/http-source-sha256.json')['files'] == [dict(item, url='http://127.0.0.1:8767/library-first/' + item['path'], status=200) for item in read(evidence / 'reference/source-sha256.json')['files']]
for name in ['baseline', 'intermediate-before-ink-fix', 'intermediate-before-settled-capture', 'intermediate-large-before-settled-capture', 'intermediate-landscape-before-settled-capture']:
    source_check(read(evidence / name / 'source.json'), current=False)
    assert 'All tests passed!' in (evidence / name / 'lf8-purge-android-test.log').read_text()
    assert len(list((evidence / name).glob('*.png'))) == 12
manifest = read(evidence / 'manifest.json')
actual = {str(p.relative_to(evidence)) for p in evidence.rglob('*') if p.is_file() and p.name not in {'manifest.json', 'verification.json'}}
assert set(manifest) == actual
assert all(sha((evidence / p).read_bytes()) == digest for p, digest in manifest.items())
print(json.dumps({'verified': True, 'source': source['commit'], 'inputs': len(manifest), 'native_checkpoints': 36, 'profiles': proof}, ensure_ascii=False, indent=2))
