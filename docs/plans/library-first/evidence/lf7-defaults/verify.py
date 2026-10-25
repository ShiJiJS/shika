"""Independently check final native traces and file/source hashes."""
from pathlib import Path
import hashlib
import json

root = Path.cwd()
evidence = root / 'docs/plans/library-first/evidence/lf7-defaults'
rounds = json.loads((evidence / 'verification.json').read_text())
assert len(rounds) == 3 and all(r['exit_code'] == 0 for r in rounds)
proof = []
phases = ['migration', 'video', 'reader', 'unknown', 'reopened']
for r in rounds:
    folder = evidence / f"round-{r['round']}"
    events = json.loads((folder / 'lf7-defaults-host-events.json').read_text())
    assert not events['errors']
    actual_phases = [e['phase'] for e in events['events']]
    assert all('defaults-' + p in actual_phases for p in phases)
    files, traces = {}, {}
    for phase in phases:
        base = folder / f'lf7-defaults-defaults-{phase}'
        assert base.with_suffix('.png').is_file()
        files[phase] = json.loads(Path(str(base) + '-files.json').read_text())['hashes']
        traces[phase] = json.loads(Path(str(base) + '-requests.json').read_text())['items']
    assert len(files['migration']) == 81
    assert all(value == files['migration'] for value in files.values())
    assert not any(e['method'] == 'PATCH' for e in traces['migration'])
    # The reader draft/cancel/open flow has still not sent reader defaults.
    assert not any(e['method'] == 'PATCH' and e['path'] == '/api/v1/reading-defaults'
                   for e in traces['reader'])
    trace = traces['reopened']
    assert all(e['authenticated'] for e in trace)
    changes = [e for e in trace if e['method'] == 'PATCH']
    assert len(changes) == 2
    video = next(e for e in changes if e['path'] == '/api/v1/playback-defaults')
    reader = next(e for e in changes if e['path'] == '/api/v1/reading-defaults')
    assert video['status'] == 200 and reader['status'] == 503
    receipts = [e for e in trace if '/pack-reading-requests/defaults/' in e['path']]
    assert len(receipts) == 1 and receipts[0]['method'] == 'GET'
    assert hashlib.sha256(receipts[0]['path'].split('/')[-1].encode()).hexdigest() == reader['command_hash']
    posts = [e for e in trace if e['method'] == 'POST']
    assert len(posts) == 1 and posts[0]['path'] == '/api/v1/pack-sessions'
    assert not any(e['method'] != 'GET' and '/rounds' in e['path'] for e in trace)
    log = (folder / 'lf7-defaults-android-test.log').read_text()
    assert 'All tests passed!' in log
    marker = next(line.split('VV_DEFAULTS_PROOF ', 1)[1] for line in log.splitlines()
                  if 'VV_DEFAULTS_PROOF ' in line)
    check = json.loads(marker)
    assert check == {'patches': 2, 'old_pack_preserved': True, 'unread_pack_inherits': True,
                     'current_video_range_preserved': True, 'local_migration_reopened': True}
    proof.append({'round': r['round'], 'unchanged_images': 81, 'default_writes': 2,
                  'reader_receipt_gets': 1, 'active_video_mutations': 0,
                  'app_assertions': check})
source = json.loads((evidence / 'source-sha256.json').read_text())
assert all(hashlib.sha256((root / p).read_bytes()).hexdigest() == sha
           for p, sha in source['files'].items())
(evidence / 'proof.json').write_text(json.dumps(proof, indent=2) + '\n')
print('PASS three native defaults rounds: two explicit writes, one original receipt, 81 images unchanged')
