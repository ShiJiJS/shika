import json,re,subprocess,time
from pathlib import Path
import business_ui as u,driver
from ui_driver import device,fill,tap
from snapshot_all import snapshot
O=Path(__file__).resolve().parent;L=O.parent;seed=json.loads((L/'seed.json').read_text());proof=[]
def round_read(name,source,count,tags,search):
 m=json.loads((O/'runtime.json').read_text());code="import sqlite3,json;c=sqlite3.connect('file:/data/library.sqlite3?mode=ro',uri=True);c.row_factory=sqlite3.Row;c.execute('BEGIN');r=dict(c.execute('SELECT * FROM playback_rounds ORDER BY created_at DESC LIMIT 1').fetchone());e=[dict(x) for x in c.execute('SELECT * FROM round_entries WHERE round_id=? ORDER BY ordinal',(r['id'],))];c.rollback();c.close();print(json.dumps({'round':r,'entries':e}))";raw=subprocess.check_output(['docker','exec',m['container'],'python','-c',code],timeout=20);v=json.loads(raw);r=v['round'];q=json.loads(r['scope']);assert r['membership']=='fixed' and r['source']==source and r['candidate_count']==count;assert set(q.get('tag_ids',[]))==set(tags) and q.get('search','')==search;assert len(v['entries'])==count
 if source=='tags':assert {x['video_id'] for x in v['entries']}=={v['id'] for v in seed['videos'] if '风里' in v['name']}
 else:assert {x['video_id'] for x in v['entries']}=={v['id'] for v in seed['videos']}
 (L/(name+'-round.json')).write_bytes(raw);proof.append({'name':name,'id':r['id'],'source':source,'count':count,'scope':q})
def leave(name):
 n=u.snap(name+'-before');values=u.matches(n,label='返回来源');top=[x for x in values if int(re.findall(r'\d+',x.get('bounds'))[1])<500];target=top if top else values;assert len(target)==1;tap(target[0],'return from actual video source');return u.snap(name+'-after')
def search_field(nodes,value):
 fields=[x for x in nodes if x.get('class')=='android.widget.EditText'];assert len(fields)==1 and fields[0].get('text')==value;return fields[0]

before=snapshot('new','video-source-before')
u.choose('媒体库',context='video-library-nav');n=u.choose(prefix='视频\n',context='video-library-kind');search_field(n,'')
fill(0,'.mp4','video-source-search');device('shell','input','keyevent','4');n=u.snap('video-source-filtered');assert '2 个视频' in driver.text(n)
u.choose('预览此范围',context='video-library-preview');u.snap('video-library-playing');round_read('video-library-source','library',2,[],'.mp4')
n=leave('video-library-return');assert search_field(n,'.mp4').get('focused')=='false'
n=u.choose(prefix='图包\n',context='pack-query-after-video');search_field(n,'Scope');assert any('Scope 26' in x.get('content-desc','').splitlines() for x in n)
u.choose('标签',context='video-tag-nav');n=u.choose('视频',context='video-tag-kind');assert '匹配 1 个视频' in driver.text(n) and '同时包含 2 个标签' in driver.text(n)
u.choose('预览这 1 个视频',context='video-tag-preview');u.snap('video-tag-playing');round_read('video-tag-source','tags',1,[seed['tags']['video'][k] for k in ['Scope','Intersection']],'')
n=leave('video-tag-return');assert '匹配 1 个视频' in driver.text(n)
after=snapshot('new','video-source-after')
for key in ['pack_progress','pack_preferences','pack_sessions','pack_session_entries','pack_tag_definitions','pack_tag_links','packs','pack_pages','tags','video_tags']:
 assert before['tables'][key]==after['tables'][key],key
assert before['opaque_table_digests']['access_tokens']==after['opaque_table_digests']['access_tokens']
(L/'video-entry-focus-result.json').write_text(json.dumps({'complete':True,'code':21,'ranges':proof,'video_search_focus_not_restored':True,'pack_search_preserved':True,'all_pack_tables_and_two_tag_namespaces_unchanged':True},indent=2)+'\n')
