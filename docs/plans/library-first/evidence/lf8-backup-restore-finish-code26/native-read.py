import json
import ui,helpers as f,api,media,snapshot_all
L=ui.L;state=json.loads((L/'preparation-state.json').read_text())
ui.choose('返回设置');ui.choose('最近');ui.choose('图包')
f.until(lambda n:any(s.startswith('Gate-pack\n') for s in f.labels(n)),'restored recent')
ui.snap('10-restored-recent-S1');f.prefix('Gate-pack\n')
f.until(lambda n:'阅读设置' in f.labels(n),'restored page')
ui.snap('11-restored-page03-row13-offset45')
pack=api.call('GET','/api/v1/packs/'+state['pack_id'])
assert pack['progress']['page_id']==state['page_id'] and pack['progress']['offset_ratio']==.45
assert set(pack['tag_ids'])=={state['S0_tag']['id'],state['S1_added_tag']['id']}
ui.device('shell','input','keyevent','4')
f.until(lambda n:'最近看过' in f.labels(n),'back to recent')
ui.snap('12-return-recent-after-management-restore')
after=snapshot_all.snapshot('normal26','after-native-read-and-back')
assert media.save('after-native-read-and-back')==state['files']
trace=[json.loads(x) for x in (L/'requests.jsonl').read_text().splitlines()]
reads=[r for r in trace if r['path']=='/api/v1/pages/'+state['page_id']+'/image']
assert reads and all(r['status']==200 for r in reads)
(L/'native-read.json').write_text(json.dumps({'pack_id':state['pack_id'],'page_id':state['page_id'],'progress':pack['progress'],'tags':pack['tag_ids'],'original_page_200_count':len(reads),'all_three_files_unchanged':True,'no_cold_restart_claim':True},indent=2))
print({'actual_original_image_read':True,'page':3,'offset':.45,'tags':2,'files':3})
