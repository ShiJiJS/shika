import json,re,subprocess,time
from pathlib import Path
from urllib.parse import parse_qs
import business_ui as u,driver
from ui_driver import device,fill,tap
from snapshot_all import snapshot
O=Path(__file__).resolve().parent;L=O.parent;seed=json.loads((L/'seed.json').read_text());checks=[]
def count(kind,value,context):
 end=time.monotonic()+30
 while True:
  n=u.snap(context)
  if f'{value} 个{kind}' in driver.text(n):return n
  assert time.monotonic()<end,(context,value);time.sleep(.3)
def dropdown(prefix,value,context):u.choose(prefix=prefix,context=context+'-dropdown');return u.choose(value,context=context+'-option')
def rounds(name,expected,scope):
 meta=json.loads((O/'runtime.json').read_text());code="import sqlite3,json;c=sqlite3.connect('file:/data/library.sqlite3?mode=ro',uri=True);c.row_factory=sqlite3.Row;c.execute('BEGIN');r=dict(c.execute('SELECT * FROM playback_rounds ORDER BY created_at DESC LIMIT 1').fetchone());e=[dict(x) for x in c.execute('SELECT * FROM round_entries WHERE round_id=? ORDER BY ordinal',(r['id'],))];c.rollback();c.close();print(json.dumps({'round':r,'entries':e}))";v=json.loads(subprocess.check_output(['docker','exec',meta['container'],'python','-c',code],timeout=20));r=v['round'];q=json.loads(r['scope']);assert r['source']=='library' and r['membership']=='fixed' and r['candidate_count']==len(expected);assert {x['video_id'] for x in v['entries']}==set(expected) and [x['ordinal'] for x in v['entries']]==list(range(len(expected)))
 for k,value in scope.items():assert q.get(k)==value,(k,q,value)
 (L/(name+'-round.json')).write_text(json.dumps(v,indent=2)+'\n');checks.append({'name':name,'count':len(expected),'scope':q});return v

def preview(name,expected,scope):
 u.choose('预览此范围',context=name+'-open');n=u.snap(name+'-playing');assert '视频预览' in driver.text(n);rounds(name,expected,scope)
 values=u.matches(n,label='返回来源');top=[x for x in values if int(re.findall(r'\d+',x.get('bounds'))[1])<500];assert len(top)==1;tap(top[0],'return to matching library');return u.snap(name+'-returned')
def selectall(kind,value,name):
 offset=driver.trace_count();u.choose('更多',context=name+'-more');u.choose('多选内容',context=name+'-select');n=u.choose('全选匹配项',context=name+'-all');assert f'已选 {value}' in driver.text(n)
 lines=[json.loads(x) for x in (O/'trace/requests.jsonl').read_text().splitlines()[offset:]];requests=[x for x in lines if x['path']==('/api/v1/videos/selection' if kind=='video' else '/api/v1/packs/selection')];assert requests and all(x['method']=='GET' and x['status']==200 for x in requests);(L/(name+'-selection-requests.json')).write_text(json.dumps(requests,indent=2)+'\n')
 u.choose('更多',context=name+'-exit-more');n=u.choose('多选内容',context=name+'-exit');assert not u.matches(n,label='全选匹配项');return n

if __name__=='__main__':
 u.choose('关闭面板',context='initial-filter-dismiss');fill(0,'Scope','initial-video-search');device('shell','input','keyevent','4');count('视频',27,'initial-27-videos');before=snapshot('new','before-video-flow')
 expected=[v['id'] for v in seed['videos'] if v['name'].startswith('Scope ')];preview('video-27-first24',expected,{'search':'Scope','tag_ids':[]});selectall('video',27,'video-27-first24')
 u.choose('筛选视频',context='combined-filter');u.choose('更换目录',context='combined-directory');n=u.snap('directory-inventory')
 (L/'video-first-result.json').write_text(json.dumps({'complete':True,'checks':checks},indent=2)+'\n')
