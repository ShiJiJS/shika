import hashlib,json,subprocess,time
from pathlib import Path
L=Path(__file__).resolve().parent;R=L.parents[1];O=L/'normal';H=L/'history-normal';read=lambda p:json.loads(p.read_text());meta=read(O/'runtime.json');hist=read(H/'runtime.json');adb=R/'.dev/android-sdk/platform-tools/adb'
def run(args):return subprocess.check_output([str(x) for x in args],text=True,timeout=30).strip()
def device(*args):return run([adb,'-s','emulator-5556',*args])
assert read(L/'package-audit.json')['complete'] and read(L/'rollback-business-audit.json')['complete']
assert '-avd video_viewer_upgrade_36 -port 5556 ' in run(['ps','-p',meta['emulator_pid'],'-o','command='])
# Verify resources and donor before making cleanup mutations.
for name,cid in hist['original_containers'].items():
 c=json.loads(run(['docker','inspect',name]))[0];assert c['Id']==cid and c['State']['Running'] and c['State']['Health']['Status']=='healthy'
for rel,sha in meta['donor_hashes'].items():assert hashlib.sha256((Path(meta['donor'])/'data'/rel).read_bytes()).hexdigest()==sha
for d,label in [(hist,'lf8-menu-dropdown-history'),(meta,'lf8-menu-dropdown-normal')]:
 c=json.loads(run(['docker','inspect',d['container']]))[0];assert c['Config']['Labels']['video-viewer.lab']==label
original=read(O/'original-settings.json');mapping={'window':('global','window_animation_scale'),'transition':('global','transition_animation_scale'),'animator':('global','animator_duration_scale'),'font':('system','font_scale'),'rotation':('system','user_rotation'),'accel':('system','accelerometer_rotation'),'immersive':('secure','immersive_mode_confirmations')}
for k,(table,name) in mapping.items():
 v=original[k]
 if device('shell','settings','get',table,name)!=v:device('shell','settings','delete',table,name) if v=='null' else device('shell','settings','put',table,name,v)
 assert device('shell','settings','get',table,name)==v
for k in ['size','density']:assert device('shell','wm',k)==original[k]
debug=read(O/'debug-access.json');unroot=None
if debug['temporary_root_enabled']:
 unroot=device('unroot');end=time.monotonic()+25
 while True:
  p=subprocess.run([str(adb),'-s','emulator-5556','shell','id'],capture_output=True,text=True,timeout=5)
  if p.returncode==0 and p.stdout.strip()==debug['initial_uid']:break
  assert time.monotonic()<end;time.sleep(.2)
uid=p.stdout.strip() if debug['temporary_root_enabled'] else device('shell','id');assert uid==debug['initial_uid']
receipt=device('emu','kill');end=time.monotonic()+25
while subprocess.run(['ps','-p',str(meta['emulator_pid'])],stdout=subprocess.DEVNULL).returncode==0:
 assert time.monotonic()<end;time.sleep(.2)
removed=[]
for d in [hist,meta]:
 removed.append({'id':d['container'],'receipt':run(['docker','rm','-f',d['container']])})
# Check only the original services; all test data and APKs stay on disk.
for name,cid in meta['original_containers'].items():
 c=json.loads(run(['docker','inspect',name]))[0];assert c['Id']==cid and c['State']['Running'] and c['State']['Health']['Status']=='healthy'
for rel,sha in meta['donor_hashes'].items():assert hashlib.sha256((Path(meta['donor'])/'data'/rel).read_bytes()).hexdigest()==sha
result={'complete':True,'owned_qemu_pid':meta['emulator_pid'],'owned_qemu_absent':True,'entering_settings_restored':original,'entering_uid_restored':True,'unroot_receipt':unroot,'emulator_receipt':receipt,'owned_containers_removed_secondary_first':removed,'original4_services_preserved_healthy':meta['original_containers'],'donor_12_files_unchanged':True,'all_data_and_apks_preserved':True,'no_nas_phone_or_real_media_operations':True}
(L/'cleanup.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
