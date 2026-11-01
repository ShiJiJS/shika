import json
import api,helpers as f,media,ui
from snapshot_all import snapshot
L=ui.L;state=json.loads((L/'tall-native-state.json').read_text());name=state['name'];seed=json.loads((L/'tall-preparation.json').read_text());before=json.loads((L/'tall-before-logical-restore-files.json').read_text());assert media.files()==before
trace=[json.loads(x) for x in (L/'requests.jsonl').read_text().splitlines()];posts=[x for x in trace if x['method']=='POST' and x['path']=='/api/v1/pack-restore-plans'];assert len(posts)==1
restored=api.call('GET','/api/v1/pack-restore-requests/'+posts[0]['command']['request_id']);assert restored['status']=='completed' and restored['result']['succeeded']==1
state.update(additional_owned_emulator_reboot=True,image_only_emulator_profile=True,restore_completed_before_emulator_exit=True)
f.cold_open();f.settings_row('操作任务')
for swipe in range(20):
 _,nodes=ui.xml();labels=f.labels(nodes);pending=[n for n in nodes if n.get('clickable')=='true' and (n.get('content-desc') or '').startswith('恢复 1 个图包\n本机结果待核对')];completed=[n for n in nodes if n.get('clickable')=='true' and (n.get('content-desc') or '').startswith('批量恢复图包\n已完成')]
 if pending or completed:
  chosen=(pending or completed)[0];state['restore_result_entry']='pending-original-request' if pending else 'original-server-task';ui.tap(chosen,'same completed native restore');break
 assert swipe<19;ui.device('shell','input','swipe','540','1740','540','700','250')
f.until(lambda n:restored['id'] in '\n'.join(f.labels(n)),'same native restore plan id');ui.snap('10-tall-original-restore-result')
ui.choose('返回操作任务')
for scroll in range(20):
    _,nodes=ui.xml();rows=[n for n in nodes if n.get('clickable')=='true' and (n.get('content-desc') or '').startswith('永久删除图包图片\n部分完成')]
    if rows:ui.tap(rows[0],'latest native partial purge');break
    assert scroll<19;ui.device('shell','input','swipe','540','1740','540','700','250')
f.until(lambda n:state['original_operation'] in '\n'.join(f.labels(n)),'same original tall purge id');ui.choose('查看逐项图片结果');f.until(lambda n:'已确认删除 2/3 张' in f.labels(n),'original two of three');ui.choose('重试原任务');f.until(lambda n:'重试未完成项' in f.labels(n),'explicit old purge retry');ui.choose('重试未完成项');f.until(lambda n:'已确认删除 2/3 张' in f.labels(n),'restored image protected');ui.snap('11-tall-old-purge-protected')
task=api.wait(state['original_operation'],route='/api/v1/pack-operations/');assert task['result']['items'][0]['error']=='stale_pack_state' and task['result']['pages_deleted']==2;assert media.files()==before
snapshot('normal26','tall-after-old-purge-retry');state.update(phase='restored_original_purge_stopped',restore_plan=restored,old_purge_retry=task,restore_queries_acknowledged_natively=True);(L/'tall-native-state.json').write_text(json.dumps(state,indent=2))
ui.choose('关闭');ui.choose('返回操作任务');ui.choose('返回设置');ui.choose('最近');ui.choose('图包');f.until(lambda n:any(name in x and '1/1' in x.replace(' ','') for x in f.labels(n)),'tall recent one of one');ui.snap('12-tall-recent-one-of-one');f.prefix(name+'\n');f.until(lambda n:'阅读设置' in f.labels(n),'restored tall reader open');ui.snap('13-tall-restored-row13-offset')
pack=next(p for p in api.all_pages('/api/v1/packs') if p['id']==state['pack_id']);assert pack['progress']['page_id']==state['page_id'] and abs(pack['progress']['offset_ratio']-.45)<.02,pack['progress']
state.update(phase='first_native_read_open',first_read_progress=pack['progress'],native_restore_posts=1,remaining_image_and_attachments_preserved=True);(L/'tall-native-state.json').write_text(json.dumps(state,indent=2));snapshot('normal26','tall-first-native-read');print({'restored_native_tall':'1/1','page_id':state['page_id'],'offset_ratio':pack['progress']['offset_ratio'],'old_purge':'stale_pack_state'},flush=True)
