import hashlib,json,shlex,subprocess,time
from pathlib import Path
L=Path(__file__).resolve().parent;R=L.parents[1];O=L/'normal';read=lambda p:json.loads(p.read_text());meta=read(O/'runtime.json');ADB=R/'.dev/android-sdk/platform-tools/adb'
def run(args):return subprocess.check_output([str(v) for v in args],text=True,timeout=30).strip()
def device(*args):return run([ADB,'-s','emulator-5556',*args])
assert read(L/'package-audit.json')['complete'];pid=meta['emulator_pid'];cmd=run(['ps','-p',pid,'-o','command=']);assert ' -avd video_viewer_upgrade_36 ' in cmd and ' -no-audio ' in cmd
device('shell','am','force-stop','io.github.shijijs.video_viewer');original=read(O/'original-settings.json')
for key,orig in [('window_animation_scale','window'),('transition_animation_scale','transition'),('animator_duration_scale','animator')]:
 value=original[orig];device('shell','settings','delete' if value=='null' else 'put','global',key,*([] if value=='null' else [value]));assert device('shell','settings','get','global',key)==value
for key,orig in [('font_scale','font'),('user_rotation','rotation'),('accelerometer_rotation','accel')]:
 value=original[orig];device('shell','settings','delete' if value=='null' else 'put','system',key,*([] if value=='null' else [value]));assert device('shell','settings','get','system',key)==value
value=original['immersive'];device('shell','settings '+('delete secure immersive_mode_confirmations' if value=='null' else 'put secure immersive_mode_confirmations '+shlex.quote(value)));assert device('shell','settings','get','secure','immersive_mode_confirmations')==value
for k in ['size','density']:assert device('shell','wm',k)==original[k]
receipt=device('unroot');end=time.monotonic()+20
while True:
 p=subprocess.run([str(ADB),'-s','emulator-5556','shell','id'],capture_output=True,text=True,timeout=5)
 if p.returncode==0 and p.stdout.strip()==read(O/'debug-access.json')['initial_uid']:break
 assert time.monotonic()<end;time.sleep(.2)
shutdown=device('emu','kill');end=time.monotonic()+20
while subprocess.run(['ps','-p',str(pid)],stdout=subprocess.DEVNULL).returncode==0:
 assert time.monotonic()<end;time.sleep(.2)
name='video-viewer-settings-normal';c=json.loads(run(['docker','inspect',name]))[0];assert c['Id']==meta['container'] and c['Config']['Labels']['video-viewer.lab']=='lf8-settings-normal';run(['docker','stop','--time','10',name]);run(['docker','rm',name])
for name,id in meta['original_containers'].items():
 v=json.loads(run(['docker','inspect',name]))[0];assert v['Id']==id and v['State']['Running'] and v['State']['Health']['Status']=='healthy'
donor=Path(meta['donor']);active=json.loads(run(['docker','inspect',*run(['docker','ps','-q']).split()]))
for c in active:
 for m in c['Mounts']:
  s=Path(m['Source']);assert not (donor.resolve().is_relative_to(s) or s.is_relative_to(donor.resolve()))
for rel,h in meta['donor_hashes'].items():assert hashlib.sha256((donor/'data'/rel).read_bytes()).hexdigest()==h,rel
result={'complete':True,'owned_qemu_pid':pid,'owned_qemu_absent':True,'settings_restored':True,'temporary_debug_root_reverted':True,'unroot_receipt':receipt,'emulator_shutdown':shutdown,'owned_container_removed':meta['container'],'original_containers_preserved':meta['original_containers'],'donor_hashes_preserved':True,'all_lab_files_and_apks_retained':True,'no_nas_or_real_media_actions':True}
(L/'package-cleanup.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
