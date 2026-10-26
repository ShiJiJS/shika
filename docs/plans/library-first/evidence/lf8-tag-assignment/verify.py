"""Read-only verification of tag-assignment sources, images, requests and SQL."""
import gzip
import hashlib
import json
import struct
import subprocess
import tarfile
from functools import cache
from io import BytesIO
from pathlib import Path

root = Path.cwd()
evidence = Path(__file__).resolve().parent
states = ['video-single', 'video-dark', 'video-error', 'video-keyboard',
          'video-saved', 'pack-single', 'pack-error', 'pack-keyboard',
          'pack-saved', 'videos', 'video-batch', 'packs', 'pack-batch', 'verified']
production = ('apps/mobile/lib/', 'services/server/video_viewer/')


def read(path):
    if path.exists():
        return json.loads(path.read_text())
    return json.loads(gzip.decompress(Path(str(path) + '.gz').read_bytes()))


def sha(data):
    return hashlib.sha256(data).hexdigest()


@cache
def committed_hashes(commit):
    raw = subprocess.check_output(['git', 'archive', '--format=tar', commit,
                                  'apps/mobile', 'services/server/video_viewer',
                                  'services/server/tests/e2e_server.py',
                                  'scripts/run-client-connection-test.py'])
    with tarfile.open(fileobj=BytesIO(raw)) as archive:
        return {f.name: sha(archive.extractfile(f).read()) for f in archive if f.isfile()}


def marker(log, name):
    values = [json.loads(line.split(name + ':', 1)[1]) for line in log.splitlines() if name + ':' in line]
    assert len(values) == 1, name
    return values[0]


subprocess.run(['git', 'diff', '--quiet', 'HEAD', '--', 'design/reference/library-first'], check=True)
assert subprocess.check_output(['git', 'rev-parse', 'HEAD:design/reference/library-first'], text=True).strip() == '1cbf605af8f03fa067a4ce8e914bb809e3a487ca'
assert '10 passed' in (evidence / 'checks' / 'server-tags-linux-check.log').read_text()
proof = []
for group, size, text13 in [('normal', [390, 844], 13), ('large', [360, 740], 26), ('landscape', [844, 390], 13)]:
    folder = evidence / 'native' / group
    source = read(folder / 'source.json')
    committed = committed_hashes(source['commit'])
    for path, digest in source['files'].items():
        assert committed[path] == digest, path
        if path.startswith(production):
            assert sha((root / path).read_bytes()) == digest, path
    assert source['prototype_tree'] == '1cbf605af8f03fa067a4ce8e914bb809e3a487ca'
    events = read(folder / 'lf8-tags-host-events.json')
    assert not events['errors']
    observed = [x['phase'].removeprefix('tag-ui-assign-') for x in events['events'] if x['phase'].startswith('tag-ui-assign-')]
    assert observed == states, observed
    assert [e['state'] for e in events['events'] if e['phase'] == 'capture-ack'] == ['tag-ui-assign-' + state for state in states]
    restored = read(folder / 'restored-viewport.json')
    assert restored['before'] == restored['after']
    log = (folder / 'lf8-tags-android-test.log').read_text()
    assert 'TAG_ASSIGNMENT_FLUTTER_ERROR:' not in log and 'All tests passed!' in log and 'Some tests failed' not in log
    ids = marker(log, 'TAG_ASSIGNMENT_VERIFIED')
    metrics = [json.loads(line.split('TAG_ASSIGNMENT_METRICS:', 1)[1]) for line in log.splitlines() if 'TAG_ASSIGNMENT_METRICS:' in line]
    assert [m['state'] for m in metrics] == states
    assert all(m['window'] == size and m['dpr'] == 3 and m['text13'] == text13 for m in metrics)
    assert all((m['keyboard'] > 0) == m['state'].endswith('-keyboard') for m in metrics)
    assert all(m['dark'] == (m['state'] == 'video-dark') for m in metrics)
    for item in metrics:
        if item['state'].endswith('-keyboard'):
            assert item['focused'] is True
            for name in ['input_rect', 'add_rect']:
                left, top, right, bottom = item[name]
                assert 0 <= left < right <= size[0]
                assert 0 <= top < bottom <= size[1] - item['keyboard']
    reloaded = [json.loads(line.split('TAG_ASSIGNMENT_SAVED:', 1)[1]) for line in log.splitlines() if 'TAG_ASSIGNMENT_SAVED:' in line]
    assert [item['kind'] for item in reloaded] == ['video', 'pack']
    assert all(item['source_reloaded'] for item in reloaded)
    hashes = None
    for state in states:
        prefix = folder / ('lf8-tags-tag-ui-assign-' + state)
        png = prefix.with_suffix('.png').read_bytes()
        assert png[:8] == b'\x89PNG\r\n\x1a\n'
        assert struct.unpack('>II', png[16:24]) == tuple(n * 3 for n in size)
        window = Path(str(prefix) + '-window.txt').read_text()
        assert any('mCurrentFocus=' in line and 'io.github.shijijs.video_viewer' in line for line in window.splitlines())
        current = read(Path(str(prefix) + '-files.json'))['hashes']
        if hashes is None:
            hashes = current
            assert len(hashes) == 81
        assert current == hashes
        stats = read(Path(str(prefix) + '-stats.json'))
        for pack in [False, True]:
            defs = stats['pack_tags' if pack else 'video_tags']
            names = {d['id']: d['name'] for d in defs}
            assert len(names) == len(defs) and len(names) <= 200
            links = stats['pack_links' if pack else 'video_links']
            assert all(link['tag_id'] in names for link in links)
            if state == 'verified':
                media_ids = set(ids['packs' if pack else 'videos'])
                assert len(media_ids) == 27
                excluded = ids['excluded_pack' if pack else 'excluded_video']
                preserved = ids['pack_preserved' if pack else 'video_preserved']
                appended = ids['pack_appended' if pack else 'video_appended']
                assert names[preserved] == '保留' and names[appended] == '追加'
                created = ids['pack_created' if pack else 'video_created']
                assert names[created] == '现场新标签'
                assert created != ids['video_created' if pack else 'pack_created']
                assert len(links) == 53
                for item in media_ids:
                    selected = {r['tag_id'] for r in links if r['pack_id' if pack else 'video_id'] == item}
                    assert selected == ({preserved} if item == excluded else {preserved, appended})
        if state in {'video-saved', 'pack-saved'}:
            requests = read(Path(str(prefix) + '-requests.json'))['items']
            for pack in ([False] if state == 'video-saved' else [False, True]):
                path = '/api/v1/pack-tag-links' if pack else '/api/v1/video-tags'
                saves = [r for r in requests if r['method'] == 'PATCH' and r['path'] == path
                         and r.get('assignment', {}).get('mode') == 'replace'
                         and len(r['assignment']['pack_ids' if pack else 'video_ids']) == 1]
                assert len(saves) == 1 and saves[0]['status'] == 200
                body = saves[0]['assignment']
                target = body['pack_ids' if pack else 'video_ids'][0]
                created = ids['pack_created' if pack else 'video_created']
                added = ids['pack_appended' if pack else 'video_appended']
                preserved = ids['pack_preserved' if pack else 'video_preserved']
                assert set(body['tag_ids']) == {created, added}
                ui = reloaded[1 if pack else 0]
                assert ui['id'] == target and set(ui['tags']) == {created, added}
                links = stats['pack_links' if pack else 'video_links']
                assert len(links) == 28
                for item in ids['packs' if pack else 'videos']:
                    actual = {r['tag_id'] for r in links if r['pack_id' if pack else 'video_id'] == item}
                    assert actual == ({created, added} if item == target else {preserved})
        if state == 'verified':
            requests = read(Path(str(prefix) + '-requests.json'))['items']
            for pack in [False, True]:
                path = '/api/v1/pack-tag-links' if pack else '/api/v1/video-tags'
                posts = [r for r in requests if r['method'] == 'PATCH' and r['path'] == path]
                batch = posts[-1]
                assert batch['status'] == 200
                body = batch['assignment']
                targets = set(body['pack_ids' if pack else 'video_ids'])
                assert targets == set(ids['packs' if pack else 'videos']) - {ids['excluded_pack' if pack else 'excluded_video']}
                assert body['mode'] == 'add'
                assert body['tag_ids'] == [ids['pack_appended' if pack else 'video_appended']]
                assert any(r['status'] == 409 and r['path'] == ('/api/v1/pack-tags' if pack else '/api/v1/tags') for r in requests)
    proof.append({'group': group, 'states': len(states), 'members_each_kind': 27, 'appended_each_kind': 26, 'image_hashes': len(hashes)})

for run in range(1, 4):
    log = (evidence / 'checks' / f'final-tests-{run}.log').read_text()
    assert '+48: All tests passed!' in log and 'Some tests failed' not in log
assert '+31: All tests passed!' in (evidence / 'checks' / 'shared-modal-regressions.log').read_text()
assert 'Formatted 16 files (0 changed)' in (evidence / 'checks' / 'format.log').read_text()
assert 'All checks passed!' in (evidence / 'checks' / 'ruff.log').read_text()
assert 'No issues found!' in (evidence / 'checks' / 'analyze.log').read_text()
manifest = read(evidence / 'manifest.json')
assert set(manifest['files']) == {str(p.relative_to(evidence)) for p in evidence.rglob('*')
                                  if p.is_file() and p.name not in {'manifest.json', 'verification.json'}}
for name, digest in manifest['files'].items():
    assert sha((evidence / name).read_bytes()) == digest, name
print(json.dumps({'verified': True, 'groups': proof, 'widget_tests_per_round': 48, 'widget_rounds': 3, 'additional_shared_tests': 31,
                  'manifest_files': len(manifest['files'])}, ensure_ascii=False, indent=2))
