"""Independently cross-check captured records; never mutate the fixture."""
import hashlib
import json
import subprocess
from pathlib import Path

L = Path(__file__).resolve().parent
R = L.parents[1]


def read(name):
    return json.loads((L / name).read_text())


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def same_catalog(left, right):
    a, b = read(left), read(right)
    for key in ('tables', 'opaque_table_digests', 'setting_key_sha256'):
        assert a[key] == b[key], (left, right, key)
    assert len(a['tables']) + len(a['opaque_table_digests']) == 37


same_catalog('original-before-image-fix-all-catalog.json', 'original-after-image-fix-start-all-catalog.json')
same_catalog('original-before-read-200-all-catalog.json', 'original-after-read-200-all-catalog.json')
same_catalog('tall-before-readonly-200-all-catalog.json', 'tall-after-readonly-200-all-catalog.json')
original = read('original-read-200.json')
assert len([v for v in original['results'] if v['status'] == 200]) == 9
assert len([v for v in original['results'] if v['status'] == 206]) == 1
native = [json.loads(line) for line in (L / 'requests.jsonl').read_text().splitlines()]
state = read('tall-native-state.json')
assert state['phase'] == 'native_read_and_cold_resume_completed'
permanent = [v for v in native if v['method'] == 'POST' and v['path'] == '/api/v1/pack-trash/permanent']
restores = [v for v in native if v['method'] == 'POST' and v['path'] == '/api/v1/pack-restore-plans']
assert len(permanent) == len(restores) == 1, (permanent, restores)
assert permanent[0]['status'] == 202 and restores[0]['status'] == 202
assert state['partial_task']['result']['pages_deleted'] == 2
assert state['old_purge_retry']['id'] == state['original_operation']
assert state['old_purge_retry']['error'] == 'stale_pack_state'
assert state['old_purge_retry']['result']['pages_deleted'] == 2
assert state['restore_plan']['result']['succeeded'] == 1
ctime = state['explicit_fixture_ctime_only_update']
assert ctime['before'][:4] == ctime['after'][:4]
assert ctime['before'][4] != ctime['after'][4]
assert ctime['sha256'] == ctime['after_sha256'] and ctime['original_mode_restored']
for name in ('first_read_progress', 'cold_resume_progress', 'progress_after_back'):
    assert state[name]['page_id'] == state['page_id']
    assert state[name]['offset_ratio'] == .45
assert state['old_app_pid'] != state['new_app_pid'] and state['old_pid_absent_from_ps']
image_gets = [v for v in native if v['path'] == '/api/v1/pages/' + state['page_id'] + '/image' and v['status'] == 200]
assert len(image_gets) >= 2
before, after = [read(n)['tables'] for n in ('tall-before-logical-restore-all-catalog.json', 'tall-after-logical-restore-all-catalog.json')]
preserved = ['pack_pages', 'pack_preferences', 'pack_progress', 'pack_tag_links', 'recent_entries', 'pack_sessions', 'pack_session_entries']
assert all(before[k] == after[k] for k in preserved)
initial = read('before-tall-inputs-files.json')
files = read('tall-before-readonly-200-files.json')
all_inputs = dict(initial, **read('tall-preparation.json')['new_files'])
assert len(initial) == 46 and len(all_inputs) == 51 and len(files) == 49
assert set(all_inputs) - set(files) == {'Restore-read-tall/01.png', 'Restore-read-tall/02.png'}
assert all(all_inputs[k] == v for k, v in files.items())
assert all(files[k] == v for k, v in initial.items())
conflict = read('post-restore-scan-identity-conflict.json')
assert conflict['same_directory_device_inode'] and conflict['same_remaining_image_sha256']
assert conflict['old_pack_after_scan']['status'] == 'missing'
assert conflict['new_available_pack']['id'] != conflict['old_available_pack']['id']
assert conflict['old_tag_links'] and not conflict['new_tag_links']
assert conflict['old_recent_entries'] and not conflict['new_recent_entries']
assert read('scan-identity-issue-receipt.json')['bodyPresent']
runtime = read('runtime-source.json')
assert len(runtime['files']) == 78 and runtime['other_76_files_unchanged']
assert subprocess.check_output(['git', 'diff', '8416a3f7359af94f1da802185b136770d6499986', '--', 'apps/mobile']) == b''
assert hashlib.sha256((R / 'tmp/releases/video-viewer-0.2.0-preview.20-arm64.apk').read_bytes()).hexdigest() == read('installation.json')['apk_sha256']
full = (L / 'full-server-atomic.log').read_text()
assert '509 passed' in full and 'failed' not in full
assert '1 failed, 508 passed' in (L / 'full-server.log').read_text()
assert '44 passed' in (L / 'read-after-fix-targeted.log').read_text()
assert 'All checks passed' in (L / 'ruff-atomic.log').read_text()
assert '147 files already formatted' in (L / 'format-atomic.log').read_text()
out = {'product_source': runtime['source'], 'test_fixture_source': read('test-build-source.json')['source'], 'client_unchanged': True, 'original_failure_read_200_before_scans': True, 'readonly_full_37_table_comparisons': 3, 'native_permanent_posts': len(permanent), 'native_restore_posts': len(restores), 'native_tall_image_gets_200': len(image_gets), 'native_cold_pid_pair': [state['old_app_pid'], state['new_app_pid']], 'same_page_offset_ratio': .45, 'restoration_preserved_tables': preserved, 'initial_files_preserved': 46, 'final_files': 49, 'only_two_confirmed_tall_images_deleted': True, 'next_blocking_scan_identity_issue': 163, 'tall_not_scanned_after_restore': True, 'full_server_passed': 509, 'targeted_passed': 44, 'first_full_fixture_race_preserved': True, 'nas_accessed': False}
(L / 'verified-phase.json').write_text(json.dumps(out, indent=2))
print(json.dumps(out, indent=2))
