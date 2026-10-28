import json
import shutil
import sqlite3
import sys
import time

from app_driver import PACKAGE, capture, cold_start, current_pid, device, fill, tap, text
from lab import LAB, MEDIA, NEW, OLD, api, save, sha, start, stop, tables, tree

BASE = json.loads((LAB / 'baseline-projection.json').read_text())
SEED = json.loads((LAB / 'seeded.json').read_text())
COLUMNS = {k: v['columns'] for k, v in BASE.items() if isinstance(v, dict)}
STABLE = ['tags', 'video_tags', 'playback_rounds', 'round_entries', 'request_records',
          'file_operations', 'file_steps', 'trash_items']


def observed(name, label=None, prefix=None):
    nodes = capture(name)
    if label is not None:
        tap(next(n for n in nodes if n.get('content-desc') == label), label)
    elif prefix is not None:
        tap(next(n for n in nodes if n.get('content-desc', '').startswith(prefix)), prefix)
    return nodes


def wait_scan(phase):
    old_ids = {v['id'] for v in BASE['tasks']['rows'] if v['kind'] == 'scan'}
    deadline = time.monotonic() + 40
    while True:
        snapshot = tables(LAB / 'data/library.sqlite3')
        scans = [v for v in snapshot['tasks']['rows'] if v['kind'] == 'scan' and v['id'] not in old_ids]
        if scans and all(v['status'] == 'completed' for v in scans):
            save(phase + '/startup-scans.json', scans)
            return snapshot
        assert time.monotonic() < deadline, 'Startup scan did not finish'
        time.sleep(.2)


def verify_migration(phase):
    current = wait_scan(phase)
    assert current['alembic_version']['rows'] == [{'version_num': '0014'}]
    assert current['integrity'] == 'ok' and not current['foreign_key_errors']
    snapshots = list((LAB / 'data/migration-snapshots').glob('*.sqlite3'))
    assert len(snapshots) == 1
    original = tables(snapshots[0], stopped=True)
    assert original == BASE
    save(phase + '/automatic-snapshot-proof.json', {
        'name': snapshots[0].name, 'sha256': sha(snapshots[0]),
        'mode': oct(snapshots[0].stat().st_mode & 0o777), 'all_original_tables_equal': True,
    })
    projection = tables(LAB / 'data/library.sqlite3', COLUMNS)
    assert projection['access_tokens'] == BASE['access_tokens']
    for name in STABLE:
        assert projection[name] == BASE[name], name
    # Existing identities and metadata survive; scanner observations can advance.
    for name, ignored in [('roots', {'last_scan'}), ('videos', {'seen_scan'}), ('directories', {'seen_scan'})]:
        prior = [{k: v for k, v in row.items() if k not in ignored} for row in BASE[name]['rows']]
        after = [{k: v for k, v in row.items() if k not in ignored} for row in projection[name]['rows']]
        assert prior == after, name
    assert all(row in projection['settings']['rows'] for row in BASE['settings']['rows'])
    assert all(row in projection['tasks']['rows'] for row in BASE['tasks']['rows'])
    with sqlite3.connect((LAB / 'data/library.sqlite3').as_uri() + '?mode=ro', uri=True) as c:
        epoch = c.execute("select value from settings where key='management_epoch'").fetchone()[0]
        assert c.execute('select count(*) from access_tokens').fetchone()[0] == 1
        assert c.execute('select count(*) from access_tokens where issued_epoch=?', (epoch,)).fetchone()[0] == 1
        assert c.execute('select kind,enabled from roots').fetchall() == [('video', 1)]
    save(phase + '/after-startup-original-columns.json', projection)
    save(phase + '/migration-proof.json', {
        'schema': '0014', 'old_token_columns_equal': True, 'original_token_bound_once': True,
        'stable_tables': STABLE, 'old_settings_and_tasks_retained': True,
        'root_video_enabled': True, 'scanner_changes_only': ['roots.last_scan', 'videos.seen_scan', 'directories.seen_scan'],
    })
    return projection


def preferences(nodes):
    switches = {n.get('content-desc'): n.get('checked') for n in nodes if n.get('class') == 'android.widget.Switch'}
    assert switches['暗黑模式'] == 'true'
    assert switches['准备相邻视频，前后各一条；关闭可减少网络与解码占用'] == 'false'
    assert 'http://10.0.2.2:8772' in text(nodes)
    return switches


def app_window(phase, allow_marker=False):
    startup = json.loads((LAB / (phase + '-app-start.json')).read_text())
    rows = [json.loads(s) for s in (LAB / 'trace' / phase / 'requests.jsonl').read_text().splitlines()][startup['trace_start_offset']:]
    writes = [v for v in rows if v['method'] != 'GET']
    assert all(v['status'] in (200, 201, 206) for v in rows)
    assert not any(v['path'] == '/api/v1/auth/login' for v in rows)
    if allow_marker:
        assert len(writes) == 1 and writes[0]['method'] == 'POST' and writes[0]['path'] == '/api/v1/tags'
    else:
        assert writes == []
    save(phase + '/app-requests.json', rows)
    return rows


def new_ui(number, resume=False):
    phase = f'final-{number}-new'
    before = verify_migration(phase)
    if resume:
        existing = json.loads((LAB / (phase + '-app-start.json')).read_text())
        assert current_pid() == existing['new_pid']
    else:
        cold_start(phase, 'new')
    nodes = capture(phase + '-library')
    assert '1 个视频' in text(nodes) and 'LEGACY_ONLY' in text(nodes)
    startup = app_window(phase)
    assert not any('/stream' in v['path'] or '/opened' in v['path'] for v in startup)
    save(phase + '/startup-requests.json', startup)
    observed(phase + '-before-packs', label='图包\n0')
    nodes = capture(phase + '-packs-empty')
    assert '没有符合条件的图包' in text(nodes)
    observed(phase + '-before-videos', label='视频\n1')
    observed(phase + '-before-tags', label='标签')
    nodes = capture(phase + '-tags')
    assert 'LEGACY_ONLY' in text(nodes) and 'AFTER_UPGRADE' not in text(nodes)
    observed(phase + '-before-settings', label='设置')
    nodes = capture(phase + '-settings')
    switches = preferences(nodes)
    observed(phase + '-before-trash', prefix='回收站\n')
    nodes = capture(phase + '-trash')
    assert '共 1 个视频' in text(nodes) and 'flower-portrait' in text(nodes)
    observed(phase + '-trash-return', label='返回设置')
    observed(phase + '-before-tasks', prefix='操作任务\n')
    nodes = capture(phase + '-tasks')
    row = next(n for n in nodes if n.get('content-desc', '').startswith('视频移入回收站\n'))
    assert row.get('content-desc').splitlines()[1] == '已完成'
    tap(row, 'migrated old task completed')
    nodes = capture(phase + '-task-detail')
    assert SEED['task']['id'] in text(nodes)
    observed(phase + '-task-before-all', label='全部')
    nodes = capture(phase + '-task-all')
    assert 'flower-portrait' in text(nodes) and '已完成' in text(nodes) and '共 1 项' in text(nodes)
    assert tables(LAB / 'data/library.sqlite3', COLUMNS) == before
    observed(phase + '-task-return', label='返回操作任务')
    observed(phase + '-tasks-return', label='返回设置')
    observed(phase + '-settings-return-tags', label='标签')
    observed(phase + '-before-new-tag', label='新建视频标签')
    capture(phase + '-create-dialog')
    marker = f'AFTER_UPGRADE_FINAL_{number}'
    fill(0, marker, phase + '-marker-input')
    if 'mInputShown=true' in device('shell', 'dumpsys', 'input_method').decode():
        device('shell', 'input', 'keyevent', '4')
    observed(phase + '-marker-filled', label='创建标签')
    nodes = capture(phase + '-marker-created')
    assert marker in text(nodes) and 'LEGACY_ONLY' in text(nodes)
    device('shell', 'am', 'force-stop', PACKAGE)
    assert current_pid() is None
    app_window(phase, allow_marker=True)
    after = tables(LAB / 'data/library.sqlite3', COLUMNS)
    assert after['tags']['count'] == BASE['tags']['count'] + 1
    assert after['request_records']['count'] == BASE['request_records']['count'] + 1
    for name in [n for n in STABLE if n not in {'tags', 'request_records'}]:
        assert after[name] == BASE[name], name
    save(phase + '/after-ui-original-columns.json', after)
    save(phase + '/ui-proof.json', {
        'no_login': True, 'new_library_no_autoplay': True, 'available_video_count': 1,
        'pack_entry_available_empty': True, 'old_tag_retained': True, 'trash_count': 1,
        'old_task_id': SEED['task']['id'], 'old_task_state': 'completed', 'completed_members': 1,
        'readonly_before_marker': True, 'marker': marker, 'actual_switches': switches,
    })
    print(json.dumps({'phase': phase, 'ui': 'passed', 'old_task': 'completed'}), flush=True)


def inspect_http(phase, version):
    assert current_pid() is None
    prior = tables(LAB / 'data/library.sqlite3')['access_tokens']
    token = api('/api/v1/auth/login', 'POST', {'passphrase': (LAB / 'config/passphrase').read_text()})['access_token']
    info = api('/api/v1/info', token=token)
    videos = api('/api/v1/videos', token=token)
    trash = api('/api/v1/trash', token=token)
    receipt = api('/api/v1/file-requests/upgrade-rollback-seed-trash', token=token)
    assert info['server_id'] == SEED['info']['server_id']
    assert videos['total'] == 1 and trash['total'] == 1
    assert videos['items'][0]['id'] == SEED['videos']['items'][0]['id']
    assert trash['items'][0]['video']['id'] == SEED['trash']['items'][0]['video']['id']
    assert receipt == SEED['receipt']
    summary = None
    if version == 'new':
        assert info['schema_version'] == '0014'
        summary = api('/api/v1/maintenance-tasks/' + receipt['id'], token=token)
        assert summary['state'] == 'completed' and summary['total'] == summary['processed'] == 1
    else:
        assert 'capabilities' not in info
    api('/api/v1/auth/session', 'DELETE', token=token)
    assert tables(LAB / 'data/library.sqlite3')['access_tokens'] == prior
    save(phase + '/host-http-inspection.json', {
        'app_already_stopped': True, 'temporary_inspection_token_revoked': True,
        'original_token_table_unchanged': True, 'info': info, 'videos': videos, 'trash': trash,
        'original_receipt_unchanged': True, 'receipt': receipt, 'summary': summary,
    })


def restore_backup(number):
    phase = f'final-{number}-new'
    assert json.loads((LAB / phase / 'stopped.json').read_text())['removed']
    assert current_pid() is None
    (LAB / 'data').rename(LAB / f'final-{number}-upgraded-data')
    assert tree(LAB / 'config') == tree(LAB / 'baseline-backup/config')
    shutil.copytree(LAB / 'baseline-backup/data', LAB / 'data', copy_function=shutil.copyfile)
    assert tree(LAB / 'data') == tree(LAB / 'baseline-backup/data')
    assert tables(LAB / 'data/library.sqlite3', stopped=True) == BASE
    save(f'final-{number}-restore.json', {
        'app_stopped': True, 'upgraded_container_removed': True, 'upgraded_data_preserved': True,
        'restored_all_data_files_equal': True, 'config_equal': True, 'schema': '0004',
        'files': tree(LAB / 'data'),
    })


def old_ui(number):
    phase = f'final-{number}-old'
    current = wait_scan(phase)
    assert current['alembic_version']['rows'] == [{'version_num': '0004'}]
    for name in STABLE + ['access_tokens']:
        assert current[name] == BASE[name], name
    cold_start(phase, 'legacy')
    observed(phase + '-before-library', label='视频库')
    nodes = capture(phase + '-library')
    assert '1 个视频' in text(nodes) and 'LEGACY_ONLY' in text(nodes)
    observed(phase + '-before-tags', label='标签')
    nodes = capture(phase + '-tags')
    assert 'LEGACY_ONLY' in text(nodes) and 'AFTER_UPGRADE' not in text(nodes)
    observed(phase + '-before-settings', label='设置')
    nodes = capture(phase + '-settings')
    switches = preferences(nodes)
    observed(phase + '-before-trash', prefix='回收站\n')
    nodes = capture(phase + '-trash')
    assert '共 1 个视频' in text(nodes) and 'flower-portrait' in text(nodes)
    device('shell', 'am', 'force-stop', PACKAGE)
    assert current_pid() is None
    rows = app_window(phase)
    assert not any('/packs' in v['path'] or '/pack-tags' in v['path'] for v in rows)
    save(phase + '/after-ui-projection.json', tables(LAB / 'data/library.sqlite3'))
    save(phase + '/ui-proof.json', {
        'no_login': True, 'legacy_video_ui': True, 'available_video_count': 1, 'trash_count': 1,
        'old_tag_retained': True, 'post_upgrade_marker_absent': True, 'actual_switches': switches,
        'unsupported_pack_requests': 0,
    })
    print(json.dumps({'phase': phase, 'ui': 'passed', 'marker_absent': True}), flush=True)


def cycle(number, resume=False):
    new_phase, old_phase = f'final-{number}-new', f'final-{number}-old'
    if not resume:
        assert not (LAB / 'data').exists()
        shutil.copytree(LAB / 'baseline-backup/data', LAB / 'data', copy_function=shutil.copyfile)
        start(new_phase, 'new')
    new_ui(number, resume)
    inspect_http(new_phase, 'new')
    stop(new_phase)
    restore_backup(number)
    start(old_phase, 'old')
    old_ui(number)
    inspect_http(old_phase, 'old')
    stop(old_phase)
    (LAB / 'data').rename(LAB / f'final-{number}-rolled-back-data')
    assert tree(MEDIA) == json.loads((LAB / 'media-before.json').read_text())
    save(f'final-{number}-result.json', {
        'complete': True, 'same_sample': True, 'server_source': 'b79da7b9c4d2ab099c055b8eb855904e32abb0a5',
        'new_image': NEW, 'old_image': OLD, 'app_version_code': 6, 'upgrade': '0004->0014',
        'rollback': 'full stopped baseline -> original image', 'media_sha_unchanged': True,
        'old_receipt_unchanged': True, 'no_app_login': True,
    })
    print(json.dumps({'round': number, 'complete': True}), flush=True)


if __name__ == '__main__':
    first = int(sys.argv[1])
    for number in range(first, 4):
        cycle(number, resume=(number == first and '--resume-new' in sys.argv))
