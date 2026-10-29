import json,subprocess,time
from pathlib import Path
L=Path(__file__).resolve().parent;R=L.parents[1];O=L/'native-1';read=lambda p:json.loads(p.read_text());meta=read(O/'runtime.json');adb=R/'.dev/android-sdk/platform-tools/adb'
def run(args):return subprocess.check_output([str(x) for x in args],text=True,timeout=30).strip()
def device(*args):return run([adb,'-s','emulator-5558',*args])
assert read(L/'audit.json')['complete']
assert '-avd video_viewer_reader_perf_36' in run(['ps','-p',meta['emulator_pid'],'-o','command='])
original=read(O/'original-settings.json')
for group,table in [('scales','global'),('system','system'),('secure','secure')]:
 for k,v in original[group].items():assert device('shell','settings','get',table,k)==v
for k,v in original['display'].items():assert device('shell','wm',k)==v
receipt=device('emu','kill');end=time.monotonic()+20
while subprocess.run(['ps','-p',str(meta['emulator_pid'])],stdout=subprocess.DEVNULL).returncode==0:
 assert time.monotonic()<end;time.sleep(.2)
expected=dict(reversed(line.split()) for line in meta['original_containers'].splitlines())
for name,id in expected.items():
 v=json.loads(run(['docker','inspect',name]))[0];assert v['Id'].startswith(id) and v['State']['Running'] and v['State']['Health']['Status']=='healthy'
(L/'cleanup.json').write_text(json.dumps({'owned_qemu_pid':meta['emulator_pid'],'owned_qemu_absent':True,'settings_restored':True,'original_services_preserved':expected,'no_app_server_or_media_operations':True,'receipt':receipt},indent=2)+'\n');print('Owned emulator closed; settings and four original services preserved')
