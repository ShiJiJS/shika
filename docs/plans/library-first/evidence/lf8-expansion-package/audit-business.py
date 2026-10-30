import json,hashlib,struct,xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path
L=Path(__file__).resolve().parent;O=L/'normal';B=L/'business-2';read=lambda p:json.loads(p.read_text())
def rows(n):return read(O/(n+'-all-catalog.json'))
def equal(a,b):assert a['tables']==b['tables'] and a['opaque_table_digests']==b['opaque_table_digests']
a=rows('before18');assert len(a['tables'])==35
for n in ['forward18','rollback18','forward18-return']:
 equal(a,rows('after-'+n));v=read(O/(n+'-install.json'));assert v['no_uninstall_or_clear']
 assert all(v['before'][k]==v['after'][k] for k in ['firstInstallTime','dataDir','appId'])
 assert v['after']['versionCode'].split()[0]=='18'
 assert read(O/'before18-preferences.json')==read(O/('after-'+n+'-preferences.json'))
r=read(B/'business-result.json');assert r['complete'] and r['rounds']==3 and len(r['checks'])==15 and r['service_scans']==6 and r['state_checkpoints']==9
proof=[]
def count(nodes,phrase):return sum((n.get('content-desc') or n.get('text') or '').splitlines().count(phrase) for n in nodes)
def check_screen(suffix,present,phrase=None):
 candidates=sorted((O/'screens').glob('*-'+suffix+'.xml'));assert candidates,suffix;p=candidates[-1];nodes=list(ET.parse(p).iter('node'));text='\n'.join((n.get('content-desc') or n.get('text') or '') for n in nodes)
 assert count(nodes,'目录扫描')==int(present),(p,count(nodes,'目录扫描'))
 if phrase:assert phrase in text
 if present and suffix.endswith('-failed-visible'):assert '1 个视频信息读取失败' in text
 if suffix.endswith('-recovery-expanded'):assert count(nodes,'重新扫描')==1 and '媒体信息无法解析' not in text
 if not present:assert count(nodes,'重新扫描')==0
 png=p.with_suffix('.png').read_bytes();assert png.startswith(b'\x89PNG\r\n\x1a\n') and struct.unpack('>II',png[16:24])==(1170,2532)
 assert 'io.github.shijijs.video_viewer' in p.with_name(p.stem+'-window.txt').read_text()
 proof.append({'xml':str(p.relative_to(L)),'card_visible':present,'phrase':phrase});return p
ids=[]
for n in [1,2,3]:
 prefix=f'run2-round-{n}'
 for mode,value in [('normal','1'),('reduced','0')]:
  check_screen(prefix+'-'+mode+'-expanded',True,'扫描完成');check_screen(prefix+'-'+mode+'-collapsed',False,'扫描完成')
  c=next(c for c in r['checks'] if c['name']==prefix+'-'+mode+'-directions');assert c['directions']==2 and set(c['scales'].values())=={value}
 check_screen(prefix+'-open-before-update-visible',True,'扫描完成')
 check_screen(prefix+'-scanning-visible',True,'等待文件写入稳定')
 check_screen(prefix+'-failed-visible',True,'媒体信息无法解析 1 个')
 check_screen(prefix+'-recovery-scanning-visible',True,'等待文件写入稳定')
 check_screen(prefix+'-completed-collapsed',False,'扫描完成')
 check_screen(prefix+'-recovery-expanded',True,'扫描完成');check_screen(prefix+'-recovery-collapsed',False,'扫描完成')
 active=read(B/(prefix+'-scanning-service.json'));failed=read(B/(prefix+'-read-failure-service.json'));recover=read(B/(prefix+'-recovery-scanning-service.json'));done=read(B/(prefix+'-completed-service.json'))
 assert active['scanning'] and recover['scanning'] and active['task_id']==failed['task_id'] and recover['task_id']==done['task_id']
 assert active['task_id']!=recover['task_id'];ids.extend([active['task_id'],recover['task_id']])
 assert failed['status']=='completed' and failed['counts']['failed']==1 and failed['failure_reasons']=={'probe_failed':1}
 assert done['status']=='completed' and done['counts']['failed']==done['counts']['deferred']==0 and not done['failure_reasons']
assert len(ids)==len(set(ids))==6 and len(proof)==33
traces=[json.loads(v) for v in (O/'trace/requests.jsonl').read_text().splitlines()];post=Counter(x['path'] for x in traces if x['method']=='POST');assert post=={'/api/v1/auth/login':2,'/api/v1/scans':8},post
assert all(x['method'] in ['GET','HEAD','POST'] for x in traces)
assert all(x['status'] in [200,202] for x in traces if x['method']=='POST')
for n in ['baseline17','forward18','forward18-return']:
 w=read(O/(n+'-startup.json'));scope=traces[w['trace_offset']:w['trace_end_offset']];assert scope
 assert all(x['method'] in ['GET','HEAD'] and '/stream' not in x['path'] and not ('/pages/' in x['path'] and x['path'].endswith('/image')) for x in scope)
a=rows('before-scan-business-2');b=rows('after-scan-business-2');changed={k for k in a['tables'] if a['tables'][k]!=b['tables'][k]}
allowed={'tasks','roots','observations','videos','directories','packs','pack_pages'};assert changed<=allowed,(changed-allowed)
assert a['opaque_table_digests']['access_tokens']==b['opaque_table_digests']['access_tokens']
assert a['opaque_table_digests']['settings']['rows']==b['opaque_table_digests']['settings']['rows']
marker=read(L/'settings-marker-proof.json');key=marker['key'];assert key=='pack_root_scan_v1:packs'
assert a['setting_key_sha256'].keys()==b['setting_key_sha256'].keys()
assert {k:v for k,v in a['setting_key_sha256'].items() if k!=key}=={k:v for k,v in b['setting_key_sha256'].items() if k!=key}
for snap,field in [(a,'before_reconstructed_value'),(b,'after_observed_value')]:
 value=marker[field];assert hashlib.sha256(value.encode()).hexdigest()==snap['setting_key_sha256'][key]
 root=next(x for x in snap['tables']['roots'] if x['id']=='packs')
 assert json.loads(value)=={'path':root['path'],'last_scan':root['last_scan'],'identity':marker['directory_identity']}
old_tasks={x['id']:x for x in a['tables']['tasks']};new_tasks={x['id']:x for x in b['tables']['tasks']};assert all(new_tasks[k]==v for k,v in old_tasks.items());assert set(new_tasks)-set(old_tasks)==set(ids)
for name,fields in [('roots',{'last_scan'}),('directories',{'seen_scan'}),('packs',{'seen_scan'}),('pack_pages',{'seen_scan'})]:
 def project(v):return sorted([{k:x for k,x in row.items() if k not in fields} for row in v['tables'][name]],key=lambda x:json.dumps(x,sort_keys=True))
 assert project(a)==project(b),name
# The dedicated sample exists before successful three-round baseline; identity and content return.
old_v={x['id']:x for x in a['tables']['videos']};new_v={x['id']:x for x in b['tables']['videos']};assert old_v.keys()==new_v.keys()
for key,old in old_v.items():
 owned=old['name']=='Expansion-probe.mp4';ignored={'seen_scan'}|({'mtime_ns','ctime_ns','thumbnail'} if owned else set())
 assert {k:v for k,v in old.items() if k not in ignored}=={k:v for k,v in new_v[key].items() if k not in ignored},key
 if owned:
  assert new_v[key]['sha256']==read(B/'owned-sample.json')['valid_sha256']
  before_poster=(O/'data/thumbnails'/old['thumbnail']).read_bytes();after_poster=(O/'data/thumbnails'/new_v[key]['thumbnail']).read_bytes()
  assert hashlib.sha256(before_poster).digest()==hashlib.sha256(after_poster).digest()
assert read(O/'before-scan-business-2-preferences.json')==read(O/'after-scan-business-2-preferences.json')==read(O/'before18-preferences.json')
result={'complete':True,'upgrade_checks':3,'preserved_business_tables':35,'normal_main':True,'rounds':3,'ordinary_reduced_directions':12,'extra_open_before_update':3,'recovery_directions':6,'real_scan_state_checks':9,'critical_xml_png_states':33,'successful_scan_tasks':ids,'post_counts':dict(post),'changed_tables_during_final_6_scans':sorted(changed),'no_restore_delete_or_backup_commands':True,'three_round_table_projection_equal':True,'full_goal_acceptance':False}
(L/'scan-state-proof.json').write_text(json.dumps(proof,indent=2,ensure_ascii=False)+'\n');(L/'business-audit.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
