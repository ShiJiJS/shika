"""Read-only audit of identical production bytes and explicitly composed evidence."""

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
core = ['video', 'pack', 'dark', 'create-keyboard', 'create-error', 'created',
        'rename-editor', 'rename-editor-dark', 'renamed', 'remove-confirm',
        'removed', 'page-error', 'paged']
results = ['results-error', 'results']
production = ('apps/mobile/lib/', 'services/server/video_viewer/')


def read(path):
    return json.loads(path.read_text())


def sha(data):
    return hashlib.sha256(data).hexdigest()


@cache
def committed_hashes(commit):
    data = subprocess.check_output([
        'git', 'archive', '--format=tar', commit,
        'apps/mobile/lib', 'apps/mobile/test', 'apps/mobile/integration_test',
        'scripts/run-client-connection-test.py', 'services/server/video_viewer',
        'services/server/tests/e2e_server.py',
    ])
    with tarfile.open(fileobj=BytesIO(data)) as archive:
        return {item.name: sha(archive.extractfile(item).read()) for item in archive if item.isfile()}


def source_check(metadata, current=False, production_current=True):
    expected = committed_hashes(metadata['commit'])
    for path, digest in metadata['files'].items():
        assert expected[path] == digest, path
        if current or production_current and path.startswith(production):
            assert sha((root / path).read_bytes()) == digest, path


def marker(log, name):
    values = [json.loads(line.split(name + ':', 1)[1]) for line in log.splitlines() if name + ':' in line]
    assert len(values) == 1, name
    return values[0]


source = read(evidence / 'source.json')
proof = []
groups = [('normal', [390, 844], 13, core + results, 'complete'),
          ('large', [360, 740], 26, core, 'core'),
          ('landscape', [844, 390], 13, core, 'core'),
          ('large-results', [360, 740], 26, results, 'results-only'),
          ('landscape-results', [844, 390], 13, results, 'results-only')]
for name, size, text13, states, scope in groups:
    folder = evidence / name
    metadata = read(folder / 'source.json')
    source_check(metadata)
    assert metadata['prototype_tree'] == source['prototype_tree']
    events = read(folder / 'lf8-tags-host-events.json')
    assert not events['errors']
    actual = [v['phase'][len('tag-ui-'):] for v in events['events'] if v['phase'].startswith('tag-ui-')]
    # The historical core run had a weak results gate. That last frame is
    # intentionally excluded; actual results are checked in separate new runs.
    assert actual == (core + ['results'] if scope == 'core' else states)
    log = (folder / 'lf8-tags-android-test.log').read_text()
    assert 'All tests passed!' in log and 'Some tests failed' not in log
    expected = 'TAG_RESULTS_ONLY_VERIFIED:two-tag AND=1, 503 retry, exact member, source and playback unchanged' if scope == 'results-only' else 'TAG_MANAGEMENT_VERIFIED:separate same names, duplicate preserved, rename retained id, cancelled removal, pack-only removal, two-tag AND=1, source and playback unchanged'
    assert expected in log
    before, after = marker(log, 'TAG_MANAGEMENT_BASELINE'), marker(log, 'TAG_MANAGEMENT_FINAL')
    assert after == {key: before[key] for key in ['playback', 'media']}
    assert len(before['media']['items']) == 27 and before['playback']['total'] == 27
    if scope != 'core':
        assert marker(log, 'TAG_RESULT_VERIFIED') == {
            'ids': [before['video_ids'][0]], 'total': 1,
            'tags': sorted(before['tag_ids'][:2]), 'error': '',
        }
    metrics = [json.loads(line.split('TAG_MANAGEMENT_METRICS:', 1)[1]) for line in log.splitlines() if 'TAG_MANAGEMENT_METRICS:' in line]
    assert [m['state'] for m in metrics] == actual
    assert all(m['window'] == size and m['dpr'] == 3 and m['text13'] == text13 for m in metrics)
    assert all((m['keyboard'] > 0) == (m['state'] == 'create-keyboard') for m in metrics)
    assert all(m['dark'] == (m['state'] in {'dark', 'rename-editor-dark'}) for m in metrics)
    stats, traces, hashes = {}, {}, {}
    for state in states:
        base = folder / ('lf8-tags-tag-ui-' + state)
        png = base.with_suffix('.png').read_bytes()
        assert png[:8] == b'\x89PNG\r\n\x1a\n'
        assert struct.unpack('>II', png[16:24]) == tuple(n * 3 for n in size)
        focus = Path(str(base) + '-window.txt').read_text()
        assert any('mCurrentFocus=' in line and 'io.github.shijijs.video_viewer' in line for line in focus.splitlines())
        stats[state] = read(Path(str(base) + '-stats.json'))
        traces[state] = read(Path(str(base) + '-requests.json'))['items']
        hashes[state] = read(Path(str(base) + '-files.json'))['hashes']
    initial = stats[states[0]]
    assert len(hashes[states[0]]) == 81 and all(v == hashes[states[0]] for v in hashes.values())
    definitions = {r['id']: r['name'] for r in initial['video_tags']}
    assert len(definitions) == 61 and set(definitions) == set(before['tag_ids'])
    assert definitions[before['tag_ids'][0]] == '分页00'
    pack_tag, pack_id = before['pack_tag'], before['pack_id']
    initial_pack_links = [{'pack_id': pack_id, 'tag_id': pack_tag}]
    assert initial['pack_tags'] == [{'id': pack_tag, 'name': '分页00'}]
    assert initial['pack_links'] == initial_pack_links
    links = initial['video_links']
    first, second = before['tag_ids'][:2]
    linked = {tag: {v['video_id'] for v in links if v['tag_id'] == tag} for tag in [first, second]}
    assert linked[first] == set(before['video_ids']) and linked[second] == {before['video_ids'][0]}
    assert linked[first] & linked[second] == {before['video_ids'][0]}
    for state in states:
        data = stats[state]
        assert {r['id']: r['name'] for r in data['video_tags']} == definitions
        assert data['video_links'] == links
        pack_definitions = {r['id']: r['name'] for r in data['pack_tags']}
        if scope == 'results-only' or states.index(state) < states.index('created'):
            assert pack_definitions == {pack_tag: '分页00'}
            assert data['pack_links'] == initial_pack_links
        elif states.index(state) < states.index('removed'):
            assert len(pack_definitions) == 2 and '仅图包新标签' in pack_definitions.values()
            assert pack_definitions[pack_tag] == ('图包改名' if state in {'renamed', 'remove-confirm'} else '分页00')
            assert data['pack_links'] == initial_pack_links
        else:
            assert len(pack_definitions) == 1 and list(pack_definitions.values()) == ['仅图包新标签']
            assert data['pack_links'] == []
    initial_writes = [r for r in traces[states[0]] if r['method'] != 'GET']
    final_writes = [r for r in traces[states[-1]] if r['method'] != 'GET']
    assert final_writes[:len(initial_writes)] == initial_writes
    writes = final_writes[len(initial_writes):]
    if scope == 'results-only':
        assert not writes
    else:
        assert [(r['method'], r['path'], r['status'], r['tag_input']) for r in writes] == [
            ('POST', '/api/v1/pack-tags', 409, {'name': '分页00'}),
            ('POST', '/api/v1/pack-tags', 201, {'name': '仅图包新标签'}),
            ('PATCH', '/api/v1/pack-tags/' + pack_tag, 200, {'name': '图包改名'}),
            ('DELETE', '/api/v1/pack-tags/' + pack_tag, 200, {'name': None}),
        ]
        assert len({r['command_hash'] for r in writes}) == 4
        assert [r for r in traces['remove-confirm'] if r['method'] != 'GET'] == final_writes[:-1]
    final_trace = traces[states[-1]]
    assert all(r['authenticated'] or r['path'] in {'/api/v1/info', '/api/v1/auth/login'} for r in final_trace)
    page = [r['status'] for r in final_trace if r['method'] == 'GET' and r['path'] == '/api/v1/tags' and r['query'].get('offset') == '50']
    assert page == ([] if scope == 'results-only' else [503, 200])
    if scope != 'core':
        reads = [r for r in final_trace if r['method'] == 'GET' and r['path'] == '/api/v1/videos' and r['query'].get('source') == 'tags' and r['query'].get('limit') == '24']
        assert [r['status'] for r in reads] == [503, 200]
        assert all(set(r['query_lists'].get('tag_ids', [])) == {first, second} for r in reads)
        assert not [r for r in traces['results-error'] if r['method'] == 'GET' and r['path'] == '/api/v1/videos' and r['query'].get('source') == 'tags' and r['query'].get('limit') == '24' and r['status'] == 200]
    restored = read(folder / 'restored-viewport.json')
    assert restored['before'] == restored['after'] == {'size': 'Physical size: 1080x2400', 'density': 'Physical density: 420', 'font_scale': '1.0'}
    proof.append({'group': name, 'scope': scope, 'source': metadata['commit'], 'valid_checkpoints': len(states), 'image_hashes': 81, 'video_files': 27, 'video_tags': 61, 'intersection': 1, 'ui_mutation_attempts': len(writes)})

source_check(source)
source_check(read(evidence / 'checks/source.json'), current=True)
assert subprocess.check_output(['git', 'rev-parse', '4e905aa:apps/mobile/lib']) == subprocess.check_output(['git', 'rev-parse', 'HEAD:apps/mobile/lib'])
assert subprocess.check_output(['git', 'rev-parse', '7e366e9:services/server/video_viewer']) == subprocess.check_output(['git', 'rev-parse', 'HEAD:services/server/video_viewer'])
for index in [1, 2, 3]:
    assert '+46: All tests passed!' in (evidence / f'checks/targeted-{index}.log').read_text()
assert 'No issues found!' in (evidence / 'checks/analyze.log').read_text()
assert '0 changed' in (evidence / 'checks/format.log').read_text()
assert 'All checks passed!' in (evidence / 'checks/ruff.log').read_text()
prototype = read(evidence / 'reference/source.json')
assert prototype['prototype_tree'] == source['prototype_tree'] == '1cbf605af8f03fa067a4ce8e914bb809e3a487ca'
assert subprocess.check_output(['git', 'rev-parse', 'HEAD:design/reference/library-first'], text=True).strip() == source['prototype_tree']
assert len(prototype['files']) == 13
for item in prototype['files']:
    assert item['status'] == 200 and sha((root / 'design/reference/library-first' / item['path']).read_bytes()) == item['sha256']
for name in ['baseline-partial', 'intermediate-input-delivery', 'intermediate-before-single-panel', 'intermediate-large-before-single-panel', 'intermediate-single-panel-normal', 'intermediate-single-panel-large', 'intermediate-result-title-only-normal', 'intermediate-result-title-only-landscape', 'diagnostics/landscape-before-ready-wait', 'diagnostics/landscape-loaded-but-unmounted', 'diagnostics/emulator-exited', 'diagnostics/result-fault-without-epoch', 'diagnostics/strict-results-before-transport-diagnostic', 'diagnostics/emulator-exited-during-large', 'diagnostics/emulator-exited-during-large2', 'diagnostics/software-launcher-anr']:
    source_check(read(evidence / name / 'source.json'), production_current=False)
manifest = read(evidence / 'manifest.json')
actual = {str(p.relative_to(evidence)) for p in evidence.rglob('*') if p.is_file() and p.name not in {'manifest.json', 'verification.json'}}
assert set(manifest) == actual
assert all(sha((evidence / p).read_bytes()) == digest for p, digest in manifest.items())
assert sum(p['valid_checkpoints'] for p in proof) == 45
print(json.dumps({'verified': True, 'production_client': '4e905aa', 'inputs': len(manifest), 'native_checkpoints': 45, 'composed_groups': proof}, ensure_ascii=False, indent=2))
