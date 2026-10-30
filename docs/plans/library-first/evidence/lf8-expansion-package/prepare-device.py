import hashlib,json,subprocess,time,shutil
from pathlib import Path
R=Path(__file__).resolve().parents[2];L=R/'.dev/lf8-expansion-package';O=L/'normal';assert O.exists();ADB=R/'.dev/android-sdk/platform-tools/adb'
def device(*args):return subprocess.check_output([str(ADB),'-s','emulator-5556',*args],text=True,timeout=30).strip()
rows=subprocess.check_output(['ps','-ax','-o','pid=,command='],text=True).splitlines();matches=[]
for r in rows:
 p=r.strip().split(None,1)
 if len(p)==2 and 'qemu-system' in p[1].split()[0] and ' -avd video_viewer_upgrade_36 -port 5556 ' in p[1]:matches.append((int(p[0]),p[1]))
assert len(matches)==1 and ' -no-audio ' in matches[0][1];assert device('emu','avd','name').splitlines()[0]=='video_viewer_upgrade_36'
meta={'pid':matches[0][0],'command':matches[0][1],'serial':'emulator-5556','avd':'video_viewer_upgrade_36'};(L/'device.json').write_text(json.dumps(meta,indent=2)+'\n')
args={'size':['wm','size'],'density':['wm','density'],'window':['settings','get','global','window_animation_scale'],'transition':['settings','get','global','transition_animation_scale'],'animator':['settings','get','global','animator_duration_scale'],'font':['settings','get','system','font_scale'],'rotation':['settings','get','system','user_rotation'],'accel':['settings','get','system','accelerometer_rotation'],'immersive':['settings','get','secure','immersive_mode_confirmations']};(L/'original-settings.json').write_text(json.dumps({k:device('shell',*v) for k,v in args.items()},indent=2)+'\n')
uid=device('shell','id');debug={'initial_uid':uid,'temporary_root_enabled':not uid.startswith('uid=0(')}
if debug['temporary_root_enabled']:
 debug['root_receipt']=device('root');end=time.monotonic()+25
 while True:
  p=subprocess.run([str(ADB),'-s','emulator-5556','shell','id'],text=True,capture_output=True,timeout=5)
  if p.returncode==0 and p.stdout.startswith('uid=0('):break
  assert time.monotonic()<end;time.sleep(.2)
(L/'debug-access.json').write_text(json.dumps(debug,indent=2)+'\n')
for name in []:
 s=(R/'.dev/lf8-menu-dropdown-package/normal'/name).read_text().replace('.dev/lf8-menu-dropdown-package/normal','.dev/lf8-expansion-package/ui')
 if name=='driver.py':
  s=s.replace("def trace_count():return len((OUT/'trace/requests.jsonl').read_text().splitlines())","def trace_count():return {k:len((OUT.parent/k/'trace/requests.jsonl').read_text().splitlines()) for k in ['legacy','modern']}")
 (O/name).write_text(s)
# Read installed APK bytes by its package-reported absolute path; no install/clear.
pkg='io.github.shijijs.video_viewer';apkpath=device('shell','pm','path',pkg);assert apkpath.count('package:')==1;actual=device('shell','sha256sum',apkpath.removeprefix('package:')).split()[0];expected='21a149b0ab8dea8bed2d2534ad718df83677cf148dd44ad23e3efbc280f1396c';assert actual==expected
(L/'installed-apk.json').write_text(json.dumps({'package':pkg,'sha256':actual,'matches_original_signed_normal_preview11':True,'no_install_clear_or_uninstall':True},indent=2)+'\n');print(json.dumps({'pid':matches[0][0],'apk_sha_verified':True,'root_temporary':debug['temporary_root_enabled']}))
