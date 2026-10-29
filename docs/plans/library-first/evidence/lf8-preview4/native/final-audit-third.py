import json,hashlib,subprocess,sqlite3
from pathlib import Path
import driver,snapshot
O=Path(__file__).resolve().parent
base=json.loads((O/'before-forward10-catalog.json').read_text());after=snapshot.snapshot('final');prefs=driver.appearance('final')
keep=['videos','tags','video_tags','directories','roots','packs','pack_pages','pack_tag_definitions','pack_tag_links','tasks','file_operations','file_steps','trash_items']
for k in keep:assert base['tables'][k]==after['tables'][k],k
assert base['opaque_table_digests']['access_tokens']==after['opaque_table_digests']['access_tokens']
donor=Path(json.loads((O/'runtime.json').read_text())['donor'])/'data/library.sqlite3'
for cont in json.loads(subprocess.check_output(['docker','inspect',*subprocess.check_output(['docker','ps','-q'],text=True).split()])):
 for mount in cont['Mounts']:
  assert not donor.is_relative_to(Path(mount['Source']))
subprocess.run(['docker','exec','video-viewer-preview4-native','mkdir','-p','/tmp/inactive-donor'],check=True)
assert not list(donor.parent.glob('library.sqlite3-*')), 'Inactive baseline must have no outstanding WAL'
subprocess.run(['docker','cp',str(donor),'video-viewer-preview4-native:/tmp/inactive-donor/library.sqlite3'],check=True)
code="import sqlite3,json,hashlib,sys;c=sqlite3.connect('file:'+sys.argv[1]+'?mode=ro',uri=True);print(json.dumps({k:hashlib.sha256(v.encode()).hexdigest() for k,v in c.execute('SELECT key,value FROM settings')}));c.close()"
old_settings=json.loads(subprocess.check_output(['docker','exec','video-viewer-preview4-native','python','-c',code,'/tmp/inactive-donor/library.sqlite3']))
new_settings=json.loads(subprocess.check_output(['docker','exec','video-viewer-preview4-native','python','-c',code,'/data/library.sqlite3']))
assert set(old_settings)==set(new_settings)
changed_settings=[k for k in old_settings if old_settings[k]!=new_settings[k]]
assert set(changed_settings)<=set(['active_pack_opened','active_pack_session','active_round']),changed_settings
(O/'settings-digest-audit.json').write_text(json.dumps({'before_inactive_donor':old_settings,'after':new_settings,'changed_keys':changed_settings},indent=2)+'\n')
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
result={'protected13_tables_equal':keep,'auth_digest_equal':True,'only_expected_active_settings_changed':changed_settings,'appearance_equal':True,'install_startup_windows':installs,'focus_exceptions':focus,'path_result':json.loads((O/'path-result.json').read_text()),'server_unchanged':True,'physical_phone_nas_and_audio_not_accepted':True,'original_network_causes_not_fixed':True}
(O/'final-audit.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({k:v for k,v in result.items() if k not in ['path_result','focus_exceptions']},indent=2))
