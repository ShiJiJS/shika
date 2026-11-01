import json,re,subprocess
import api,helpers as f,media,ui
from snapshot_all import snapshot
L=ui.L;state=json.loads((L/'tall-native-state.json').read_text());assert state['phase']=='first_native_read_open'
before=media.files();pid=ui.device('shell','pidof',ui.PACKAGE).decode().strip();assert pid.isdigit();ui.device('shell','am','force-stop',ui.PACKAGE)
try:remaining=ui.device('shell','pidof',ui.PACKAGE).decode().strip()
except subprocess.CalledProcessError as error:assert error.returncode==1;remaining=''
assert not remaining
ps=ui.device('shell','ps','-A','-o','PID,NAME').decode();assert not re.search(r'^\s*'+pid+r'\s',ps,re.M)
f.cold_open();newpid=ui.device('shell','pidof',ui.PACKAGE).decode().strip();assert newpid.isdigit() and newpid!=pid
ui.snap('14-tall-cold-library');ui.choose('最近');ui.choose('图包');f.until(lambda n:any(state['name'] in x and '1/1' in x.replace(' ','') for x in f.labels(n)),'cold recent original tall');ui.snap('15-tall-cold-recent');f.prefix(state['name']+'\n');f.until(lambda n:'阅读设置' in f.labels(n),'cold same tall reader');ui.snap('16-tall-cold-row13-offset')
pack=next(p for p in api.all_pages('/api/v1/packs') if p['id']==state['pack_id']);assert pack['progress']['page_id']==state['page_id'] and abs(pack['progress']['offset_ratio']-.45)<.001,pack['progress']
ui.device('shell','input','keyevent','4');f.until(lambda n:'最近看过' in f.labels(n),'reader back to recent');ui.snap('17-tall-return-after-cold-read')
final=next(p for p in api.all_pages('/api/v1/packs') if p['id']==state['pack_id']);assert final['progress']['page_id']==state['page_id'] and abs(final['progress']['offset_ratio']-.45)<.001,final['progress']
assert media.files()==before
trace=[json.loads(x) for x in (L/'requests.jsonl').read_text().splitlines()];reads=[r for r in trace if r['path']=='/api/v1/pages/'+state['page_id']+'/image'];assert len(reads)>=2 and all(r['status']==200 for r in reads)
posts=[r for r in trace if r['method']=='POST' and r['path']=='/api/v1/pack-trash/permanent'];restores=[r for r in trace if r['method']=='POST' and r['path']=='/api/v1/pack-restore-plans'];assert len(posts)==len(restores)==1
snapshot('normal26','tall-after-cold-read-and-back');state.update(phase='native_read_and_cold_resume_completed',old_app_pid=pid,new_app_pid=newpid,old_pid_absent_from_ps=True,cold_resume_progress=pack['progress'],progress_after_back=final['progress'],all_fixture_bytes_preserved_during_reading=True,native_permanent_posts=1,native_restore_posts=1,tall_image_read_200_count=len(reads))
(L/'tall-native-state.json').write_text(json.dumps(state,indent=2));print({'normal_code':26,'old_pid':pid,'new_pid':newpid,'same_page_id':state['page_id'],'cold_offset_ratio':pack['progress']['offset_ratio'],'after_back_offset_ratio':final['progress']['offset_ratio'],'original_permanent_posts':1,'original_restore_posts':1},flush=True)
