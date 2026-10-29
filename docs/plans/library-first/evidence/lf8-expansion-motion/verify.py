"""Read only frozen logs and hashes; no app, SDK, service or device operations."""
import hashlib
import json
from pathlib import Path
import re

root = Path(__file__).resolve().parent
manifest = json.loads((root / 'manifest.json').read_text())
for name, entry in manifest['files'].items():
    data = (root / name).read_bytes()
    assert len(data) == entry['bytes'], name
    assert hashlib.sha256(data).hexdigest() == entry['sha256'], name
assert len(manifest['files']) == 13
raw = (root / 'original-diagnostic.log').read_text()
points = re.findall(r'ACTUAL scan (ordinary|reduced|live) expand=(true|false) visibleHeight=([0-9.]+)', raw)
assert len(points) == 6 and '+0 -6:' in raw and 'Some tests failed.' in raw
for mode, direction, height in points:
    assert float(height) != (1 if direction == 'true' else 0)
style = (root / 'style-only-diagnostic.log').read_text()
assert len(re.findall(r'STYLE ONLY expand=(true|false) firstReducedHeight=', style)) == 2
assert '+0 -2:' in style and 'Some tests failed.' in style
assert '+9 -2:' in (root / 'target-2.log').read_text()
assert '+12: All tests passed!' in (root / 'target-3.log').read_text()
assert '+789: All tests passed!' in (root / 'client-tests.log').read_text()
assert 'No issues found!' in (root / 'analyze-2.log').read_text()
audit = json.loads((root / 'source-audit.json').read_text())
assert audit['source'] == manifest['source'] == '6af8897813df61ffc6476a4c0213624bb544f0d1'
assert audit['prototype_tree_unchanged'] == '1cbf605af8f03fa067a4ce8e914bb809e3a487ca'
assert len(audit['original_four_services_healthy']) == 4
assert len(audit['code17_pair_unchanged']) == 2
assert audit['no_android_or_container_resources_created']
assert audit['native_and_normal_new_package_pending']
print(json.dumps({'complete': True, 'frozen_inputs': 13,
                  'original_actual_root_failures': 6, 'style_only_live_failures': 2,
                  'targeted': 12, 'rgba_and_size_configurations': 32,
                  'whole_client': 789, 'source': manifest['source'],
                  'native_and_normal_package_acceptance': False}))
