"""Continue the accepted original partial operation; never submit another purge."""
import json,subprocess
import api,media,ui
from snapshot_all import snapshot
L=ui.L;seed=json.loads((L/'tall-preparation.json').read_text());name=seed['name'];assert not (L/'tall-native-state.json').exists()
trace=[json.loads(x) for x in (L/'requests.jsonl').read_text().splitlines()];posts=[x for x in trace if x['path']=='/api/v1/pack-trash/permanent' and x['method']=='POST'];assert len(posts)==1
task=api.call('GET','/api/v1/pack-file-requests/'+posts[0]['command']['request_id']);assert task['status']=='failed' and task['result']['pages_deleted']==2 and task['result']['pages_total']==3
runtime=json.loads((L/'runtime.json').read_text())
code="""import os,json,hashlib,stat,time
from pathlib import Path
from video_viewer.paths import signature
p=Path('/media/Restore-read-tall/03.png');old=p.stat();h=hashlib.sha256(p.read_bytes()).hexdigest();mode=stat.S_IMODE(old.st_mode)
os.chmod(p,mode^stat.S_IWUSR);os.chmod(p,mode)
deadline=time.monotonic()+5
while p.stat().st_ctime_ns==old.st_ctime_ns and time.monotonic()<deadline:time.sleep(.05)
new=p.stat();print(json.dumps({'before':signature(old),'after':signature(new),'sha256':h,'after_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'original_mode_restored':stat.S_IMODE(new.st_mode)==mode}))
"""
ctime=json.loads(subprocess.check_output(['docker','exec',runtime['id'],'python','-c',code]));assert ctime['before'][:4]==ctime['after'][:4] and ctime['before'][4]!=ctime['after'][4] and ctime['sha256']==ctime['after_sha256'] and ctime['original_mode_restored'],ctime
before=json.loads((L/'tall-native-before-permanent-files.json').read_text());after=media.files();media.compare_deleted(before,after,[name+'/01.png',name+'/02.png']);snapshot('normal26','tall-native-partial-after-ctime')
state={'name':name,'phase':'partial_result_open','pack_id':seed['pack']['id'],'page_id':seed['pages'][-1]['id'],'original_operation':task['id'],'request_id':posts[0]['command']['request_id'],'actual_native_permanent_posts':1,'partial_task':task,'explicit_fixture_ctime_only_update':ctime,'remaining_image_file_bytes_unchanged':True,'new_source':runtime['source'],'same_mode_chmod_did_not_advance_ctime_first_attempt':True,'no_permanent_operation_replayed':True}
(L/'tall-native-state.json').write_text(json.dumps(state,indent=2));print({'original_partial':'2/3','confirmed_ctime_only_update':ctime,'no_new_purge_post':True},flush=True)
