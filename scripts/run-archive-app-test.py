#!/usr/bin/env python3
"""Run the real archive App fixture with isolated viewport and evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--viewport', choices=('390', '360'), required=True)
p.add_argument('--scale', choices=('1', '2'), required=True)
p.add_argument('--output', type=Path, required=True)
args = p.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
adb = ROOT / '.dev/android-sdk/platform-tools/adb'
def device(*command):
    return subprocess.check_output([str(adb), '-s', 'emulator-5554', *command], timeout=20)
def shell(*command):
    return device('shell', *command).decode().strip()
def trace():
    request = urllib.request.Request('http://127.0.0.1:8762/__archive_fixture/trace',
        headers={'X-Fixture-Key':'archive-app-isolated-control'})
    with urllib.request.urlopen(request, timeout=10) as response: return json.load(response)['items']
def save(name, value):
    (args.output/name).write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n')
old = {name:shell('wm',name) for name in ('size','density')}
old_font = shell('settings','get','system','font_scale')
def media_files():
    base = ROOT / '.dev/archive-app/media'
    return {str(f.relative_to(base)): {'bytes':f.stat().st_size,
            'sha256':hashlib.sha256(f.read_bytes()).hexdigest()}
            for f in sorted(base.rglob('*')) if f.is_file()}
previous = trace()
media_before = media_files()
save('media-before.json', media_before)
started = time.monotonic()
try:
    width, height = (390,844) if args.viewport == '390' else (360,740)
    shell('wm','size',f'{width*3}x{height*3}')
    shell('wm','density','480')
    shell('settings','put','system','font_scale','1')
    source = subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    command = ['bash',str(ROOT/'scripts/dev.sh'),'flutter','test',
        'integration_test/server_archive_app_test.dart','--no-uninstall','-d','emulator-5554',
        '--dart-define=ARCHIVE_FONT_SCALE='+args.scale]
    with (args.output/'flutter.log').open('w') as log:
        process = subprocess.run(command,cwd=ROOT/'apps/mobile',stdout=log,stderr=subprocess.STDOUT,timeout=360)
    after = trace()
    assert after[:len(previous)] == previous, 'Fixture trace changed unexpectedly'
    events = after[len(previous):]
    save('requests.json',events)
    media_after = media_files()
    save('media-after.json', media_after)
    assert media_before == media_after, 'Archive restore changed source files'
    assert process.returncode == 0, 'Android archive test failed; see flutter.log'
    log = (args.output/'flutter.log').read_text()
    assert 'ARCHIVE_APP_VERIFIED:roots=27,epoch_changed=true,snapshot=' in log and 'All tests passed!' in log
    screens = re.findall(r'ARCHIVE_SCREENSHOT:(/data/user/0/io.github.shijijs.video_viewer/files/archive-app-evidence/[a-z-]+\.png)',log)
    assert len(screens) == 5
    for path in screens:
        relative = path.split('/files/',1)[1]
        (args.output/Path(path).name).write_bytes(device('exec-out','run-as','io.github.shijijs.video_viewer','cat','files/'+relative))
    posts = [e for e in events if e['method']=='POST']
    for path, count in [('/api/v1/management-backups',1),('/api/v1/management-backups/imports',1),
        ('/api/v1/management-backups/restores',1),('/api/v1/auth/login',1)]:
        assert sum(e['path']==path for e in posts)==count, (path,posts)
    assert sum('/from-snapshot/' in e['path'] for e in posts)==1
    save('result.json',{'source':source,'viewport':[width,height], 'font_scale':int(args.scale),
        'exit_code':0,'elapsed_seconds':round(time.monotonic()-started,2),'screens':screens,
        'request_count':len(events),'restore_post_count':1,'login_post_count':1})
    print((args.output/'result.json').read_text(),flush=True)
finally:
    for name in ('size','density'):
        value = next((v.split(':',1)[1].strip() for v in old[name].splitlines() if v.startswith('Override')), 'reset')
        shell('wm',name,value)
    if old_font=='null': shell('settings','delete','system','font_scale')
    else: shell('settings','put','system','font_scale',old_font)
    save('restored-viewport.json',{'before':old,'before_font':old_font,
        'after':{n:shell('wm',n) for n in ('size','density')},'after_font':shell('settings','get','system','font_scale')})
