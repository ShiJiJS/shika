import json,re,subprocess
import api,helpers as f,media,ui
from snapshot_all import snapshot
L=ui.L;state=json.loads((L/'native-read-state.json').read_text());assert state['phase']=='first_tag_read_verified'
files=media.files();before=snapshot('normal26','before-native-cold-read')
pid=ui.device('shell','pidof',ui.PACKAGE).decode().strip();assert pid.isdigit()
boot=ui.device('shell','cat','/proc/sys/kernel/random/boot_id')
state.update(phase='force_stop_planned',old_app_pid=pid);(L/'native-read-state.json').write_text(json.dumps(state,indent=2))
ui.device('shell','am','force-stop',ui.PACKAGE)
try:left=ui.device('shell','pidof',ui.PACKAGE).decode().strip()
except subprocess.CalledProcessError as error:assert error.returncode==1;left=''
assert not left
assert not re.search(r'^\s*'+pid+r'\s',ui.device('shell','ps','-A','-o','PID,NAME').decode(),re.M)
ui.record({'action':'force-stop','old_app_pid':pid,'old_pid_absent':True})
state['phase']='force_stopped';(L/'native-read-state.json').write_text(json.dumps(state,indent=2))
f.cold_open();newpid=ui.device('shell','pidof',ui.PACKAGE).decode().strip();assert newpid.isdigit() and newpid!=pid
assert ui.device('shell','cat','/proc/sys/kernel/random/boot_id')==boot
ui.record({'action':'cold-open','new_app_pid':newpid,'same_android_boot':True});ui.snap('09-cold-library-after-scan')
ui.choose('最近');ui.choose('图包');f.until(lambda n:any('Restore-partial' in x for x in f.labels(n)) and any('Restore-read-tall' in x for x in f.labels(n)),'cold recovered recent');ui.snap('10-cold-recent-three-packs')
f.prefix('Restore-read-tall\n');f.until(lambda n:'阅读设置' in f.labels(n),'cold original tall page');ui.snap('11-cold-tall-row13-offset')
pack=api.call('GET','/api/v1/packs/'+state['pack_id']);assert pack['progress']['page_id']==state['page_id'] and pack['progress']['offset_ratio']==.45
ui.device('shell','input','keyevent','4');f.until(lambda n:'最近看过' in f.labels(n),'cold reader back to recent');ui.snap('12-cold-return-recent')
final=api.call('GET','/api/v1/packs/'+state['pack_id']);assert final['progress']['page_id']==state['page_id'] and final['progress']['offset_ratio']==.45
assert api.call('GET','/api/v1/recent?kind=pack')['total']==3
assert media.files()==files
trace=[json.loads(x) for x in (L/'requests.jsonl').read_text().splitlines()]
reads=[r for r in trace if r['path']=='/api/v1/pages/'+state['page_id']+'/image'];assert len(reads)>=2 and all(r['status']==200 for r in reads)
sessions=[r['command'] for r in trace if r['path']=='/api/v1/pack-sessions' and r['method']=='POST' and r.get('command',{}).get('anchor_pack_id')==state['pack_id']]
assert [s['source'] for s in sessions]==['tags','recent']
assert sessions[0]['scope']['tag_ids'] and not sessions[1]['scope']['tag_ids']
assert len([r for r in trace if r['method']=='POST' and r['path']=='/api/v1/scans'])==1
assert not [r for r in trace if r['method']=='POST' and r['path'].startswith(('/api/v1/pack-trash/permanent','/api/v1/pack-restore'))]
snapshot('normal26','after-native-cold-read-and-back')
state.update(phase='native_cold_read_verified',new_app_pid=newpid,old_pid_absent=True,same_android_boot_no_emulator_reboot=True,cold_progress=pack['progress'],after_back_progress=final['progress'],native_image_reads_200=len(reads),native_tall_sources=['tags','recent'],recent_total=3,all_49_files_unchanged=True,no_native_delete_restore_post=True)
(L/'native-read-state.json').write_text(json.dumps(state,indent=2));print({'old_app_pid':pid,'new_app_pid':newpid,'same_android_boot':True,'same_page':state['page_id'],'cold_and_back_offset':.45,'recent_total':3,'native_image_200_count':len(reads)},flush=True)
