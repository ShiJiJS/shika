import json,subprocess,time
from pathlib import Path
L=Path(__file__).resolve().parent;R=L.parents[1];O=L/'native-4';read=lambda p:json.loads(p.read_text());meta=read(O/'runtime.json');ADB=R/'.dev/android-sdk/platform-tools/adb'
def run(args):return subprocess.check_output([str(v) for v in args],text=True,timeout=30).strip()
def device(*args):return run([ADB,'-s','emulator-5558',*args])
assert read(L/'audit-native.json')['complete'];pid=meta['emulator_pid'];assert ' -avd video_viewer_reader_perf_36 ' in run(['ps','-p',pid,'-o','command='])
original=read(O/'original-settings.json')
for group,table in [('scales','global'),('system','system'),('secure','secure')]:
 for k,v in original[group].items():assert device('shell','settings','get',table,k)==v
for k,v in original['display'].items():assert device('shell','wm',k)==v
assert device('shell','id')==meta['entering_uid']
assert run(['ps','-p',pid,'-o','command='])==meta['emulator_command']
receipt=device('emu','kill');end=time.monotonic()+20
while subprocess.run(['ps','-p',str(pid)],stdout=subprocess.DEVNULL).returncode==0:
 assert time.monotonic()<end;time.sleep(.2)
for name,id in meta['original_container_ids'].items():
 c=json.loads(run(['docker','inspect',name]))[0];assert c['Id']==id and c['State']['Running'] and c['State']['Health']['Status']=='healthy'
(L/'cleanup-native.json').write_text(json.dumps({'complete':True,'owned_qemu_pid':pid,'owned_qemu_absent':True,'settings_restored':True,'original4_services_preserved_healthy':meta['original_container_ids'],'no_app_server_or_media_operations':True,'no_adb_root_or_unroot_commands':True,'all_artifacts_retained':True,'receipt':receipt},indent=2)+'\n');print('Owned emulator closed, entering configuration and original four services preserved')
