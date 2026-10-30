import json,re,time,subprocess
from pathlib import Path
import business_ui as u,driver,observe
from ui_driver import device,tap
O=Path(__file__).resolve().parent;L=O.parent
checks=[]
def inspect(name,index,mode=None,direction=None,gap=None):
 n=u.snap(name);assert f'{index+1} / 6' in driver.text(n) and 'Scope 26' in driver.text(n),name
 v=observe.read(name);assert v['pack']['progress']['page_index']==index
 s=v['session'];assert s['candidate_count']==27 and s['cursor']==25 and s['current']['id']==observe.target['id'];assert s['scope']['search']=='Scope' and not s['scope']['tag_ids'];assert s['source']=={'kind':'library','sort':'title'}
 assert {i['pack']['id'] for i in v['entries']['items']}==observe.expected and [i['ordinal'] for i in v['entries']['items']]==list(range(27))
 p=s['resume']['preferences']
 for key,expected in [('mode',mode),('direction',direction),('gap',gap)]:
  if expected is not None:assert p[key]==expected,(name,key,p)
 checks.append({'name':name,'page_index':index,'mode':p['mode'],'direction':p['direction'],'gap':p['gap'],'session_id':s['id']})
 return n

def direction(value):
 u.choose('阅读设置',context='direction-'+value)
 current='从左向右' if value=='rtl' else '从右向左';u.choose('翻页方向\n'+current,context='direction-menu-'+value)
 u.choose('从右向左' if value=='rtl' else '从左向右',context='direction-select-'+value)
 u.choose('继续阅读',context='direction-done-'+value)

def refresh_session(name):
 meta=json.loads((O/'runtime.json').read_text());code="import sqlite3,json;c=sqlite3.connect('file:/data/library.sqlite3?mode=ro',uri=True);c.row_factory=sqlite3.Row;c.execute('BEGIN');r=dict(c.execute('SELECT id,created_at FROM pack_sessions ORDER BY created_at DESC LIMIT 1').fetchone());c.rollback();c.close();print(json.dumps(r))";raw=subprocess.check_output(['docker','exec',meta['container'],'python','-c',code],timeout=20);(L/(name+'-session.json')).write_bytes(raw);observe.session_id=json.loads(raw)['id']

def card(nodes):
 values=[n for n in nodes if n.get('clickable')=='true' and 'Scope 26' in (n.get('content-desc','')+'\n'+n.get('text','')).splitlines()];assert len(values)==1
 return values[0]

refresh_session('flow3-initial')

for i in [1,2,3]:
 prefix=f'flow3-round-{i}'
 inspect(prefix+'-start',2,'horizontal','ltr')
 expected_gap=not observe.req('/pack-sessions/'+observe.session_id)['resume']['preferences']['gap']
 for label,start,end,index in [('ltr-next',900,250,3),('ltr-previous',250,900,2)]:
  device('shell','input','swipe',str(start),'1400',str(end),'1400','350');inspect(prefix+'-'+label,index,'horizontal','ltr')
 direction('rtl');inspect(prefix+'-rtl-same-page',2,'horizontal','rtl')
 for label,start,end,index in [('rtl-next',250,900,3),('rtl-previous',900,250,2)]:
  device('shell','input','swipe',str(start),'1400',str(end),'1400','350');inspect(prefix+'-'+label,index,'horizontal','rtl')
 u.choose('阅读设置',context=prefix+'-vertical-settings');u.choose('纵向拼接',context=prefix+'-vertical-mode');u.choose('图片之间留间距',context=prefix+'-vertical-gap');u.choose('继续阅读',context=prefix+'-vertical-done');inspect(prefix+'-vertical-same-page',2,'vertical','rtl',expected_gap)
 for j in range(5):device('shell','input','swipe','900','2000','900','700','400')
 inspect(prefix+'-vertical-end',5,'vertical','rtl',expected_gap)
 u.choose('阅读设置',context=prefix+'-horizontal-settings');u.choose('横向翻页',context=prefix+'-horizontal-mode');u.choose('继续阅读',context=prefix+'-horizontal-done');inspect(prefix+'-horizontal-same-last',5,'horizontal','rtl')
 u.choose('总览',context=prefix+'-overview');u.choose(prefix='第 3 页',context=prefix+'-overview-third');inspect(prefix+'-overview-chosen',2,'horizontal','rtl')
 direction('ltr');inspect(prefix+'-ltr-restored',2,'horizontal','ltr')
 u.choose('图包更多',context=prefix+'-more');u.choose('本次图包范围',context=prefix+'-queue');n=u.back(prefix+'-queue-dismiss');assert '3 / 6' in driver.text(n)
 u.choose('沉浸',context=prefix+'-immersive');n=u.back(prefix+'-immersive-exit');assert '3 / 6' in driver.text(n) and '返回来源' in driver.text(n)
 u.choose('返回来源',context=prefix+'-return-library');n=u.snap(prefix+'-returned-list');assert any(x.get('text')=='Scope' and x.get('class')=='android.widget.EditText' for x in n)
 fields=[x for x in n if x.get('class')=='android.widget.EditText'];assert len(fields)==1 and fields[0].get('focused')=='false',(prefix,'search focus was restored')
 selected=card(n);bounds=list(map(int,re.findall(r'\d+',selected.get('bounds'))));before=list(map(int,re.findall(r'\d+',json.loads((O/'entry26-code21.json').read_text())['bounds'])));assert abs(bounds[1]-before[1])<=3,(prefix,bounds,before)
 (L/(prefix+'-returned-anchor.json')).write_text(json.dumps({'before':before,'after':bounds,'search':'Scope','matched':27},indent=2)+'\n')
 if i<3:
  tap(selected,'reopen Scope26 from preserved list');n=u.snap(prefix+'-reopened');assert '3 / 6' in driver.text(n);refresh_session(prefix+'-reopened')
(L/'reader-flow3-result.json').write_text(json.dumps({'complete':True,'checks':checks,'rounds':3,'return_anchor_preserved':True,'same_signed_normal_code':21},indent=2)+'\n')
