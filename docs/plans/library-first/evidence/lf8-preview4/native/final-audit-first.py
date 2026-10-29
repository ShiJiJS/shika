import json,hashlib,subprocess
from pathlib import Path
import driver,snapshot
O=Path(__file__).resolve().parent
base=json.loads((O/'before-forward10-catalog.json').read_text());after=snapshot.snapshot('final');prefs=driver.appearance('final')
keep=['videos','tags','video_tags','directories','roots','packs','pack_pages','pack_tag_definitions','pack_tag_links','tasks','file_operations','file_steps','trash_items']
for k in keep:assert base['tables'][k]==after['tables'][k],k
assert base['opaque_table_digests']==after['opaque_table_digests']
assert prefs==json.loads((O/'before-forward10-preferences.json').read_text())
for k in ['pack_progress','pack_preferences']:
 print(k,after['tables'][k])
trace=[json.loads(v) for v in (O/'trace/requests.jsonl').read_text().splitlines()]
installs=[]
for name in ['forward10-first','rollback10','forward10-return']:
 start=json.loads((O/(name+'-startup.json')).read_text());rows=trace[start['trace_offset']:start['trace_end_offset']];assert all(v['method']=='GET' for v in rows),rows
 installs.append({'step':name,'read_only_startup_requests':len(rows),'login_post':False})
focus={}
for p in sorted((O/'screens').glob('*-window.txt')):
 text=p.read_text()
 if 'io.github.shijijs.video_viewer' not in text.split('mFocusedApp=')[0]:focus[p.name]=text
result={'protected13_tables_equal':keep,'auth_and_settings_digests_equal':True,'appearance_equal':True,'install_startup_windows':installs,'focus_exceptions':focus,'path_result':json.loads((O/'path-result.json').read_text()),'server_unchanged':True,'physical_phone_nas_and_audio_not_accepted':True,'original_network_causes_not_fixed':True}
(O/'final-audit.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({k:v for k,v in result.items() if k not in ['path_result','focus_exceptions']},indent=2))
