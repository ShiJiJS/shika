import hashlib
import json
import shutil
import socket
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / '.dev/lf8-page-motion/native-1'
DONOR = ROOT / '.dev/lf8-preview3/native'
ADB = ROOT / '.dev/android-sdk/platform-tools/adb'
assert not OUT.exists()
assert not subprocess.check_output(['docker', 'ps', '-aq', '--filter', 'name=^/video-viewer-preview3-native$']).strip()
assert 'emulator-5558' not in subprocess.check_output([str(ADB), 'devices'], text=True)
for port in [8777, 8778]:
    with socket.socket() as guard:
        guard.bind(('127.0.0.1', port))
before = subprocess.check_output(['docker', 'ps', '--format', '{{.ID}} {{.Names}}'], text=True)
OUT.mkdir()
for name in ['data', 'config', 'observe']:
    shutil.copytree(DONOR / name, OUT / name)
hashes = {str(p.relative_to(DONOR / 'data')): hashlib.sha256(p.read_bytes()).hexdigest() for p in (DONOR / 'data').rglob('*') if p.is_file()}
assert hashes == {str(p.relative_to(OUT / 'data')): hashlib.sha256(p.read_bytes()).hexdigest() for p in (OUT / 'data').rglob('*') if p.is_file()}
(OUT / 'config/passphrase').write_text('native-motion-owned-only\n')
(OUT / 'trace').mkdir()
command = [
    'docker', 'run', '-d', '--name', 'video-viewer-page-motion',
    '--label', 'video-viewer.lab=lf8-page-motion', '--read-only',
    '--user', '501:20', '--tmpfs', '/tmp:mode=1777', '-p', '127.0.0.1:8777:8760',
]
for host, target, mode in [
    (OUT / 'config', '/fixture', 'ro'), (OUT / 'observe', '/observe', 'ro'),
    (OUT / 'trace', '/trace', 'rw'), (OUT / 'data', '/data', 'rw'),
    (ROOT / '.dev/lf8-preview-package/upgrade/videos', '/media/videos', 'ro'),
    (ROOT / '.dev/lf8-preview-package/upgrade/packs', '/media/packs', 'ro'),
]:
    command += ['-v', f'{host}:{target}:{mode}']
for value in ['PYTHONPATH=/app:/observe', 'VV_PASSPHRASE_FILE=/fixture/passphrase', 'VV_MOUNTS_FILE=/fixture/mounts.json', 'VV_SCAN_INTERVAL=0', 'VV_STABILITY_SECONDS=0']:
    command += ['-e', value]
command += ['--entrypoint', 'uvicorn', 'sha256:886b79b72ecb9116087d892f230471943121f24ccef093113cc3197b4607fef4', 'video_viewer.app:create_app', '--factory', '--host', '0.0.0.0', '--port', '8760', '--workers', '1', '--log-config', '/observe/logging.json']
container = subprocess.check_output(command, text=True).strip()
launch = ['bash', str(ROOT / 'scripts/dev.sh'), str(ROOT / '.dev/android-sdk/emulator/emulator'), '-avd', 'video_viewer_reader_perf_36', '-port', '5558', '-no-boot-anim', '-gpu', 'host', '-feature', '-Vulkan', '-feature', '-GLDMA', '-feature', 'HardwareDecoder', '-no-snapshot', '-no-metrics', '-crash-report-mode', 'never', '-no-window', '-no-audio']
with (OUT / 'emulator.log').open('wb') as log:
    emulator = subprocess.Popen(launch, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
value = {'container': container, 'command': command, 'emulator_launch': launch, 'emulator_pid': emulator.pid, 'original_containers': before, 'source_donor_inactive': True, 'donor_hashes': hashes, 'data_copy_verified': True, 'same_avd_data_no_wipe': True, 'created_at': time.time()}
(OUT / 'runtime.json').write_text(json.dumps(value, indent=2) + '\n')
print(json.dumps(value))
