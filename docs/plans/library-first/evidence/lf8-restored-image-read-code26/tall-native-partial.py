import json,subprocess,time
import api,fixture_control as ctrl,helpers as f,media,ui
from snapshot_all import snapshot
L=ui.L;seed=json.loads((L/'tall-preparation.json').read_text());name=seed['name']
assert not (L/'tall-native-state.json').exists()
f.trash_page();ui.fill(0,name);ui.device('shell','input','keyevent','4');f.until(lambda n:'共 1 个图包' in f.labels(n),'one tall trash target');ui.choose('选择回收内容 '+name)
before=media.save('tall-native-before-permanent');snapshot('normal26','tall-native-before-permanent')
ui.choose('永久删除');f.until(lambda n:any('我确认永久删除' in x for x in f.labels(n)),'tall image manifest')
_,ns=ui.xml();assert any(n.get('content-desc')=='确认永久删除' and n.get('enabled')=='false' for n in ns);ui.snap('07-tall-review-three-images')
ctrl.write(L/'control/executor.json',{'target':name,'partial':True,'hold_after_first':False})
seq=max(json.loads(x)['seq'] for x in (L/'requests.jsonl').read_text().splitlines())
ui.choose('我确认永久删除本批清单中的图片，无法恢复。');ui.choose('确认永久删除');f.until(lambda n:'已确认删除 2/3 张' in f.labels(n),'actual tall partial result');ui.snap('08-tall-partial-two-of-three')
trace=[json.loads(x) for x in (L/'requests.jsonl').read_text().splitlines()];posts=[x for x in trace if x['seq']>seq and x['path']=='/api/v1/pack-trash/permanent' and x['method']=='POST'];assert len(posts)==1
task=api.call('GET','/api/v1/pack-file-requests/'+posts[0]['command']['request_id']);assert task['status']=='failed' and task['result']['pages_deleted']==2 and task['result']['pages_total']==3
after=media.save('tall-native-partial');media.compare_deleted(before,after,[name+'/01.png',name+'/02.png']);ctrl.write(L/'control/executor.json',{})
runtime=json.loads((L/'runtime.json').read_text());code="import os,json,hashlib,stat;from pathlib import Path;from video_viewer.paths import signature;p=Path('/media/Restore-read-tall/03.png');old=p.stat();h=hashlib.sha256(p.read_bytes()).hexdigest();os.chmod(p,stat.S_IMODE(old.st_mode));new=p.stat();print(json.dumps({'before':signature(old),'after':signature(new),'sha256':h,'after_sha256':hashlib.sha256(p.read_bytes()).hexdigest()}))"
ctime=json.loads(subprocess.check_output(['docker','exec',runtime['id'],'python','-c',code]));assert ctime['before'][:4]==ctime['after'][:4] and ctime['before'][4]!=ctime['after'][4] and ctime['sha256']==ctime['after_sha256']
snapshot('normal26','tall-native-partial-after-ctime')
state={'name':name,'phase':'partial_result_open','pack_id':seed['pack']['id'],'page_id':seed['pages'][-1]['id'],'original_operation':task['id'],'request_id':posts[0]['command']['request_id'],'actual_native_permanent_posts':1,'partial_task':task,'explicit_fixture_ctime_only_update':ctime,'remaining_image_file_bytes_unchanged':True,'new_source':runtime['source']}
(L/'tall-native-state.json').write_text(json.dumps(state,indent=2));print({'native_partial':'2/3','same_remaining_page_id':state['page_id'],'controlled_ctime_only_update':True},flush=True)
