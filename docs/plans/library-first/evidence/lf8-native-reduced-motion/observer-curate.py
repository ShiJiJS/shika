import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LAB = ROOT / '.dev/lf8-native-reduced-motion'
PUBLIC = ROOT / 'docs/plans/library-first/evidence/lf8-native-reduced-motion'
ATTEMPTS = ['native-1', 'native-2-enabled', 'native-3-recorder', 'native-4-host', 'native-5-canvas', 'native-6-lifecycle', 'native-7-adb', 'native-8-system-hint', 'native-9-current-elements']

def read(path):
    return json.loads(path.read_text())

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')

assert not PUBLIC.exists()
assert read(LAB / 'cleanup.json')['owned_emulator_absent']
assert not subprocess.check_output(['git', 'diff', '--name-only', 'd520d684', '--', 'apps/mobile/lib', 'apps/mobile/android', 'services/server']).strip()
PUBLIC.mkdir()
requests = [json.loads(line) for line in (LAB / 'native-1/trace/requests.jsonl').read_text().splitlines()]
for name in ATTEMPTS:
    src, dst = LAB / name, PUBLIC / name
    dst.mkdir()
    assert (src / 'restoration.json').exists()
    for path in src.iterdir():
        if path.is_file() and (path.suffix in ['.json', '.png', '.mp4', '.xml'] or path.name.endswith('-window.txt')):
            shutil.copyfile(path, dst / path.name)
    source, result = read(src / 'source.json'), read(src / 'result.json')
    window = [v for v in requests if source['started_at'] <= v['time'] <= result['finished_at']]
    (dst / 'requests-window.jsonl').write_text(''.join(json.dumps(v) + '\n' for v in window))
    provenance = {}
    for filename in ['emulator.log', 'flutter-drive.log']:
        path = src / filename
        if not path.exists():
            continue
        raw = path.read_bytes()
        content = raw.decode(errors='replace')
        if filename == 'emulator.log':
            lines = content.splitlines()
            kept = [line for line in lines if 'Sending adb public key' not in line and 'qemu.adb.pubkey=' not in line]
            count = len(lines) - len(kept)
            content = '\n'.join(kept) + '\n'
        else:
            content, count = re.subn(r'(?:https?|wss?)://(?:127\.0\.0\.1|localhost|\[::1\]):\d+/[^\s]+', '<redacted-local-vm-service>', content)
        target = dst / filename.replace('.log', '.redacted.log')
        target.write_text(content)
        provenance[filename] = {'original_sha256': hashlib.sha256(raw).hexdigest(), 'redacted_sha256': sha(target), 'redaction_count': count}
    save(dst / 'log-provenance.json', provenance)
for name in ['profile-artifact.json', 'profile-artifact-d00f.json', 'profile-artifact-0ff5.json', 'profile-artifact-adb.json', 'profile-artifact-hint.json', 'profile-artifact-current.json', 'cleanup.json', 'audit.json', 'player-tests.log', 'analyze-current.log']:
    shutil.copyfile(LAB / name, PUBLIC / name)
# These host scripts are observation provenance, not a production command entry.
for name in ['run.py', 'run-enabled.py', 'run-recorder.py', 'run-host.py', 'run-canvas.py', 'run-lifecycle.py', 'run-adb.py', 'run-hint.py', 'run-current.py']:
    shutil.copyfile(LAB / name, PUBLIC / ('observer-' + name))
artifacts = read(ROOT / '.dev/lf8-preview3/build-1/result.json')
unchanged = {}
for kind in ['forward', 'rollback']:
    value = artifacts[kind]
    assert sha(Path(value['path'])) == value['sha256']
    unchanged[kind] = {'filename': Path(value['path']).name, 'sha256': value['sha256']}
source = {'source': (LAB / 'source-ref').read_text().strip(), 'base': 'd520d6849f40fe62fe93e25198ada67221983420', 'production_unchanged': True, 'prototype_tree': subprocess.check_output(['git', 'rev-parse', 'HEAD:design/reference/library-first'], text=True).strip(), 'normal_code9_artifacts_unchanged': unchanged, 'normal_release_acceptance': False, 'phone_or_nas_acceptance': False, 'audio_playback_acceptance': False, 'all_attempts_preserved': ATTEMPTS}
assert source['prototype_tree'] == '1cbf605af8f03fa067a4ce8e914bb809e3a487ca'
save(PUBLIC / 'source.json', source)
print(json.dumps({'public': str(PUBLIC), 'source': source}))
