#!/usr/bin/env python3
"""Drive only the owned emulator's DocumentsUI for backup_native_files_test."""
import argparse
import json
from pathlib import Path
import queue
import re
import subprocess
import threading
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--device', required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
adb = ROOT / '.dev/android-sdk/platform-tools/adb'

def device(*command, **kwargs):
    return subprocess.run([str(adb), '-s', args.device, *command], check=True, timeout=20, **kwargs)

def ui(stage):
    device('shell', 'uiautomator', 'dump', '/sdcard/lf7-files-window.xml', stdout=subprocess.DEVNULL)
    raw = device('exec-out', 'cat', '/sdcard/lf7-files-window.xml', capture_output=True).stdout
    (args.output / f'{stage}.xml').write_bytes(raw)
    device('exec-out', 'screencap', '-p', stdout=(args.output / f'{stage}.png').open('wb'))
    return ET.fromstring(raw)

def tap(node):
    x1, y1, x2, y2 = map(int, re.findall(r'\d+', node.get('bounds')))
    device('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))

lines = queue.Queue()
log = (args.output / 'flutter.log').open('w')
process = subprocess.Popen(['bash', '../../scripts/dev.sh', 'flutter', 'test',
    'integration_test/backup_native_files_test.dart', '--no-uninstall', '-d', args.device],
    cwd=ROOT / 'apps/mobile', stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

def pump():
    for line in process.stdout:
        log.write(line); log.flush(); lines.put(line)
threading.Thread(target=pump, daemon=True).start()
started = time.monotonic()
def download_names():
    return set(device('shell', 'ls', '-1', '/sdcard/Download', capture_output=True).stdout.decode().splitlines())
before_downloads = download_names()
seen = []
try:
    while process.poll() is None or not lines.empty():
        if time.monotonic() - started > 600:
            raise TimeoutError('native file round exceeded ten minutes')
        try: line = lines.get(timeout=1)
        except queue.Empty: continue
        if 'SAF_' in line: print(line.strip(), flush=True)
        match = re.search(r'SAF_STAGE:([a-z-]+)', line)
        if not match: continue
        stage = match[1]
        seen.append(stage)
        if stage == 'programmatic-cancel': continue
        # The worker verifies 40 MiB before opening the save chooser.
        deadline = time.monotonic() + 30
        while True:
            tree = ui(stage)
            nodes = list(tree.iter('node'))
            if any(n.get('package') == 'com.google.android.documentsui' for n in nodes): break
            if time.monotonic() > deadline: raise TimeoutError('DocumentsUI did not open')
            time.sleep(.3)
        if stage in ('cancel-save', 'cancel-pick'):
            device('shell', 'input', 'keyevent', 'KEYCODE_BACK')
        elif stage == 'save-large':
            button = next(n for n in nodes if n.get('resource-id') == 'android:id/button1' and n.get('text') == 'SAVE')
            tap(button)
        else:
            file = next(n for n in nodes if n.get('text', '').startswith('video-viewer-backup') and n.get('text', '').endswith('.vvbackup'))
            tap(file)
    code = process.wait(timeout=15)
    expected = ['cancel-save', 'save-large', 'cancel-pick', 'pick-large', 'pick-over-limit', 'programmatic-cancel']
    assert code == 0 and seen == expected, (code, seen)
    text = (args.output / 'flutter.log').read_text()
    assert 'SAF_VERIFIED:bytes=42008576,sha256=' in text and 'All tests passed!' in text
    created = download_names() - before_downloads
    assert len(created) == 1 and all(n.startswith('video-viewer-backup') and n.endswith('.vvbackup') for n in created), created
    # Quote the known generated provider filename for Android's shell.
    filename = next(iter(created))
    assert all(c.isalnum() or c in ' .()-_' for c in filename), filename
    actual = device('shell', 'sha256sum', "'/sdcard/Download/" + filename + "'", capture_output=True).stdout.decode()
    expected_hash = re.search(r'SAF_VERIFIED:bytes=42008576,sha256=([a-f0-9]{64})', text)[1]
    assert actual.split()[0] == expected_hash, actual
    (args.output / 'saved-sha256.txt').write_text(actual)
    proof = {'device': args.device, 'stages': seen, 'exit_code': code,
             'elapsed_seconds': round(time.monotonic() - started, 2), 'created_document': filename, 'sha256':expected_hash}
    (args.output / 'result.json').write_text(json.dumps(proof, indent=2)+'\n')
    print(json.dumps(proof), flush=True)
finally:
    if process.poll() is None: process.terminate()
    log.close()
