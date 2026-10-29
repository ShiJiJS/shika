import json
import os
import re
import shlex
import subprocess
import threading
import time
import xml.etree.ElementTree as ET
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LAB = ROOT / '.dev/lf8-page-motion'
OUT = LAB / 'native-2-observer'
ADB = ROOT / '.dev/android-sdk/platform-tools/adb'


def run(args, timeout=30):
    return subprocess.check_output([str(a) for a in args], timeout=timeout)


def device(*args):
    return run([ADB, '-s', 'emulator-5558', *args])


def shell(*args):
    return device('shell', *args).decode().strip()


def save(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2) + '\n')


assert not (OUT / 'source.json').exists()
source = (LAB / 'source-ref').read_text().strip()
assert not run(['git', 'diff', '--name-only', source, '--', 'apps/mobile']).strip()
assert shell('getprop', 'sys.boot_completed') == '1'
assert device('emu', 'avd', 'name').decode().splitlines()[0] == 'video_viewer_reader_perf_36'
runtime = json.loads((OUT / 'runtime.json').read_text())
actual = json.loads(run(['docker', 'inspect', 'video-viewer-page-motion']))[0]
assert runtime['container'] == actual['Id'] and actual['State']['Running']
scales = ['window_animation_scale', 'transition_animation_scale', 'animator_duration_scale']
original = {
    'display': {k: shell('wm', k) for k in ['size', 'density']},
    'scales': {k: shell('settings', 'get', 'global', k) for k in scales},
    'secure': {'immersive_mode_confirmations': shell('settings', 'get', 'secure', 'immersive_mode_confirmations')},
    'system': {k: shell('settings', 'get', 'system', k) for k in ['font_scale', 'user_rotation', 'accelerometer_rotation']},
}
save('original-settings.json', original)
save('source.json', {'source': source, 'normal_release_apk': False, 'profile_integration': True, 'prototype_tree': run(['git', 'rev-parse', source + ':design/reference/library-first']).decode().strip(), 'runtime': runtime['container'], 'runtime_entrypoint': actual['Config']['Entrypoint'], 'runtime_command': actual['Config']['Cmd'], 'emulator_pid': runtime['emulator_pid'], 'started_at': time.time()})
shell('wm', 'size', '1170x2532')
shell('wm', 'density', '480')
shell('settings', 'put', 'system', 'font_scale', '1.0')
events, clips, errors = [], [], []
recording = None


def capture(name):
    raw = device('exec-out', 'screencap', '-p')
    assert raw.startswith(b'\x89PNG')
    (OUT / (name + '.png')).write_bytes(raw)
    window = shell('dumpsys', 'window')
    (OUT / (name + '-window.txt')).write_text('\n'.join(line.strip() for line in window.splitlines() if 'mCurrentFocus=' in line or 'mFocusedApp=' in line) + '\n')


def begin(name):
    global recording
    assert recording is None
    capture(name + '-before')
    remote = '/sdcard/lf8-page-motion-' + name + '.mp4'
    script = 'screenrecord --bit-rate 4000000 --time-limit 60 ' + remote + ' >/dev/null 2>&1 & echo $!'
    pid = shell('sh', '-c', shlex.quote(script))
    assert pid.isdigit(), pid
    assert remote in shell('cat', '/proc/' + pid + '/cmdline')
    recording = {'name': name, 'pid': pid, 'remote': remote}
    deadline = time.monotonic() + 5
    while True:
        size = subprocess.run([str(ADB), '-s', 'emulator-5558', 'shell', 'stat', '-c', '%s', remote], capture_output=True, text=True, timeout=5)
        # MediaMuxer can buffer encoded samples until stop. A written MP4
        # header proves setup; frame coverage is checked after finalization.
        if size.returncode == 0 and int(size.stdout.strip()) >= 16:
            break
        assert time.monotonic() < deadline, 'Recorder output header not ready'
        time.sleep(.1)


def end(name):
    global recording
    assert recording is not None and recording['name'] == name
    value = recording
    assert value['remote'] in shell('cat', '/proc/' + value['pid'] + '/cmdline')
    shell('kill', '-2', value['pid'])
    deadline = time.monotonic() + 10
    while subprocess.run([str(ADB), '-s', 'emulator-5558', 'shell', 'test', '-d', '/proc/' + value['pid']], stdout=subprocess.DEVNULL).returncode == 0:
        assert time.monotonic() < deadline, 'Recording did not finish'
        time.sleep(.1)
    path = OUT / (name + '.mp4')
    run([ADB, '-s', 'emulator-5558', 'pull', value['remote'], path])
    capture(name + '-after')
    metadata = json.loads(run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-count_frames', '-show_entries', 'stream=width,height,nb_read_frames:format=duration', '-of', 'json', path]))
    assert int(metadata['streams'][0]['nb_read_frames']) > 0
    run(['ffmpeg', '-v', 'error', '-i', path, '-map', '0:v:0', '-fps_mode', 'passthrough', '-enc_time_base', 'demux', '-f', 'null', '-'], timeout=40)
    clips.append({'name': name, 'metadata': metadata, 'full_decode_exit': 0})
    save('recordings.json', clips)
    shell('rm', value['remote'])
    recording = None


class Control(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_POST(self):
        if self.path != '/actions' or self.headers.get('X-Fixture-Key') != 'native-motion-owned-only':
            self.send_error(403)
            return
        length = int(self.headers.get('Content-Length', '0'))
        if not 0 < length < 8000:
            self.send_error(413)
            return
        value = json.loads(self.rfile.read(length))
        try:
            action, name = value['action'], value.get('name')
            if action == 'configure':
                assert isinstance(value['reduced'], bool)
                setting = '0' if value['reduced'] else '1'
                for key in scales:
                    shell('settings', 'put', 'global', key, setting)
                value['actual'] = {k: shell('settings', 'get', 'global', k) for k in scales}
                assert all(v == setting for v in value['actual'].values())
            elif action == 'capture':
                assert re.fullmatch('[a-z0-9-]{1,80}', name)
                capture(name)
            elif action == 'fullscreen_ready':
                remote = '/sdcard/lf8-page-motion-window.xml'
                try:
                    shell('uiautomator', 'dump', remote)
                    raw = device('exec-out', 'cat', remote)
                    root = ET.fromstring(raw)
                    titles = [n for n in root.iter('node') if n.get('package') == 'com.android.systemui' and n.get('text') == 'Viewing full screen']
                    value['education_observed'] = bool(titles)
                    if titles:
                        buttons = [n for n in root.iter('node') if n.get('package') == 'com.android.systemui' and n.get('text') == 'Got it' and n.get('clickable') == 'true']
                        assert len(buttons) == 1, 'Unexpected fullscreen education UI'
                        capture('android-fullscreen-education')
                        (OUT / 'android-fullscreen-education.xml').write_bytes(raw)
                        bounds = list(map(int, re.findall(r'\d+', buttons[0].get('bounds', ''))))
                        assert len(bounds) == 4
                        point = [(bounds[0]+bounds[2])//2, (bounds[1]+bounds[3])//2]
                        shell('input', 'tap', *map(str, point))
                        value['acknowledged_point'] = point
                finally:
                    shell('rm', '-f', remote)
            elif action == 'tap':
                point = value['point']
                assert isinstance(point, list) and len(point) == 2
                assert all(isinstance(v, int) and 0 <= v < 4096 for v in point)
                shell('input', 'tap', *map(str, point))
            elif action == 'back':
                shell('input', 'keyevent', '4')
            elif action == 'failure':
                capture('failure-' + name)
            else:
                assert action in ['begin', 'end'] and re.fullmatch('[a-z0-9-]{1,80}', name)
                (begin if action == 'begin' else end)(name)
            events.append({'time': time.time(), **value})
            save('events.json', events)
            payload = json.dumps(value).encode()
            self.send_response(200)
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            print(json.dumps(events[-1]), flush=True)
        except Exception as error:
            errors.append(repr(error))
            save('observer-errors.json', errors)
            self.send_error(500, 'Owned native observation failed')


server = ThreadingHTTPServer(('127.0.0.1', 8778), Control)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
env = {**os.environ, 'VV_READER_BENCH_OUTPUT': str(OUT)}
command = ['bash', str(ROOT / 'scripts/dev.sh'), 'flutter', 'drive', '--profile', '--use-application-binary=' + str(ROOT / '.dev/lf8-page-motion/page-motion-profile-observer.apk'), '--no-pub', '-d', 'emulator-5558', '--driver=test_driver/reader_performance.dart', '--target=integration_test/server_page_motion_test.dart']
save('command.json', {'command': command, 'cwd': str(ROOT / 'apps/mobile')})
try:
    with (OUT / 'flutter-drive.log').open('wb') as log:
        process = subprocess.Popen(command, cwd=ROOT / 'apps/mobile', env=env, stdout=log, stderr=subprocess.STDOUT)
        save('live-process.json', {'pid': process.pid})
        code = process.wait(timeout=1200)
    save('result.json', {'exit_code': code, 'observer_errors': errors, 'recordings': len(clips), 'finished_at': time.time()})
    print(json.dumps({'exit_code': code, 'recordings': len(clips), 'observer_errors': errors}), flush=True)
finally:
    server.shutdown()
    server.server_close()
    thread.join(timeout=5)
    if recording is not None:
        try:
            end(recording['name'])
        except Exception as error:
            errors.append('recording cleanup: ' + repr(error))
    restoration = {'errors': errors}
    try:
        for group, table in [('scales', 'global'), ('system', 'system'), ('secure', 'secure')]:
            for key, value in original[group].items():
                shell('settings', 'delete' if value == 'null' else 'put', table, key, *([] if value == 'null' else [shlex.quote(value)]))
        for key, value in original['display'].items():
            match = re.search('Override ' + key + ': (.+)', value)
            shell('wm', key, match.group(1) if match else 'reset')
        observed = {'secure': {'immersive_mode_confirmations': shell('settings', 'get', 'secure', 'immersive_mode_confirmations')}, 'display': {k: shell('wm', k) for k in original['display']}, 'scales': {k: shell('settings', 'get', 'global', k) for k in scales}, 'system': {k: shell('settings', 'get', 'system', k) for k in original['system']}}
        assert observed == original
        restoration['restored'] = observed
    except Exception as error:
        restoration['failure'] = repr(error)
    save('restoration.json', restoration)
