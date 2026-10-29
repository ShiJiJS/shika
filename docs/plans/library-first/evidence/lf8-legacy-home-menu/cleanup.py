import hashlib,json,subprocess,time
from pathlib import Path
L=Path(__file__).resolve().parent;R=L.parents[1];read=lambda p:json.loads((L/p).read_text());assert read('audit.json')['complete'];dev=read('device.json');adb=R/'.dev/android-sdk/platform-tools/adb'
def run(args):return subprocess.check_output([str(v) for v in args],text=True,timeout=30).strip()
def device(*args):return run([adb,'-s','emulator-5556',*args])
def hashes(p):return {str(x.relative_to(p)):hashlib.sha256(x.read_bytes()).hexdigest() for x in p.rglob('*') if x.is_file()}
assert '-avd video_viewer_upgrade_36 -port 5556 ' in run(['ps','-p',dev['pid'],'-o','command='])
metas=[read(k+'/runtime.json') for k in ['legacy','modern']]
for m in metas:
 d=Path(m['donor']);assert hashes(d/'data')==m['donor_data_sha256'] and hashes(d/'config')==m['donor_config_sha256'];c=json.loads(run(['docker','inspect',m['container']]))[0];assert c['Config']['Labels']['video-viewer.lab']=='lf8-legacy-menu-'+m['kind'];assert all(not x['RW'] for x in c['Mounts'] if x['Destination'].startswith('/media/'))
original=read('original-settings.json');mapping={'window':('global','window_animation_scale'),'transition':('global','transition_animation_scale'),'animator':('global','animator_duration_scale'),'font':('system','font_scale'),'rotation':('system','user_rotation'),'accel':('system','accelerometer_rotation'),'immersive':('secure','immersive_mode_confirmations')}
for k,(table,key) in mapping.items():
 v=original[k]
 if device('shell','settings','get',table,key)!=v:device('shell','settings','delete',table,key) if v=='null' else device('shell','settings','put',table,key,v)
 assert device('shell','settings','get',table,key)==v
for k in ['size','density']:assert device('shell','wm',k)==original[k]
debug=read('debug-access.json');unroot=None
if debug['temporary_root_enabled']:
 unroot=device('unroot');end=time.monotonic()+25
 while True:
  p=subprocess.run([str(adb),'-s','emulator-5556','shell','id'],text=True,capture_output=True,timeout=5)
  if p.returncode==0 and p.stdout.strip()==debug['initial_uid']:break
  assert time.monotonic()<end;time.sleep(.2)
assert device('shell','id')==debug['initial_uid'];killed=device('emu','kill');end=time.monotonic()+25
while subprocess.run(['ps','-p',str(dev['pid'])],stdout=subprocess.DEVNULL).returncode==0:
 assert time.monotonic()<end;time.sleep(.2)
removed=[]
for m in metas:
 stopped=run(['docker','stop','--time','10',m['container']]);removed.append({'id':m['container'],'stopped':stopped,'removed':run(['docker','rm',m['container']])});d=Path(m['donor']);assert hashes(d/'data')==m['donor_data_sha256'] and hashes(d/'config')==m['donor_config_sha256']
for name,cid in metas[0]['original_containers'].items():
 c=json.loads(run(['docker','inspect',name]))[0];assert c['Id']==cid and c['State']['Running'] and c['State']['Health']['Status']=='healthy'
media={n:hashes(R/'.dev/lf8-preview-package/upgrade'/n) for n in ['videos','packs']};assert media==read('media-before.json')
result={'complete':True,'owned_qemu_pid':dev['pid'],'owned_qemu_absent':True,'entering_settings_restored':original,'entering_shell_uid_restored':True,'unroot_receipt':unroot,'emulator_receipt':killed,'owned_containers_gracefully_stopped_and_removed':removed,'original4_services_preserved_healthy':metas[0]['original_containers'],'both_donor_data_and_config_sha256_unchanged':True,'all_sample_media_sha256_unchanged':True,'all_data_and_apks_preserved':True,'no_nas_phone_or_real_media_operations':True};(L/'cleanup.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
