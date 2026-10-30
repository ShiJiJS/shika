"""Read only: frozen public artifacts, not live devices or database files."""
import hashlib
import json
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parent


def read(name):
    return json.loads((ROOT / name).read_text())


manifest = read('manifest.json')
files = {str(p.relative_to(ROOT)) for p in ROOT.rglob('*')
         if p.is_file() and p.name != 'manifest.json' and '__pycache__' not in p.parts}
assert files == set(manifest['files'])
for name, entry in manifest['files'].items():
    p = ROOT / name
    assert not p.is_symlink()
    data = p.read_bytes()
    assert len(data) == entry['bytes'] and hashlib.sha256(data).hexdigest() == entry['sha256'], name
for folder in ['build-1', 'build-2']:
    result = read(folder + '/result.json')
    assert result['complete'] and len(result['steps']) == 13
    for step in result['steps']:
        assert step['exit_code'] == 0
        assert hashlib.sha256((ROOT / folder / (step['name'] + '.log')).read_bytes()).hexdigest() == step['log_sha256']
build = read('build-2/result.json')
assert build['source'] == manifest['source'] and build['forward']['version_code'] == 20
assert build['forward']['certificate_sha256'] == build['rollback']['certificate_sha256'] == 'f5abd3bd11d94b3aaee66ab65e6a666a228a4d64edf4b86de9327ae9b8a59161'
assert '+789: All tests passed!' in (ROOT / 'flutter-test.log').read_text()
assert '+19: All tests passed!' in (ROOT / 'dark-overlay-tests.log').read_text()
for log in ['analyze.log', 'dark-overlay-analyze.log']:
    assert 'No issues found!' in (ROOT / log).read_text()
for name, kind in [('upgrade20', 'forward'), ('rollback20', 'rollback'), ('return20', 'forward')]:
    before, after = [read('normal/' + name + '-' + stage + '-all-catalog.json') for stage in ['before', 'after']]
    assert len(before['tables']) == len(after['tables']) == 35
    for key in ['tables', 'opaque_table_digests', 'setting_key_sha256']:
        assert before[key] == after[key], (name, key)
    assert read('normal/' + name + '-before-preferences.json') == read('normal/' + name + '-after-preferences.json')
    receipt = read('normal/' + name + '-install.json')
    assert 'install' in receipt['command'] and '-r' in receipt['command']
    assert receipt['sha256'] == build[kind]['sha256'] and receipt['no_uninstall_or_clear']
    for key in ['firstInstallTime', 'dataDir', 'appId']:
        assert receipt['before'][key] == receipt['after'][key]
    assert receipt['after']['versionCode'].split()[0] == '20'
assert read('normal20-result.json')['installed_sha256'] == build['forward']['sha256']
for state in ['candidate20-reader-light', 'candidate20-reader-dark', 'candidate20-reader-more-cancel-back']:
    path = next((ROOT / 'normal/screens').glob('*-' + state + '.xml'))
    labels = [n.get('content-desc') or n.get('text') for n in ET.parse(path).iter('node')]
    assert all(label in labels for label in ['返回来源', '阅读设置', '3 / 6'])
def picture(state):
    p = next((ROOT / 'normal/screens').glob('*-' + state + '.png'))
    with Image.open(p) as im:
        assert im.size == (1170, 2715)
        return im.convert('RGB')
assert ImageChops.difference(picture('baseline18-reader-light').crop((0,315,1170,2160)), picture('candidate20-reader-light').crop((0,315,1170,2160))).getbbox() is None
old, new = picture('candidate19-home-dark'), picture('candidate20-home-dark')
for point in read('dark-play-pixels.json')['points']:
    a, b = old.getpixel(tuple(point['point'])), new.getpixel(tuple(point['point']))
    assert list(a) == point['code19'] and list(b) == point['code20']
    assert min(a) > 160 and max(b) < 90
a, b = [read('diagnostics/rollback19-' + stage + '-all-catalog.json') for stage in ['before', 'settled']]
assert {k for k in a['tables'] if a['tables'][k] != b['tables'][k]} == {'playback_rounds', 'round_entries'}
round_id = b['tables']['playback_rounds'][0]['id']
assert len(b['tables']['playback_rounds']) == 1 and len(b['tables']['round_entries']) == 2
assert all(e['round_id'] == round_id for e in b['tables']['round_entries'])
assert {e['video_id'] for e in b['tables']['round_entries']} == {v['id'] for v in b['tables']['videos']}
sha = lambda s: hashlib.sha256(s.encode()).hexdigest()
keys = set(a['setting_key_sha256']) | set(b['setting_key_sha256'])
assert {k for k in keys if a['setting_key_sha256'].get(k) != b['setting_key_sha256'].get(k)} == {'active_round', 'library_round_refresh'}
assert a['setting_key_sha256']['library_round_refresh'] == sha('1') and 'library_round_refresh' not in b['setting_key_sha256']
assert 'active_round' not in a['setting_key_sha256'] and b['setting_key_sha256']['active_round'] == sha(round_id)
assert a['opaque_table_digests']['access_tokens'] == b['opaque_table_digests']['access_tokens']
assert read('diagnostics/rollback19-exact-playback-settings.json') == [{'key': 'active_round', 'value': round_id}]
cleanup = read('cleanup.json')
assert cleanup['restored_device_settings'] == read('original-settings.json')
assert cleanup['exact_initial_uid_restored']
assert cleanup['original_containers_before'] == cleanup['original_containers_after']
assert cleanup['qemu_pid_stopped'] == read('device.json')['pid']
assert cleanup['container_removed'] == read('normal/runtime.json')['container']
print(json.dumps({'verified_files': len(files), 'final_code': 20, 'cover_installs': 3,
                  'tables_preserved_each_install': 35, 'reader_canvas_unchanged': True,
                  'dark_play_markers_corrected': 2, 'whole_acceptance_ids_passed': 0}))
