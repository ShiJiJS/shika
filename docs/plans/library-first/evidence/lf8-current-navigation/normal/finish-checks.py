import hashlib,json,subprocess,time
from pathlib import Path
import driver,business_ui as u
from ui_driver import device
from snapshot_all import snapshot
O=Path(__file__).resolve().parent;L=O.parent

def compare(a,b):
 return {'tables':[k for k in a['tables'] if a['tables'][k]!=b['tables'][k]],'opaque':[k for k in a['opaque_table_digests'] if a['opaque_table_digests'][k]!=b['opaque_table_digests'][k]],'settings':[k for k in set(a['setting_key_sha256'])|set(b['setting_key_sha256']) if a['setting_key_sha256'].get(k)!=b['setting_key_sha256'].get(k)]}

def installed(name,kind):
 path=device('shell','pm','path',driver.PACKAGE).decode().strip().removeprefix('package:');raw=device('exec-out','cat',path);sha=hashlib.sha256(raw).hexdigest();expected=json.loads((L/'build-1/result.json').read_text())[kind]['sha256'];assert sha==expected;driver.save(name+'-actual-apk.json',{'sha256':sha,'matches_build':True,'bytes':len(raw)})

installed('current21','forward');cold=[]
for i in range(1,4):
 name=f'cold21-{i}';u.choose('设置',context=name+'-settings');a=snapshot('new',name+'-before');p=driver.appearance(name+'-before');oldpid=device('shell','pidof',driver.PACKAGE).decode().strip();n=driver.cold(name,'new');text=driver.text(n)
 assert all(s in text for s in ['媒体库','标签','最近','设置']);assert '视频预览' not in text and '图包阅读' not in text
 newpid=device('shell','pidof',driver.PACKAGE).decode().strip();assert newpid!=oldpid
 b=snapshot('new',name+'-after');delta=compare(a,b);assert not any(delta.values()),delta;assert driver.appearance(name+'-after')==p
 meta=json.loads((O/(name+'-startup.json')).read_text());requests=(O/'trace/requests.jsonl').read_text().splitlines()[meta['trace_offset']:meta['trace_end_offset']];cold.append({'name':name,'old_pid':oldpid,'new_pid':newpid,'delta':delta,'request_lines':requests})
(L/'cold21-result.json').write_text(json.dumps({'complete':True,'code':21,'runs':cold,'default_media_library_and_four_entries':True},indent=2)+'\n')
covers=[]
for name,kind in [('rollback21','rollback'),('return21','forward')]:
 a=snapshot('new',name+'-before');p=driver.appearance(name+'-before');driver.install(name,kind);installed(name,kind);b=snapshot(kind,name+'-after');delta=compare(a,b);assert not any(delta.values()),delta;assert driver.appearance(name+'-after')==p;covers.append({'name':name,'kind':kind,'delta':delta})
(L/'cover21-result.json').write_text(json.dumps({'complete':True,'code':21,'runs':covers,'no_uninstall_clear_or_database_write':True,'all35_tables_settings_tokens_appearance_identity_preserved':True},indent=2)+'\n')
m=json.loads((O/'runtime.json').read_text());actual={}
for typ,expected in m['public_media_sha256'].items():
 root=O/typ;now={str(x.relative_to(root)):hashlib.sha256(x.read_bytes()).hexdigest() for x in sorted(root.rglob('*')) if x.is_file()};assert now==expected,typ;actual[typ]=now
(L/'media-integrity-final.json').write_text(json.dumps({'matches_original':True,'files':sum(len(x) for x in actual.values()),'sha256':actual},indent=2)+'\n')
print('ALL FINAL CHECKS PASSED',flush=True)
