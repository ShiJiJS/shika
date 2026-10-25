from pathlib import Path
import hashlib
import json

root = Path.cwd()
evidence = root / 'docs/plans/library-first/evidence/lf7-purge-selections'
rounds = json.loads((evidence / 'verification.json').read_text())
assert len(rounds) == 3 and all(row['exit_code'] == 0 for row in rounds)
proof = []
for row in rounds:
    directory = evidence / f"round-{row['round']}"
    events = json.loads((directory / 'lf6-purge-host-events.json').read_text())
    assert not events['errors']
    snapshots = {}
    traces = {}
    phases = ['selected', 'review', 'files', 'saved', 'saved-reopened',
              'unknown', 'result', 'finished']
    for phase in phases:
        snapshots[phase] = json.loads((directory / f'lf6-purge-purge-{phase}-files.json').read_text())['hashes']
        traces[phase] = json.loads((directory / f'lf6-purge-purge-{phase}-requests.json').read_text())['items']
        assert (directory / f'lf6-purge-purge-{phase}.png').is_file()
    original = snapshots['selected']
    assert len(original) == 108
    assert all(snapshots[phase] == original for phase in phases[:5])
    assert len(snapshots['unknown']) == len(snapshots['result']) == 106
    assert snapshots['unknown'] == snapshots['result']
    assert len(snapshots['finished']) == 105
    assert all(original[path] == sha for snapshot in snapshots.values() for path, sha in snapshot.items())
    notes = {path: sha for path, sha in original.items() if path.endswith('notes.txt')}
    assert len(notes) == 27
    assert all(snapshots['finished'].get(path) == sha for path, sha in notes.items())
    posts = lambda phase: [entry for entry in traces[phase] if entry['method'] == 'POST']
    assert posts('files') == posts('saved') == posts('saved-reopened')
    final = traces['finished']
    physical = [entry for entry in posts('finished') if entry['path'] == '/api/v1/pack-trash/permanent']
    preparations = [entry for entry in posts('finished') if entry['path'] == '/api/v1/pack-purge-plans']
    retries = [entry for entry in posts('finished') if entry['path'].endswith('/retry')]
    assert len(physical) == len(retries) == 1 and len(preparations) == 2
    assert physical[0]['status'] == preparations[0]['status'] == 503
    assert preparations[1]['status'] == retries[0]['status'] == 202
    assert all(entry['authenticated'] or entry['path'] == '/api/v1/auth/login' for entry in final)
    assert 'All tests passed!' in (directory / 'lf6-purge-android-test.log').read_text()
    proof.append({'round': row['round'], 'saved_choice_unchanged_files': 108,
                  'saved_open_added_posts': 0, 'preparation_posts': 2,
                  'physical_posts': 1, 'explicit_original_retries': 1,
                  'partial_remaining_files': 106, 'final_remaining_files': 105,
                  'retained_attachments': 27})
manifest = json.loads((evidence / 'source-sha256.json').read_text())
assert all(hashlib.sha256((root / path).read_bytes()).hexdigest() == sha
           for path, sha in manifest['files'].items())
(evidence / 'proof.json').write_text(json.dumps(proof, indent=2) + '\n')
print('PASS three native rounds: saved/reopened choices add no POST; exact partial/final hashes and original retry verified')
