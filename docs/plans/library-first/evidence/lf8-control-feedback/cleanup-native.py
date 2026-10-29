import json,subprocess,time
from pathlib import Path
R=Path(__file__).resolve().parents[2];L=R/'.dev/lf8-control-feedback';O=L/'native-4';meta=json.loads((O/'runtime.json').read_text());adb=R/'.dev/android-sdk/platform-tools/adb'
def run(args):return subprocess.check_output([str(v) for v in args],text=True,timeout=30).strip()
def device(*args):return run([adb,'-s','emulator-5558',*args])
assert json.loads((L/'audit.json').read_text())['passed_cases']==36
assert '-avd video_viewer_reader_perf_36' in run(['ps','-p',meta['emulator_pid'],'-o','command='])
original=json.loads((O/'original-settings.json').read_text())
for group,table in [('scales','global'),('system','system'),('secure','secure')]:
 for k,v in original[group].items():assert device('shell','settings','get',table,k)==v
for k,v in original['display'].items():assert device('shell','wm',k)==v
receipt=device('emu','kill');end=time.monotonic()+15
while subprocess.run(['ps','-p',str(meta['emulator_pid'])],stdout=subprocess.DEVNULL).returncode==0:
 assert time.monotonic()<end;time.sleep(.2)
expected=dict(reversed(line.split()) for line in meta['original_containers'].splitlines())
for name,id in expected.items():
 v=json.loads(run(['docker','inspect',name]))[0];assert v['Id'].startswith(id) and v['State']['Running'] and v['State']['Health']['Status']=='healthy'
(L/'cleanup-native.json').write_text(json.dumps({'owned_pid':meta['emulator_pid'],'owned_qemu_absent':True,'settings_restored':True,'original_services_unchanged':expected,'no_app_server_or_database_started':True,'receipt':receipt},indent=2)+'\n');print('Owned component emulator closed; exact settings and original services preserved')
