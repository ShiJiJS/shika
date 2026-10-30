import hashlib,json,subprocess,time
from pathlib import Path
L=Path(__file__).resolve().parent;R=L.parents[1];read=lambda p:json.loads(p.read_text());meta=read(L/'normal/runtime.json');device_meta=read(L/'device.json');adb=R/'.dev/android-sdk/platform-tools/adb'
def run(a):return subprocess.check_output([str(x) for x in a],text=True,timeout=30).strip()
def device(*args):return run([adb,'-s','emulator-5556',*args])
assert read(L/'business-audit.json')['complete'];assert ' -avd video_viewer_upgrade_36 -port 5556 ' in run(['ps','-p',device_meta['pid'],'-o','command='])
for name,cid in meta['original_containers'].items():
 c=json.loads(run(['docker','inspect',name]))[0];assert c['Id']==cid and c['State']['Health']['Status']=='healthy'
for m,kind in [(meta,'normal')]:
 c=json.loads(run(['docker','inspect',m['container']]))[0];assert c['Config']['Labels']['video-viewer.lab']=='lf8-expansion-'+kind
 for part,key in [('data','donor_data_sha256'),('config','donor_config_sha256')]:
  actual={str(p.relative_to(Path(m['donor'])/part)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(m['donor'])/part).rglob('*') if p.is_file()};assert actual==m[key]
media_before=read(L/'media-before.json')
for part,expected in media_before.items():
 actual={str(p.relative_to(R/'.dev/lf8-preview-package/upgrade'/part)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (R/'.dev/lf8-preview-package/upgrade'/part).rglob('*') if p.is_file()};assert actual==expected
 copy={str(p.relative_to(L/'media'/part)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (L/'media'/part).rglob('*') if p.is_file() and p.name!='Expansion-probe.mp4'};assert copy==expected
pkg='io.github.shijijs.video_viewer';actual=device('shell','pm','path',pkg);assert actual.count('package:')==1
actual_sha=device('shell','sha256sum',actual.removeprefix('package:')).split()[0];assert actual_sha==read(L/'build-1/result.json')['forward']['sha256']
(L/'installed-final-apk.json').write_text(json.dumps({'package':pkg,'sha256':actual_sha,'normal_code':18,'same_as_delivered_forward':True},indent=2)+'\n')
device('shell','am','force-stop','io.github.shijijs.video_viewer')
original=read(L/'original-settings.json');mapping={'window':('global','window_animation_scale'),'transition':('global','transition_animation_scale'),'animator':('global','animator_duration_scale'),'font':('system','font_scale'),'rotation':('system','user_rotation'),'accel':('system','accelerometer_rotation'),'immersive':('secure','immersive_mode_confirmations')}
for key,(table,name) in mapping.items():
 value=original[key]
 if device('shell','settings','get',table,name)!=value:
  if value=='null':device('shell','settings','delete',table,name)
  else:device('shell','settings','put',table,name,value)
 assert device('shell','settings','get',table,name)==value
for key in ['size','density']:
 if device('shell','wm',key)!=original[key]:
  override=next((line.split(':',1)[1].strip() for line in original[key].splitlines() if line.startswith('Override ')),None);device('shell','wm',key,override or 'reset')
 assert device('shell','wm',key)==original[key]
debug=read(L/'debug-access.json');receipt=None
if debug['temporary_root_enabled']:
 receipt=device('unroot');end=time.monotonic()+30
 while True:
  p=subprocess.run([str(adb),'-s','emulator-5556','shell','id'],capture_output=True,text=True,timeout=5)
  if p.returncode==0 and p.stdout.strip()==debug['initial_uid']:break
  assert time.monotonic()<end;time.sleep(.2)
assert device('shell','id')==debug['initial_uid']
emulator=device('emu','kill');end=time.monotonic()+25
while subprocess.run(['ps','-p',str(device_meta['pid'])],stdout=subprocess.DEVNULL).returncode==0:
 assert time.monotonic()<end;time.sleep(.2)
removed=[]
for m in [meta]:
 stopped=run(['docker','stop','--timeout','10',m['container']]);removed.append({'id':m['container'],'stop':stopped,'remove':run(['docker','rm',m['container']])})
ids=run(['docker','ps','-q']).split();active=json.loads(run(['docker','inspect',*ids]));assert {c['Name']:c['Id'] for c in active}==meta['original_containers'] and all(c['State']['Health']['Status']=='healthy' for c in active)
result={'complete':True,'owned_qemu_pid':device_meta['pid'],'owned_qemu_absent':True,'settings_restored':original,'entering_uid_restored':True,'unroot_receipt':receipt,'emulator_receipt':emulator,'owned_containers_gracefully_removed':removed,'original4_services_preserved_healthy':meta['original_containers'],'donor_preserved':True,'all_media_data_and_apks_retained':True,'no_nas_phone_or_real_media_operations':True};(L/'cleanup.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
