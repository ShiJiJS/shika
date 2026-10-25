from pathlib import Path
import hashlib
import json

root = Path.cwd()
evidence = root / 'docs/plans/library-first/evidence/lf7-purge-secure-restart'
rounds = json.loads((evidence / 'verification.json').read_text())
assert len(rounds) == 3 and all(r['exit_code'] == 0 for r in rounds)
proof = []
for r in rounds:
    folder = evidence / f"round-{r['round']}"
    events = json.loads((folder / 'lf7-purge-restart-host-events.json').read_text())
    assert not events['errors']
    by = {e['phase']: e for e in events['events']}
    stopped, absent, reopened = (by[k] for k in (
        'purge-app-force-stopped', 'purge-completed-without-app', 'purge-app-reopened'))
    assert stopped['pid_absent'] and absent['pid_absent']
    assert stopped['pid'] == reopened['old_pid'] != reopened['new_pid']
    assert stopped['time'] < absent['time'] < reopened['time']
    assert by['purge-expected-test-interruption']['runner_exit_code'] != 0
    phases = ['selected', 'review', 'unknown', 'receipt', 'paged', 'selection', 'next-review']
    files, stats, traces = {}, {}, {}
    for phase in phases:
        base = folder / f'lf7-purge-restart-bulk-{phase}'
        files[phase] = json.loads(Path(str(base) + '-files.json').read_text())['hashes']
        stats[phase] = json.loads(Path(str(base) + '-stats.json').read_text())
        traces[phase] = json.loads(Path(str(base) + '-requests.json').read_text())['items']
        assert Path(str(base) + '.png').is_file()
    original = files['selected']
    original_ids = set(stats['selected']['all_trash_ids'])
    assert len(original_ids) == 1003 and len(original) == 2006
    assert stats['selected']['task'] is None and stats['review']['task'] is None
    assert files['review'] == files['unknown'] == original
    unknown = stats['unknown']
    submitted = set(unknown['submitted_ids'])
    assert len(submitted) == len(unknown['submitted_ids']) == 1000
    submitted_paths = set(unknown['submitted_paths'])
    assert len(submitted_paths) == 1000
    baseline_path = Path('/media/shorts/图包')
    deleted_files = {str(Path(p).relative_to(baseline_path) / '1.jpg') for p in submitted_paths}
    assert len(deleted_files) == 1000 and deleted_files <= original.keys()
    without = json.loads((folder / 'lf7-purge-restart-without-app-stats.json').read_text())
    remaining = set(without['remaining_ids'])
    assert len(remaining) == 3 and submitted.isdisjoint(remaining)
    assert submitted | remaining == original_ids
    assert without['task']['id'] == unknown['task']['id']
    assert without['task']['status'] == 'completed'
    assert without['members'] == {'succeeded': 1000} and without['active_trash'] == 3
    after = json.loads((folder / 'lf7-purge-restart-without-app-files.json').read_text())['hashes']
    assert len(after) == 1006 and set(original) - set(after) == deleted_files
    notes = {path: sha for path, sha in original.items() if path.endswith('notes.txt')}
    assert len(notes) == 1003
    assert all(after.get(path) == sha for path, sha in notes.items())
    assert all(original[path] == sha for path, sha in after.items())
    for phase in phases[3:]:
        assert files[phase] == after
        assert set(stats[phase]['remaining_ids']) == remaining
        assert stats[phase]['task']['id'] == unknown['task']['id']
    setup = traces['selected']
    assert sum(e['method'] == 'POST' and e['path'] == '/api/v1/scans' for e in setup) == 1
    trace = traces['next-review']
    posts = [e for e in trace if e['method'] == 'POST']
    assert len(posts) == 3
    permanent = [e for e in posts if e['path'] == '/api/v1/pack-trash/permanent']
    assert len(permanent) == 1 and permanent[0]['status'] == 503
    assert sum(e['path'] == '/api/v1/pack-purge-plans' for e in posts) == 2
    receipts = [e for e in trace if '/pack-file-requests/' in e['path']]
    assert len(receipts) == 1 and receipts[0]['method'] == 'GET'
    assert hashlib.sha256(receipts[0]['path'].split('/')[-1].encode()).hexdigest() == permanent[0]['command_hash']
    assert any(e['path'] == f"/api/v1/maintenance-tasks/{without['task']['id']}/items"
               and e['query'].get('offset') == '24' and e['query'].get('unfinished') == 'false' for e in trace)
    assert all(e['authenticated'] for e in trace)
    log = (folder / 'lf7-purge-restart-android-test.log').read_text()
    assert 'VV_E2E_PURGE_FORCE_STOP' in log and 'VV_E2E_PURGE_REOPENED' in log and 'All tests passed!' in log
    proof.append({'round': r['round'], 'interrupted_pid': stopped['pid'], 'reopened_pid': reopened['new_pid'],
                  'original_trash_ids': 1003, 'submitted_and_deleted': 1000, 'unsubmitted': 3,
                  'retained_attachments': 1003, 'remaining_files': 1006,
                  'original_receipt_gets': 1, 'permanent_posts': 1, 'preview_posts': 2,
                  'scan_posts': 1, 'completed_without_app_seconds': round(absent['time'] - stopped['time'], 2)})
manifest = json.loads((evidence / 'source-sha256.json').read_text())
assert all(hashlib.sha256((root / p).read_bytes()).hexdigest() == sha for p, sha in manifest['files'].items())
(evidence / 'proof.json').write_text(json.dumps(proof, indent=2) + '\n')
print('PASS three real secure-storage restarts: original 1000-member batch, exact image hashes, 1003 attachments and 3 unsubmitted members')
