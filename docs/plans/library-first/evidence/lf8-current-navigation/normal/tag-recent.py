import json,re,subprocess,time
from pathlib import Path
import business_ui as u,driver,observe
from ui_driver import device,tap
O=Path(__file__).resolve().parent;L=O.parent
seed=json.loads((L/'seed.json').read_text());proof=[]
def card(nodes):
 found=[n for n in nodes if n.get('clickable')=='true' and 'Scope 26' in (n.get('content-desc','')+'\n'+n.get('text','')).splitlines()];assert len(found)==1;return found[0]
def current(name,source,expected_ids,tags):
 meta=json.loads((O/'runtime.json').read_text());code="import sqlite3,json;c=sqlite3.connect('file:/data/library.sqlite3?mode=ro',uri=True);c.row_factory=sqlite3.Row;c.execute('BEGIN');r=dict(c.execute('SELECT id,created_at FROM pack_sessions ORDER BY created_at DESC LIMIT 1').fetchone());c.rollback();c.close();print(json.dumps(r))";raw=subprocess.check_output(['docker','exec',meta['container'],'python','-c',code],timeout=20);row=json.loads(raw);s=observe.req('/pack-sessions/'+row['id']);entries=observe.req('/pack-sessions/'+row['id']+'/entries?limit=200');assert s['source']=={'kind':source,'sort':'title'} or source=='recent' and s['source']['kind']=='recent';assert s['scope']['search']=='' and set(s['scope']['tag_ids'])==set(tags);assert s['candidate_count']==len(expected_ids) and {i['pack']['id'] for i in entries['items']}==set(expected_ids);assert s['current']['id']==observe.target['id'] and s['resume']['page_index']==2
 value={'observed_sql_session':row,'session':s,'entries':entries};(L/(name+'-range.json')).write_text(json.dumps(value,indent=2,ensure_ascii=False)+'\n');proof.append({'name':name,'session_id':s['id'],'source':source,'candidate_count':s['candidate_count'],'tag_ids':s['scope']['tag_ids'],'search':s['scope']['search']})

n=u.choose(prefix='Scope\n',context='video-tag-scope');assert '匹配 2 个视频' in driver.text(n)
n=u.choose(prefix='Intersection\n',context='video-tag-intersection');assert '匹配 1 个视频' in driver.text(n)
n=u.choose('图包',context='switch-pack-tags');assert '全部图包' in driver.text(n) and '匹配 31 个图包' in driver.text(n)
n=u.choose(prefix='Scope\n',context='pack-tag-scope');assert '匹配 31 个图包' in driver.text(n)
n=u.choose(prefix='Intersection\n',context='pack-tag-intersection');assert '匹配 27 个图包' in driver.text(n)
u.choose('查看 27 个图包',context='pack-tag-results')
for i in range(24):
 n=u.snap('tag-find26-'+str(i));found=[x for x in n if x.get('clickable')=='true' and 'Scope 26' in x.get('content-desc','').splitlines()]
 if len(found)==1:
  bounds=list(map(int,re.findall(r'\d+',found[0].get('bounds'))))
  if bounds[3]-bounds[1]>=300:break
 device('shell','input','swipe','1000','2310','1000','750','450')
else:raise AssertionError('Tag range Scope26 not reached')
before=bounds;tap(found[0],'open Scope26 from actual tag results');n=u.snap('tag-reader-open');assert '3 / 6' in driver.text(n) and '26 / 27' in driver.text(n)
current('tag-source','tags',observe.expected,[seed['tags']['pack'][k] for k in ['Scope','Intersection']])
u.choose('返回来源',context='tag-reader-return');n=u.snap('tag-returned-results');node=card(n);after=list(map(int,re.findall(r'\d+',node.get('bounds'))));assert abs(before[1]-after[1])<=3;(L/'tag-return-anchor.json').write_text(json.dumps({'before':before,'after':after},indent=2)+'\n')
u.choose('返回标签选择',context='tag-results-back');n=u.choose('视频',context='tag-video-selection-return');assert '同时包含 2 个标签' in driver.text(n) and '匹配 1 个视频' in driver.text(n)
n=u.choose('图包',context='tag-pack-selection-return');assert '同时包含 2 个标签' in driver.text(n) and '匹配 27 个图包' in driver.text(n)
u.choose('最近',context='recent-source');n=u.snap('recent-initial-kind')
# Recent has a separate kind selector from tags and library.
options=u.matches(n,prefix='图包\n') or u.matches(n,label='图包');assert len(options)==1;tap(options[0],'recent pack kind');n=u.snap('recent-pack-list')
node=card(n);tap(node,'open actual recent Scope26');n=u.snap('recent-reader-open');assert '3 / 6' in driver.text(n) and '1 / 1' in driver.text(n)
current('recent-source','recent',{observe.target['id']},[])
# Both the header and the end-of-range footer may say Return source.
values=u.matches(n,label='返回来源');header=[x for x in values if int(re.findall(r'\d+',x.get('bounds'))[1])<500];assert len(header)==1;tap(header[0],'recent reader header return');n=u.snap('recent-reader-returned');card(n)
(L/'tag-recent-result.json').write_text(json.dumps({'complete':True,'normal_code':21,'video_tag_matching':1,'pack_tag_matching':27,'namespaces_independent':True,'selection_preserved_across_kinds':True,'ranges':proof,'tag_return_anchor_preserved':True},indent=2)+'\n')
