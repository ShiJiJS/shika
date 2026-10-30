import hashlib,json,subprocess,time
from pathlib import Path
L=Path(__file__).resolve().parent;R=L.parents[1];ADB=str(R/'.dev/android-sdk/platform-tools/adb');PKG='io.github.shijijs.video_viewer'
def run(*args):return subprocess.check_output(args,timeout=30,text=True).strip()
def dev(*args):return run(ADB,'-s','emulator-5556',*args)
rows=run('ps','-ax','-o','pid=,command=').splitlines();owned=[x.strip().split(None,1) for x in rows if 'qemu-system' in x and ' -avd video_viewer_upgrade_36 -port 5556 ' in x];assert len(owned)==1;pid=int(owned[0][0]);cmd=owned[0][1];assert dev('emu','avd','name').splitlines()[0]=='video_viewer_upgrade_36';assert dev('shell','id')==json.loads((L/'debug-access.json').read_text())['initial_uid']
result={'pid':pid,'command':cmd,'root_not_enabled':True,'no_reinstall_clear_or_launch':True,'after_guest_sync_stop':True,'initial_missing_apk_cause_not_proven':True};attempts=[];end=time.monotonic()+40
try:
 while True:
  p=subprocess.run([ADB,'-s','emulator-5556','shell','pm','path',PKG],capture_output=True,text=True,timeout=10);value=p.stdout.strip();attempts.append({'returncode':p.returncode,'output':value,'time':time.time()})
  if p.returncode==0 and value.count('package:')==1:
   path=value.removeprefix('package:');sha=dev('shell','sha256sum',path).split()[0];assert sha=='a0a6bb14615951ecc04329154ed15b2ede0c2c7b0ceb6a989d7bd7af05d86fb3';result.update({'package_available':True,'sha256':sha});break
  if time.monotonic()>end:result['package_available']=False;break
  time.sleep(1)
 dump=dev('shell','dumpsys','package',PKG);(L/'persistence-package.txt').write_text(dump);result['attempts']=attempts
finally:
 assert run('ps','-p',str(pid),'-o','command=')==cmd
 dev('shell','sync');dev('emu','kill');until=time.monotonic()+25
 while subprocess.run(['ps','-p',str(pid)],stdout=subprocess.DEVNULL).returncode==0:
  assert time.monotonic()<until;time.sleep(.1)
 result['owned_qemu_stopped']=True;(L/'persistence-check.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:result[k] for k in ['package_available','owned_qemu_stopped','no_reinstall_clear_or_launch']}))
