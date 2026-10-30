import json, os, signal, subprocess, time
from pathlib import Path

L = Path(__file__).resolve().parent
R = L.parents[1]
ADB = str(R / '.dev/android-sdk/platform-tools/adb')
meta = json.loads((L / 'device.json').read_text())
runtime = json.loads((L / 'normal/runtime.json').read_text())
original = json.loads((L / 'original-settings.json').read_text())
debug = json.loads((L / 'debug-access.json').read_text())

def run(*args):
    return subprocess.check_output(args, text=True, timeout=40).strip()

def dev(*args):
    return run(ADB, '-s', meta['serial'], *args)

def containers():
    rows = json.loads(run('docker', 'inspect', *runtime['original_containers'].values()))
    result = {}
    for row in rows:
        assert runtime['original_containers'][row['Name']] == row['Id']
        assert row['State']['Status'] == 'running'
        assert row['State']['Health']['Status'] == 'healthy'
        result[row['Name']] = {'id': row['Id'], 'status': 'running', 'health': 'healthy'}
    return result

assert not (L / 'cleanup.json').exists()
before = containers()
assert run('ps', '-p', str(meta['pid']), '-o', 'command=') == meta['command']
assert dev('emu', 'avd', 'name').splitlines()[0] == meta['avd']
dev('shell','am','force-stop','io.github.shijijs.video_viewer')
proxy=json.loads((L/'proxy-process.json').read_text());proxy_pid=proxy['pid']
assert run('ps','-p',str(proxy_pid),'-o','command=').endswith(' .dev/lf8-catalog-recovery/proxy.py')
assert run('lsof','-t','-iTCP:8778','-sTCP:LISTEN')==str(proxy_pid)
os.kill(proxy_pid,signal.SIGTERM)
proxy_end=time.monotonic()+15
while subprocess.run(['ps','-p',str(proxy_pid)],stdout=subprocess.DEVNULL).returncode==0:
    assert time.monotonic()<proxy_end
    time.sleep(.1)

for name in ['screenrecord', 'getevent']:
    p = subprocess.run([ADB, '-s', meta['serial'], 'shell', 'pidof', name], capture_output=True, text=True, timeout=15)
    assert p.returncode == 1 and not p.stdout.strip() and not p.stderr.strip(), (name, p)

for key, shell in [('size', ['wm', 'size']), ('density', ['wm', 'density'])]:
    override = [line for line in original[key].splitlines() if line.startswith('Override')]
    dev('shell', *shell, override[0].split(':', 1)[1].strip() if override else 'reset')
settings = {
    'window': ('global', 'window_animation_scale'),
    'transition': ('global', 'transition_animation_scale'),
    'animator': ('global', 'animator_duration_scale'),
    'font': ('system', 'font_scale'),
    'rotation': ('system', 'user_rotation'),
    'accel': ('system', 'accelerometer_rotation'),
    'immersive': ('secure', 'immersive_mode_confirmations'),
}
for key, (area, name) in settings.items():
    if original[key] == 'null':
        dev('shell', 'settings', 'delete', area, name)
    else:
        dev('shell', 'settings', 'put', area, name, original[key])
restored = {key: dev('shell', *shell) for key, shell in [('size', ['wm', 'size']), ('density', ['wm', 'density'])]}
restored.update({key: dev('shell', 'settings', 'get', area, name) for key, (area, name) in settings.items()})
assert restored == original, (restored, original)
if debug['temporary_root_enabled']:
    receipt = dev('unroot')
    until = time.monotonic() + 25
    while True:
        p = subprocess.run([ADB, '-s', meta['serial'], 'shell', 'id'], capture_output=True, text=True, timeout=5)
        if p.returncode == 0 and p.stdout.strip() == debug['initial_uid']:
            break
        assert time.monotonic() < until
        time.sleep(.2)
assert dev('shell', 'id') == debug['initial_uid']
dev('shell','sync')
dev('emu', 'kill')
until = time.monotonic() + 25
while subprocess.run(['ps', '-p', str(meta['pid'])], stdout=subprocess.DEVNULL).returncode == 0:
    assert time.monotonic() < until
    time.sleep(.2)

cid = runtime['container']
row = json.loads(run('docker', 'inspect', cid))[0]
assert row['Name'] == '/video-viewer-catalog-recovery-normal'
assert row['Config']['Labels']['video-viewer.lab'] == 'lf8-catalog-recovery-normal'
run('docker', 'stop', cid)
run('docker', 'rm', cid)
assert cid not in run('docker', 'ps', '-aq', '--no-trunc').splitlines()
after = containers()
assert before == after
report = {'restored_device_settings': restored, 'exact_initial_uid_restored': True,
          'qemu_pid_stopped': meta['pid'], 'container_removed': cid,
          'no_reference_preview_started': True, 'proxy_pid_stopped':proxy_pid,'guest_sync_before_stop':True, 'original_containers_before': before,
          'original_containers_after': after, 'no_live_database_opened_on_host': True}
(L / 'cleanup.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report))
