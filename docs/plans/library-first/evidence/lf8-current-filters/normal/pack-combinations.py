import json,re,time
from pathlib import Path
import business_ui as u,driver,flows as f
from ui_driver import fill,device,tap
from snapshot_all import snapshot
O=Path(__file__).resolve().parent;L=O.parent;result=[]
def card(nodes,name):
 candidates=[x for x in nodes if x.get('clickable')=='true' and name in (x.get('content-desc','')+'\n'+x.get('text','')).splitlines()];assert len(candidates)==1,(name,len(candidates));return candidates[0]
def fields(n,value):
 a=[x for x in n if x.get('class')=='android.widget.EditText'];assert len(a)==1 and a[0].get('text')==value
# Retain different selection sizes to detect accidental shared state.
u.choose('更多',context='video-single-more');n=u.choose('多选内容',context='video-single-on');tap(card(n,'Scope 01'),'select one video');n=u.snap('video-one-selected');assert '已选 1' in driver.text(n)
n=u.choose(prefix='图包\n',context='pack-kind-isolated');fields(n,'');fill(0,'Scope','pack-scope-search');device('shell','input','keyevent','4');f.count('图包',27,'pack-27-start')
u.choose('更多',context='pack-select-more');u.choose('多选内容',context='pack-select-on');n=u.choose('全选匹配项',context='pack-select-all27');assert '已选 27' in driver.text(n)
n=u.choose(prefix='视频\n',context='video-selection-independent');fields(n,'Scope');assert '已选 1' in driver.text(n)
u.choose('更多',context='video-selection-exit-more');u.choose('多选内容',context='video-selection-exit')
n=u.choose(prefix='图包\n',context='pack-selection-independent');fields(n,'Scope');assert '已选 27' in driver.text(n)
u.choose('追加标签',context='pack-append-cancel');u.snap('pack-append-cancel-inventory')
(L/'pack-selection-result.json').write_text(json.dumps({'selection_sizes_video':1,'selection_sizes_pack':27,'independent':True,'append_not_submitted_yet':True},indent=2)+'\n')
u.choose('取消',context='pack-append-cancel-actual');u.choose('更多',context='pack-selection-exit-more');u.choose('多选内容',context='pack-selection-exit')
n=f.count('图包',27,'pack-before-reading');tap(card(n,'Scope 01'),'open Scope01 to establish actual reading state');n=u.snap('pack-seed-reading');assert 'Scope 01' in driver.text(n) and '1 / 6' in driver.text(n)
buttons=[x for x in u.matches(n,label='返回来源') if int(re.findall(r'\d+',x.get('bounds'))[1])<500];assert len(buttons)==1;tap(buttons[0],'return from actual pack opening');n=u.snap('pack-reading-return');fields(n,'Scope')
seeded=snapshot('new','pack-reading-established');assert len(seeded['tables']['pack_progress'])==1
for i in range(1,4):
 name=f'pack-combo-{i}'
 u.choose('阅读状态',context=name+'-unread');f.count('图包',26,name+'-unread26');u.choose('未读',context=name+'-reading');f.count('图包',1,name+'-reading1');u.choose('在读',context=name+'-completed');n=f.count('图包',0,name+'-completed0')
 quick=[x for x in n if x.get('content-desc')=='快速整理'];assert len(quick)==1 and quick[0].get('enabled')=='false';u.choose('已读',context=name+'-all');f.count('图包',27,name+'-all27')
 u.choose('筛选图包',context=name+'-filter');u.choose(prefix='目录\n',context=name+'-directory');u.choose('图包',context=name+'-root');u.choose('Scope 01',context=name+'-folder');u.choose('使用此目录',context=name+'-use');u.choose('应用筛选',context=name+'-apply');n=f.count('图包',1,name+'-directory1');assert 'Scope 01' in driver.text(n)
 fill(0,'NoSuchPack','pack-negative-search-'+str(i));device('shell','input','keyevent','4');n=f.count('图包',0,name+'-search-empty');quick=[x for x in n if x.get('content-desc')=='快速整理'];assert len(quick)==1 and quick[0].get('enabled')=='false'
 fill(0,'Scope','pack-search-restore-'+str(i));device('shell','input','keyevent','4');f.count('图包',1,name+'-search-return1');u.choose('筛选图包',context=name+'-reset');u.choose('重置',context=name+'-reset-draft');u.choose('应用筛选',context=name+'-reset-apply');f.count('图包',27,name+'-reset27')
 result.append({'round':i,'unread':26,'reading':1,'completed':0,'directory':1,'negative_search':0,'reset':27})
 (L/'pack-combinations-result.json').write_text(json.dumps({'complete':i==3,'normal_code':21,'rounds':result,'selection_independent_sizes':[1,27],'append_cancelled':True},indent=2)+'\n')
after=snapshot('new','all-flows-after');before=json.loads((O/'before-video-flow-all-catalog.json').read_text())
for key in ['pack_tag_definitions','pack_tag_links','tags','video_tags','packs','pack_pages','roots','videos']:assert before['tables'][key]==after['tables'][key],key
assert before['opaque_table_digests']['access_tokens']==after['opaque_table_digests']['access_tokens']
assert seeded['tables']['pack_progress']==after['tables']['pack_progress']
(L/'tag-integrity-result.json').write_text(json.dumps({'all_tags_catalogs_roots_and_token_unchanged':True,'only_one_pack_reading_established':True,'reading_progress_stable_during_filters':True},indent=2)+'\n')
print('THREE PACK COMBINATIONS COMPLETE',flush=True)
