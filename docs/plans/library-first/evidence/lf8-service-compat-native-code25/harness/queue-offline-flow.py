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
def wait(fn,seconds=180):
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
baseline=state();assert not baseline['scanning'];base=roots(baseline);assert base['packs-a']['scan']['progress']['processed']==515;assert base['packs-b']['scan']['progress']['processed']==4;before=snapshot('new-service','before-native-queue');thread=threading.Thread(target=watch,daemon=True);thread.start()
try:
 click_root(1,['扫描此目录']*3,'scan-A-once');s=wait(lambda s: roots(s)['packs-a']['scan']['task_id']!=base['packs-a']['scan']['task_id'] and roots(s)['packs-a']['scan']['status'] in ACTIVE);r=roots(s);a1=r['packs-a']['scan']['task_id'];assert r['packs-b']==base['packs-b'];save('A-active',A1=a1,root_B_unchanged=True);text,_=screen_text('12-A-active-B-kept');assert 'Packs A' in text and 'Packs B' in text and '4 / 4 张图片' in text
 click_root(2,['扫描此目录','正在扫描','扫描此目录'],'queue-B-once-while-A-active');s=wait(lambda s: bool(roots(s)['packs-b']['queued_task_ids']));r=roots(s);assert r['packs-b']['scan']==base['packs-b']['scan'];b1=r['packs-b']['queued_task_ids'][0];save('B-queued',B1=b1,root_B_old_fact_retained=True);text,_=screen_text('13-B-queued-old-completion-kept');assert '下一次扫描已排队' in text and '4 / 4 张图片' in text
 # Disconnect only App transport. Service/control endpoint remains running.
 offline_start=state();p=json.loads((L/'proxy-process.json').read_text());command=subprocess.check_output(['ps','-p',str(p['pid']),'-o','command='],text=True);assert p['script'] in command;os.kill(p['pid'],signal.SIGTERM);save('App-transport-offline',offline_started=time.time());deadline=time.monotonic()+45
 while True:
  _,nodes=ui.xml();text='\n'.join(n.get('content-desc') or n.get('text') or '' for n in nodes)
  if '下方保留上次同步的记录。' in text:break
  assert time.monotonic()<deadline,'offline state not visible'
 text,nodes=screen_text('14-offline-records-preserved');assert 'Packs A' in text and 'Packs B' in text and '4 / 4 张图片' in text and '0 / 0' not in text;actions=[n for n in nodes if n.get('class')=='android.widget.Button' and (n.get('content-desc') or n.get('text')) in ['扫描此目录','正在扫描','已排队','全部扫描']];assert actions and all(n.get('enabled')=='false' for n in actions)
 offline_end=state();processed_start=roots(offline_start)['packs-a']['scan']['progress']['processed'];processed_end=roots(offline_end)['packs-a']['scan']['progress']['processed'];assert processed_end>processed_start,(processed_start,processed_end);save('offline-verified',offline_A_processed_before=processed_start,offline_A_processed_after=processed_end)
 with (L/'new-proxy-reconnected.log').open('wb') as out:process=subprocess.Popen(['python3',str(L/'new-proxy.py')],stdin=subprocess.DEVNULL,stdout=out,stderr=subprocess.STDOUT,start_new_session=True)
 p['pid']=process.pid;(L/'proxy-process.json').write_text(json.dumps(p,indent=2)+'\n');deadline=time.monotonic()+10
 while True:
  try:
   with socket.create_connection(('127.0.0.1',8783),timeout=1):pass
   break
  except OSError:assert time.monotonic()<deadline;time.sleep(.1)
 deadline=time.monotonic()+45
 while True:
  _,nodes=ui.xml();text='\n'.join(n.get('content-desc') or n.get('text') or '' for n in nodes)
  if '下方保留上次同步的记录。' not in text and 'Packs A' in text:break
  assert time.monotonic()<deadline
 screen_text('15-reconnected-live-progress');save('App-reconnected',reconnected_at=time.time())
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
