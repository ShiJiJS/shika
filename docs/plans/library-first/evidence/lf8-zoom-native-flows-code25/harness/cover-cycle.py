import sys,json,re,hashlib,time,subprocess
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import ui
from snapshot_all import snapshot
checks=json.loads((ui.ROOT/'docs/plans/library-first/evidence/lf8-vertical-strip-zoom/checks.json').read_text());records=[]
def package(name):
 raw=ui.device('shell','dumpsys','package',ui.PACKAGE).decode();(ui.L/(name+'-package.txt')).write_text(raw);v={k:re.search(r'\b'+k+r'=([^\n]+)',raw).group(1).strip() for k in ['versionCode','versionName','firstInstallTime','lastUpdateTime','dataDir','appId']};return v
def pref(name):
 path='/data/user/0/'+ui.PACKAGE+'/files/appearance.json';exists=subprocess.run([str(ui.ADB),'-s','emulator-5554','shell','test','-f',path],capture_output=True).returncode==0;v=json.loads(ui.device('exec-out','cat',path)) if exists else {'file_absent':True};(ui.L/(name+'-appearance.json')).write_text(json.dumps(v,indent=2)+'\n');return v
def install(kind,expected):
 entry=checks[kind+'_code25'];p=Path(entry['path']);assert hashlib.sha256(p.read_bytes()).hexdigest()==entry['sha256'];b=package(kind+'25-before');ui.device('shell','am','force-stop',ui.PACKAGE);out=ui.device('install','-r',str(p)).decode();assert 'Success' in out;a=package(kind+'25-after')
 for k in ['firstInstallTime','dataDir','appId']:assert a[k]==b[k]
 assert re.match(r'25\b',a['versionCode']);assert a['versionName']==entry['version'];base=ui.device('shell','pm','path',ui.PACKAGE).decode().strip().removeprefix('package:');assert hashlib.sha256(ui.device('exec-out','cat',base)).hexdigest()==entry['sha256'];ui.device('shell','am','start','-n',ui.PACKAGE+'/.MainActivity');deadline=time.monotonic()+50
 while True:
  _,nodes=ui.xml()
  if any((v.get('content-desc') or v.get('text'))==expected for v in nodes):break
  assert time.monotonic()<deadline
 ui.snap('35-cover-rollback25' if kind=='rollback' else '36-cover-normal25');records.append({'kind':kind,'before':b,'after':a,'actual_installed_sha256':entry['sha256'],'no_uninstall_or_clear':True});print({'installed':kind,'entry_verified':expected},flush=True)
before=json.loads((ui.L/'cover-before-rollback25-all-catalog.json').read_text());preferences=pref('cover-before');install('rollback','视频库');old=snapshot('rollback25','cover-after-rollback25');assert pref('cover-after-rollback')==preferences
protected=[k for k in before['tables'] if k.startswith('pack') or k in ['tags','video_tags','file_operations','file_steps','trash_items','roots']]
for k in protected:assert old['tables'][k]==before['tables'][k],k
install('normal','媒体库');after=snapshot('new25','cover-after-normal25');assert pref('cover-after-normal')==preferences
for k in ['tables','opaque_table_digests','setting_key_sha256']:assert old[k]==after[k],k
(ui.L/'cover-cycle-checks.json').write_text(json.dumps({'cycles':records,'protected_business_tables':protected,'protected_tables_equal_through_rollback':True,'normal_reopen_all_35_tables_and_settings_equal_to_after_old_start':True,'appearance_equal':True,'old_start_changed_tables':[k for k in before['tables'] if old['tables'][k]!=before['tables'][k]],'old_start_changed_settings':[k for k in set(old['setting_key_sha256'])|set(before['setting_key_sha256']) if old['setting_key_sha256'].get(k)!=before['setting_key_sha256'].get(k)],'server':'new 430fede5, not old-service compatibility','visual_review':'pending'},indent=2)+'\n');print('Normal25 -> rollback25 -> normal25 actual covers passed with pack data/identity/preferences preserved',flush=True)
