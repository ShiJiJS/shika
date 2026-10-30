import hashlib,json,time,urllib.request
from pathlib import Path
import business_ui as u,driver,snapshot_all
from ui_driver import device,record,tap
O=Path(__file__).resolve().parent;L=O.parent;M=L/'media/videos';B=L/'business-2';assert not B.exists();B.mkdir();events=[];headers={};checks=[]
def save(n,v):(B/n).write_text(json.dumps(v,indent=2,ensure_ascii=False)+'\n')
def req(method,path,value=None):
 b=None if value is None else json.dumps(value).encode()
 with urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:8772/api/v1'+path,data=b,headers={**headers,'Content-Type':'application/json'},method=method),timeout=20) as r:raw=r.read();status=r.status
 events.append({'time':time.time(),'method':method,'path':path,'status':status});save('business-requests.json',events);return json.loads(raw)
def state(name):
 v=req('GET','/library-state');save(name+'-service.json',v);return v
def wait_state(name,predicate):
 end=time.monotonic()+45
 while True:
  v=req('GET','/library-state')
  if predicate(v):save(name+'-service.json',v);return v
  assert time.monotonic()<end,v;time.sleep(.5)
def read(name,predicate):
 end=time.monotonic()+30
 while True:
  n=u.snap(name);text=driver.text(n)
  if predicate(n,text):return n
  assert time.monotonic()<end,(name,text);time.sleep(.3)
def count(n,text):return sum((v.get('content-desc') or v.get('text') or '').splitlines().count(text) for v in n)
def card(name,present,phrase=None):
 return read(name,lambda n,t:count(n,'目录扫描')==int(present) and (phrase is None or phrase in t))
def checkpoint(name,details):
 u.check(name,details);checks.append({'name':name,**details});save('business-result.json',{'complete':False,'checks':checks})
def scales(value):
 for k in ['window_animation_scale','transition_animation_scale','animator_duration_scale']:device('shell','settings','put','global',k,str(value))
 values={k:device('shell','settings','get','global',k).decode().strip() for k in ['window_animation_scale','transition_animation_scale','animator_duration_scale']};assert set(values.values())=={str(value)};record({'action':'system-motion','scales':values});return values
# The previous run captured actual scanning but counted only an exact standalone label.
# Preserve its terminal failure; repair only the dedicated test file before the new baseline.
headers['Authorization']='Bearer '+req('POST','/auth/login',{'passphrase':(O/'config/passphrase').read_text().strip()})['access_token']
p=M/'Expansion-probe.mp4';assert p.exists();source=next(x for x in sorted(M.rglob('*.mp4')) if x!=p);valid=source.read_bytes()
initial=state('entering-after-diagnostic');assert not initial['scanning'] and initial['counts']['failed']==1
card('run2-entering-real-read-failure',True,'媒体信息无法解析 1 个')
p.write_bytes(valid);record({'action':'owned-file-rewrite','file':p.name,'sha256':hashlib.sha256(valid).hexdigest(),'mode':'diagnostic-recovery'})
u.choose('重新扫描',context='run2-prepare-recovery');ready=wait_state('preparation-recovered',lambda v:not v['scanning'] and v['task_id']!=initial['task_id'])
assert ready['counts']['failed']==0 and not ready['failure_reasons'];card('run2-preparation-collapsed',False,'扫描完成')
snapshot_all.snapshot('normal','before-scan-business-2');before_prefs=driver.appearance('before-scan-business-2')
state0=state('business-baseline');assert not state0['scanning'] and state0['counts']['failed']==0
save('owned-sample.json',{'source':source.name,'valid_sha256':hashlib.sha256(valid).hexdigest(),'owned':p.name,'service_stability_seconds':15,'media_mounted_readonly':True})
for round in range(1,4):
 prefix=f'run2-round-{round}'
 card(prefix+'-initial-collapsed',False,'扫描完成')
 for mode,value in [('normal',1),('reduced',0)]:
  actual=scales(value)
  u.choose(prefix='扫描完成',context=prefix+'-'+mode+'-expand');card(prefix+'-'+mode+'-expanded',True,'扫描完成')
  u.choose(prefix='扫描完成',context=prefix+'-'+mode+'-collapse');card(prefix+'-'+mode+'-collapsed',False,'扫描完成')
  checkpoint(prefix+'-'+mode+'-directions',{'directions':2,'scales':actual,'completed_card_visible_only_expanded':True})
 scales(1)
 # Leave a completed detail open, then use the actual App action for the next scan.
 u.choose(prefix='扫描完成',context=prefix+'-open-before-update');card(prefix+'-open-before-update-visible',True,'扫描完成')
 invalid=('deliberately invalid owned fixture round '+str(round)).encode();p.write_bytes(invalid);record({'action':'owned-file-rewrite','file':p.name,'sha256':hashlib.sha256(invalid).hexdigest(),'bytes':len(invalid),'mode':'corrupt'})
 before=state(prefix+'-before-error-scan');u.choose('同步外部变更',context=prefix+'-request-error-scan')
 active=wait_state(prefix+'-scanning',lambda s:s['scanning'] and s['task_id']!=before['task_id'])
 assert active['status'] in ['queued','running'];n=card(prefix+'-scanning-visible',True,'等待文件写入稳定')
 checkpoint(prefix+'-scanning',{'task_id':active['task_id'],'real_service':True,'single_visible_detail':True})
 failed=wait_state(prefix+'-read-failure',lambda s:not s['scanning'] and s['task_id']==active['task_id'])
 assert failed['status']=='completed' and failed['phase']=='completed' and failed['counts']['failed']==1 and failed['failure_reasons']=={'probe_failed':1},failed
 n=card(prefix+'-failed-visible',True,'媒体信息无法解析 1 个');assert '1 个视频信息读取失败' in driver.text(n)
 checkpoint(prefix+'-read-failure',{'task_id':failed['task_id'],'task_status':failed['status'],'failed_count':1,'single_visible_detail':True,'failure_reason':'probe_failed'})
 # Replace only the dedicated test file; no donor or real-media mutation.
 p.write_bytes(valid);record({'action':'owned-file-rewrite','file':p.name,'sha256':hashlib.sha256(valid).hexdigest(),'bytes':len(valid),'mode':'valid'})
 u.choose('重新扫描',context=prefix+'-request-recovery-scan')
 recovering=wait_state(prefix+'-recovery-scanning',lambda s:s['scanning'] and s['task_id']!=failed['task_id'])
 card(prefix+'-recovery-scanning-visible',True,'等待文件写入稳定')
 done=wait_state(prefix+'-completed',lambda s:not s['scanning'] and s['task_id']==recovering['task_id'])
 assert done['status']=='completed' and done['counts']['failed']==0 and not done['failure_reasons'] and done['counts']['deferred']==0,done
 n=card(prefix+'-completed-collapsed',False,'扫描完成');assert not u.matches(n,label='重新扫描')
 u.choose(prefix='扫描完成',context=prefix+'-recovery-expand');n=card(prefix+'-recovery-expanded',True,'扫描完成');assert count(n,'重新扫描')==1 and '媒体信息无法解析' not in driver.text(n)
 u.choose(prefix='扫描完成',context=prefix+'-recovery-collapse');card(prefix+'-recovery-collapsed',False,'扫描完成')
 checkpoint(prefix+'-recovery-completed',{'task_id':done['task_id'],'task_status':done['status'],'failed_count':0,'collapsed_after_replacement':True,'reopened_correct_single_detail':True})
assert len(checks)==15
final=state('business-final');assert final['counts']['failed']==0 and not final['scanning'];snapshot_all.snapshot('normal','after-scan-business-2');assert before_prefs==driver.appearance('after-scan-business-2')
save('business-result.json',{'complete':True,'checks':checks,'rounds':3,'ordinary_reduced_directions':12,'additional_open_before_scan':3,'recovery_directions':6,'service_scans':6,'state_checkpoints':9,'no_forced_service_status_or_clock':True,'normal_main_release':True,'prefs_preserved':True,'not_normal_package_frame_timing_proof':True})
print('3 real-service rounds complete',flush=True)
