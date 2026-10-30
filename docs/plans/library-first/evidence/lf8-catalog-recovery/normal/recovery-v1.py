import json,re,time,urllib.request
from pathlib import Path
import business_ui as u,driver
from ui_driver import device,tap,record
from snapshot_all import snapshot
O=Path(__file__).resolve().parent;L=O.parent
SEED=json.loads((L/'seed.json').read_text());N=[];RESULT=[]
def observe(name):
 global N
 N=u.snap(name);return N
def text():return driver.text(N)
def wait(name,predicate,seconds=30):
 end=time.monotonic()+seconds
 while True:
  observe(name)
  if predicate():return N
  assert time.monotonic()<end,name;time.sleep(.15)
def act(label=None,prefix=None,name='action'):
 nodes=u.matches(N,label=label,prefix=prefix);assert len(nodes)==1,(label,prefix,[x.get('content-desc') for x in nodes]);tap(nodes[0],label or prefix);return observe(name)
def set_search(value,name,count=None,kind=None):
 fields=[x for x in N if x.get('class')=='android.widget.EditText'];assert len(fields)==1;node=fields[0];tap(node,'set fixture search');device('shell','input','keyevent','123');device('shell','input','keyevent',*(['67']*(len(node.get('text',''))+2)));device('shell','input','text',value);record({'action':'search','value':value,'context':name});device('shell','input','keyevent','4');observe(name)
 assert search()==value
 if count is not None:wait(name+'-ready',lambda:f'{count} 个{kind}' in text())
def search():
 fields=[x for x in N if x.get('class')=='android.widget.EditText'];assert len(fields)==1;return fields[0].get('text')
def rules(rows):
 p=L/'rules.next';p.write_text(json.dumps({'rules':rows}));p.replace(L/'proxy-rules.json')
def events():return [json.loads(x) for x in (L/'proxy-events.jsonl').read_text().splitlines()]
def event_wait(identity,kind):
 end=time.monotonic()+25
 while True:
  values=[x for x in events() if x.get('rule')==identity and x['event']==kind]
  if values:return values[-1]
  assert time.monotonic()<end,(identity,kind);time.sleep(.05)
def bounds(n):return list(map(int,re.findall(r'\d+',n.get('bounds'))))
def cards():
 result=[]
 for n in N:
  names=[s for s in n.get('content-desc','').splitlines() if re.fullmatch(r'Scope \d\d',s)]
  if n.get('clickable')=='true' and names:result.append({'name':names[0],'bounds':bounds(n)})
 return result
def viewport():
 values=[bounds(n) for n in N if n.get('scrollable')=='true'];assert len(values)==1,values;return values[0]
def anchor():
 v=viewport();c=[x for x in cards() if x['bounds'][1]>v[1]+5 and x['bounds'][3]<v[3]-5 and x['bounds'][3]-x['bounds'][1]>250];assert c,(cards(),v);a=sorted(c,key=lambda x:(x['bounds'][1],x['bounds'][0]))[0];return {'card':a,'viewport':v,'inset':a['bounds'][1]-v[1]}
def prove_empty(kind,value):
 assert search()==value and f'0 个{kind}' in text();assert not cards()
 label='预览此范围' if kind=='视频' else '快速整理';a=[x for x in N if x.get('content-desc')==label];assert len(a)==1 and a[0].get('enabled')=='false'
def run(kind,i):
 key='video' if kind=='视频' else 'pack';path='/api/v1/videos' if key=='video' else '/api/v1/packs';prefix=f'r{i}-{key}'
 act(prefix=kind+'\n',name=prefix+'-kind')
 more=prefix+'-more-fail';rules([{'id':more,'path':path,'query':{'search':'Scope','offset':'24'},'action':'fail'}]);set_search('Scope',prefix+'-initial',27,kind)
 for swipe in range(16):
  if '当前列表已保留' in text() and u.matches(N,label='重试'):break
  device('shell','input','swipe','1000','2290','1000','750','350');record({'action':'swipe','context':prefix+'-more','number':swipe});observe(prefix+'-scroll-'+str(swipe))
 else:raise AssertionError('pagination failure not reached')
 assert search()=='Scope' and cards();failure=event_wait(more,'injected_failure');a=anchor();(L/(prefix+'-failure-anchor.json')).write_text(json.dumps(a,indent=2)+'\n');rules([]);act('重试',name=prefix+'-retry');wait(prefix+'-retried',lambda:'当前列表已保留' not in text())
 v=viewport();same=[x for x in cards() if x['name']==a['card']['name']];assert len(same)==1;(L/(prefix+'-retry-anchor.json')).write_text(json.dumps({'before':a,'after':{'card':same[0],'viewport':v,'inset':same[0]['bounds'][1]-v[1]}},indent=2)+'\n');assert abs(same[0]['bounds'][1]-v[1]-a['inset'])<=3
 reads=[x for x in events() if x['event']=='catalog_response' and x['path']==path and x['time']>failure['time'] and 'offset=24' in x['query']];assert reads and reads[0]['body_summary']['total']==27 and len(reads[0]['body_summary']['ids'])==3
 for swipe in range(6):
  if any(c['name']=='Scope 27' for c in cards()):break
  device('shell','input','swipe','1000','2250','1000','750','350');observe(prefix+'-after-retry-tail-'+str(swipe))
 assert any(c['name']=='Scope 27' for c in cards())
 # A new search fails before any items arrive, and retries the same empty query.
 empty=f'NoSuch{i}{key}';eid=prefix+'-initial-fail';rules([{'id':eid,'path':path,'query':{'search':empty,'offset':'0'},'action':'fail'}]);set_search(empty,prefix+'-empty-failure');wait(prefix+'-empty-error',lambda:'测试读取暂不可用' in text() and bool(u.matches(N,label='重试')));event_wait(eid,'injected_failure');assert search()==empty and not cards();rules([]);act('重试',name=prefix+'-empty-retry');wait(prefix+'-empty-restored',lambda:f'0 个{kind}' in text());prove_empty(kind,empty)
 # The response is read from the real backend before being held.
 hid=prefix+'-late';rules([{'id':hid,'path':path,'query':{'search':'Scope','offset':'0'},'action':'hold','once':True}]);set_search('Scope',prefix+'-held-request');held=event_wait(hid,'held');assert held['body_summary']['total']==27 and len(held['body_summary']['ids'])==24
 new=f'NoLate{i}{key}';set_search(new,prefix+'-new-search',0,kind);prove_empty(kind,new);(L/('release-'+hid)).touch();released=event_wait(hid,'released');end=time.monotonic()+10
 while not any(e.get('rule')==hid and e['event'] in ['sent','client_closed'] for e in events()):assert time.monotonic()<end;time.sleep(.05)
 rules([]);observe(prefix+'-after-late-release');prove_empty(kind,new);observe(prefix+'-late-still-empty');prove_empty(kind,new)
 outcomes=[e for e in events() if e.get('rule')==hid and e['event'] in ['sent','client_closed']];RESULT.append({'kind':key,'round':i,'failure':failure,'retry_page':reads[0],'anchor_preserved':True,'initial_empty_retry_same_query':empty,'held':held,'released':released,'outcomes':outcomes,'new_query_after_release':new});(L/'recovery-result.json').write_text(json.dumps({'complete':len(RESULT)==6,'normal_code':22,'runs':RESULT},indent=2)+'\n')
if __name__=='__main__':
 observe('recovery-start');assert '媒体库' in text()
 if u.matches(N,label='清除'):act('清除',name='clear-entering-conditions')
 before=snapshot('new','read-recovery-before');prefs=driver.appearance('read-recovery-before')
 for i in range(1,4):
  for kind in ['视频','图包']:run(kind,i)
 after=snapshot('new','read-recovery-after')
 for key in ['tables','opaque_table_digests','setting_key_sha256']:assert before[key]==after[key],key
 assert driver.appearance('read-recovery-after')==prefs
 (L/'recovery-integrity.json').write_text(json.dumps({'all35_tables_settings_tokens_preferences_unchanged':True,'no_content_opened_or_written':True},indent=2)+'\n');print('SIX NATIVE RECOVERY FLOWS COMPLETE',flush=True)
