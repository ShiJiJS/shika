import sys,json,time,threading,subprocess,os,signal,socket,hashlib,re
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import ui,api
from snapshot_all import snapshot
L=ui.L;MEDIA=Path(json.loads((L/'runtime.json').read_text())['media_source']);ACTIVE={'queued','discovering','waiting_for_stable_files','processing_media','reconciling'};stop=threading.Event();events={};journal=[]
def state():return api.call('GET','/api/v1/library-state')
def roots(s):return {v['id']:v for v in s['roots']}
def save(stage,**values):
 events.update(values);events['stage']=stage;events['observed_at']=time.time();(L/'queue-flow-state.json').write_text(json.dumps(events,indent=2)+'\n');print({'stage':stage,**{k:v for k,v in values.items() if isinstance(v,(str,int,float,bool))}},flush=True)
def watch():
 while not stop.is_set():
  try:row={'time':time.time(),'state':state()}
  except Exception as exc:row={'time':time.time(),'observation_error':type(exc).__name__}
  journal.append(row)
  with (L/'queue-backend-watch.jsonl').open('a') as f:f.write(json.dumps(row)+'\n')
  stop.wait(.5)
def wait(fn,seconds=300):
 deadline=time.monotonic()+seconds;lastlog=time.monotonic()
 while True:
  s=state()
  if fn(s):return s
  assert time.monotonic()<deadline,('state wait timed out',events.get('stage'))
  if time.monotonic()-lastlog>15:
   print({'waiting':events.get('stage'),'roots':[(r['id'],r['scan']['status'],r['scan'].get('progress',{}).get('processed')) for r in s['roots']]},flush=True);lastlog=time.monotonic()
  time.sleep(.3)
def click_root(index,expected,label):
 deadline=time.monotonic()+20
 while True:
  _,nodes=ui.xml();buttons=[n for n in nodes if (n.get('content-desc') or n.get('text')) in ['扫描此目录','正在扫描','已排队'] and n.get('class')=='android.widget.Button'];labels=[n.get('content-desc') or n.get('text') for n in buttons]
  if labels==expected and buttons[index].get('enabled')=='true':break
  assert time.monotonic()<deadline,('unexpected root controls',labels,expected)
 ui.tap(buttons[index],label)
def screen_text(name):
 n=ui.snap(name);return '\n'.join(v.get('content-desc') or v.get('text') or '' for v in n),n
events=json.loads((L/'queue-flow-state.json').read_text());assert events['stage']=='App-reconnected';a1=events['A1'];b1=events['B1'];baseline=json.loads((L/'new-baseline-state.json').read_text());before=json.loads((L/'before-native-queue-all-catalog.json').read_text());thread=threading.Thread(target=watch,daemon=True);thread.start()
# Resume waiting only; A/B requests and offline actions are not replayed.
try:
 s=wait(lambda s: roots(s)['packs-a']['scan']['task_id']==a1 and roots(s)['packs-a']['scan']['status']=='partial' and roots(s)['packs-b']['scan']['task_id']==b1 and roots(s)['packs-b']['scan']['status'] in ACTIVE);a_done=roots(s)['packs-a'];assert a_done['scan']['progress']['processed']==1515;save('A-finished-B-active',A1_completed=1515);text,_=screen_text('16-A-finished-B-active');assert '1515 / 1515 张图片' in text
 click_root(1,['扫描此目录','扫描此目录','正在扫描'],'queue-A-again-after-A-finished-while-B-active');s=wait(lambda s: bool(roots(s)['packs-a']['queued_task_ids']));r=roots(s);a2=r['packs-a']['queued_task_ids'][0];assert r['packs-a']['scan']==a_done['scan'];assert r['packs-b']['scan']['task_id']==b1 and r['packs-b']['scan']['status'] in ACTIVE;save('A-requeued-B-active',A2=a2,A1_fact_preserved_while_queued=True);text,_=screen_text('17-A-requeued-previous-result-kept');assert '1515 / 1515 张图片' in text and '下一次扫描已排队' in text
 s=wait(lambda s: not s['scanning'] and roots(s)['packs-a']['scan']['task_id']==a2 and roots(s)['packs-a']['scan']['status']=='partial' and roots(s)['packs-b']['scan']['task_id']==b1 and roots(s)['packs-b']['scan']['status']=='completed',240);final=roots(s);assert final['packs-a']['scan']['progress']['processed']==1515;assert final['packs-b']['scan']['progress']['processed']==604
 deadline=time.monotonic()+45
 while True:
  _,nodes=ui.xml();text='\n'.join(n.get('content-desc') or n.get('text') or '' for n in nodes)
  if '1515 / 1515 张图片' in text and '604 / 604 张图片' in text and '下一次扫描已排队' not in text:break
  assert time.monotonic()<deadline
 screen_text('18-final-independent-roots');after=snapshot('new-service','after-native-queue');protected=[k for k in before['tables'] if k.startswith('pack_') and k not in ['pack_pages'] or k in ['tags','video_tags','videos','file_operations','file_steps','trash_items','playback_rounds','round_entries','recent_entries','request_records']]
 for k in protected:assert before['tables'][k]==after['tables'][k],k
 assert before['opaque_table_digests']['access_tokens']==after['opaque_table_digests']['access_tokens'];records=[json.loads(line) for line in (L/'requests.jsonl').read_text().splitlines()];posts=[r for r in records if r['method']=='POST' and r['path']=='/api/v1/scans'];assert [r['scan_request'] for r in posts]==[{'all':False,'root_id':'packs-a'},{'all':False,'root_id':'packs-b'},{'all':False,'root_id':'packs-a'}],posts
 tasks=[api.call('GET','/api/v1/tasks/'+i) for i in [a1,b1,a2]]
 for task,rid in zip(tasks,['packs-a','packs-b','packs-a']):assert task['result']['scope']=={'all':False,'root_ids':[rid]},task['result']['scope']
 assert tasks[0]['finished_at']<=tasks[1]['finished_at']<=tasks[2]['finished_at']
 hashes=json.loads((L/'new-media-baseline.json').read_text());assert all(hashlib.sha256((MEDIA/f).read_bytes()).hexdigest()==h for f,h in hashes.items());save('passed',exact_scan_POSTs=3,final_A_images=1515,final_B_images=604)
 (L/'queue-native-checks.json').write_text(json.dumps({'normal_code':25,'service_source':'430fede546fe7649bdffeb7f399c6d86b6bbb212','events':events,'baseline':baseline,'final':s,'tasks':tasks,'scan_posts':posts,'read_only_User_tables_preserved':protected,'access_tokens_equal':True,'baseline_public_file_hashes_kept':len(hashes),'new_synthetic_files':1600,'original_media_or_NAS_changes':False,'passive_offline_state_retained_and_actions_disabled':True,'offline_backend_progress':[processed_start,processed_end],'visual_review':'pending','no_performance_claim':True},indent=2)+'\n')
finally:stop.set();thread.join(timeout=3)
