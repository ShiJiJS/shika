"""Verify pinned source, raw log integrity and this stage's measured assertions."""

import hashlib
import json
import re
import subprocess
from pathlib import Path

folder = Path(__file__).resolve().parent
root = folder.parents[4]
manifest = json.loads((folder / 'manifest.json').read_text())
for name, digest in manifest['inputs'].items():
    assert hashlib.sha256((folder / name).read_bytes()).hexdigest() == digest, name
source = json.loads((folder / 'source.json').read_text())
for name, digest in source['files'].items():
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == digest, name
    committed = subprocess.check_output(['git', 'show', source['commit'] + ':' + name], cwd=root)
    assert hashlib.sha256(committed).hexdigest() == digest, name
assert subprocess.check_output(['git', 'rev-parse', source['commit'] + ':services/server'], cwd=root, text=True).strip() == source['server_tree']
for ref in ('HEAD', 'design-lf-2026-10-23'):
    assert subprocess.check_output(['git', 'rev-parse', ref + ':design/reference/library-first'], cwd=root, text=True).strip() == '1cbf605af8f03fa067a4ce8e914bb809e3a487ca'
full = (folder / 'server-full.log').read_text()
assert re.search(rf"\b{manifest['expected_server_tests']} passed, 1 warning in ", full)
assert not re.search(r'^FAILED |^ERROR |^=+ FAILURES ', full, re.M)
process = (folder / 'process-http.log').read_text()
assert re.search(r'\b4 passed, 1 warning in ', process)
checkpoints = [json.loads(v) for v in re.findall(r'\{"phase":.*?\}', process)]
assert len(checkpoints) == 3
assert {v['phase'] for v in checkpoints} == {'snapshot_written', 'after_replace_before_commit', 'restore_committed'}
assert all(v['fault'] == 'SIGKILL' and all(v[k] is True for k in ('recovered_once', 'snapshot_download', 'source_hash_preserved', 'retired_post_blocked')) for v in checkpoints)
metrics = re.findall(r'VV_MANAGEMENT_HTTP_MEMORY (\{.*\})', process)
assert len(metrics) == 1
memory = json.loads(metrics[0])
assert memory['archive_bytes'] > 32 * 1024 * 1024
assert memory['server_python_peak_bytes'] < 32 * 1024 * 1024
assert memory['limit_bytes'] == 64 * 1024 * 1024
assert memory['restored_note_tasks'] == 18000 and memory['source_hash_preserved'] is True
assert (folder / 'ruff.log').read_text().strip() == 'All checks passed!'
assert 'VV_COMPILE_OK' in (folder / 'compile.log').read_text()
print(json.dumps({'verified': True, 'source': source['commit'], 'server_tests': manifest['expected_server_tests'], 'sigkill_checkpoints': len(checkpoints), **memory}, ensure_ascii=False, indent=2))
