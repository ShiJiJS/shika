"""Read-only verification of frozen public evidence; no device or server access."""
import hashlib
import json
import re
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parent


def read(name):
    return json.loads((ROOT / name).read_text())


manifest = read('manifest.json')
actual = {
    str(p.relative_to(ROOT)) for p in ROOT.rglob('*')
    if p.is_file() and p.name != 'manifest.json' and '__pycache__' not in p.parts
}
assert actual == set(manifest['files'])
for name, entry in manifest['files'].items():
    p = ROOT / name
    assert not p.is_symlink()
    value = p.read_bytes()
    assert len(value) == entry['bytes'], name
    assert hashlib.sha256(value).hexdigest() == entry['sha256'], name

assert read('installed-apk.json')['sha256'] == manifest['apk_sha256']
assert manifest['candidate_code'] == 18
assert manifest['production_lib_tree'] == '2f02bc78653acbf12de64107e41e3236d61cb9cf'
before = read('pinch-v3-before-reader-service.json')
assert before['progress']['page_index'] == 2 and before['page_count'] == 6
base_path = next((ROOT / 'normal/screens').glob('*-pinch-v3-baseline-page-three.png'))
crop = (0, 315, 1170, 2160)
with Image.open(base_path) as im:
    assert im.size == (1170, 2715)
    base = im.convert('RGB').crop(crop)
proof = read('pinch-v3-pixel-proof.json')
for i in (1, 2, 3):
    for state in ('zoomed', 'panned', 'back-reset'):
        path = next((ROOT / 'normal/screens').glob(f'*-pinch-v3-round-{i}-{state}.png'))
        labels = [n.get('content-desc') or n.get('text') for n in ET.parse(path.with_suffix('.xml')).iter('node')]
        assert all(label in labels for label in ['返回来源', '阅读设置', '3 / 6'])
        assert read(f'pinch-v3-round-{i}-{state}-reader-service.json')['progress'] == before['progress']
        with Image.open(path) as im:
            assert im.size == (1170, 2715)
            diff = ImageChops.difference(base, im.convert('RGB').crop(crop))
        mask = diff.convert('L').point(lambda n: 255 if n > 4 else 0)
        fraction = sum(mask.histogram()[1:]) / (mask.width * mask.height)
        assert abs(fraction - proof['frames'][i - 1][state + '_changed_fraction_vs_fit']) < 1e-12
        assert fraction == 0 if state == 'back-reset' else fraction > .15
trace = (ROOT / 'pinch-v3-getevent.txt').read_text()
for tracking_id, count in [('0000044c', 3), ('0000044d', 3), ('ffffffff', 6)]:
    assert len(re.findall(r'ABS_MT_TRACKING_ID\s+' + tracking_id + r'\s', trace)) == count
subprocess.run(['ffmpeg', '-v', 'error', '-i', str(ROOT / 'pinch-v3.mp4'), '-f', 'null', '-'], check=True, timeout=60)
assert (ROOT / 'diagnostics/pinch-v2.mp4').stat().st_size == 0
assert 'err=-22' in (ROOT / 'diagnostics/pinch-v2-record.log').read_text()
assert read('reference/reader-content832-metrics.json')['simulatedHomeIndicatorVisible'] is False
with Image.open(ROOT / 'reference/reader-content832.png') as im:
    assert im.size == (390, 832)
with Image.open(ROOT / 'compare/reader-equal-content-height.png') as im:
    assert im.size == (780, 832)
cleanup = read('cleanup.json')
assert cleanup['restored_device_settings'] == read('original-settings.json')
assert cleanup['exact_initial_uid_restored'] is True
assert cleanup['original_containers_before'] == cleanup['original_containers_after']
assert cleanup['qemu_pid_stopped'] == read('device.json')['pid']
assert cleanup['container_removed'] == read('runtime.json')['container']
print(json.dumps({'verified_files': len(actual), 'native_rounds': 3, 'reader_states': 9,
                  'full_progress_unchanged': True, 'full_recording_decode': True,
                  'whole_requirement_ids_passed': 0}))
