import hashlib,json,subprocess
from pathlib import Path
R=Path(__file__).resolve().parents[2];L=R/'.dev/lf8-catalog-recovery';adb=R/'.dev/android-sdk/platform-tools/adb';pkg='io.github.shijijs.video_viewer'
def device(*args):return subprocess.check_output([str(adb),'-s','emulator-5556',*args],timeout=30)
def files():
 raw=device('shell','find','/data/user/0/'+pkg,'-type','f','-exec','sha256sum','{}','+').decode();return {line[66:]:line[:64] for line in raw.splitlines() if len(line)>66}
before=files();assert before; (L/'initial-app-data-digests.json').write_text(json.dumps(before,indent=2)+'\n')
apk=R/'tmp/releases/video-viewer-0.2.0-preview.16-arm64.apk';sha=hashlib.sha256(apk.read_bytes()).hexdigest();assert sha=='a0a6bb14615951ecc04329154ed15b2ede0c2c7b0ceb6a989d7bd7af05d86fb3'
result=device('install','-r',str(apk)).decode();assert 'Success' in result
path=device('shell','pm','path',pkg).decode().strip();assert path.count('package:')==1;assert device('shell','sha256sum',path.removeprefix('package:')).decode().split()[0]==sha
after=files();(L/'after-reconcile-app-data-digests.json').write_text(json.dumps(after,indent=2)+'\n');stable=lambda values:{k:v for k,v in values.items() if '/cache/' not in k and '/code_cache/' not in k}
assert stable(before)==stable(after)
(L/'install-cache-delta.json').write_text(json.dumps({'added':sorted(set(after)-set(before)),'removed':sorted(set(before)-set(after)),'changed':[k for k in before.keys() & after.keys() if before[k]!=after[k]],'noncache_identical':True},indent=2)+'\n')
v={'package':pkg,'sha256':sha,'normal_main_preview16':True,'initial_registered_pkg_null_missing_code_path':True,'initial_data_directory_retained':True,'reinstall_r_result':result,'same_noncache_app_data_file_digests_before_launch':True,'app_data_files':len(before),'no_uninstall_or_clear':True,'not_an_independent_new_upgrade_cycle_proof':True,'cause_not_diagnosed':True};(L/'installed-apk.json').write_text(json.dumps(v,indent=2)+'\n');print(json.dumps(v))
