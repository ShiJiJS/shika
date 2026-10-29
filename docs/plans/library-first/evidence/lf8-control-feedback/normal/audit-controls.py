"""Audit existing normal-release actions; never repeat a command."""
import json,xml.etree.ElementTree as ET
from pathlib import Path
O=Path(__file__).resolve().parent
read=lambda name:json.loads((O/name).read_text())
b=read('before-real-controls-catalog.json');a=read('after-real-controls-catalog.json');d=read('before-tag-draft-catalog.json')
changed={k for k in b['tables'] if b['tables'][k]!=a['tables'][k]}
assert changed=={'pack_progress','pack_preferences','request_records','pack_sessions','pack_session_entries','recent_entries'},changed
bp=b['tables']['pack_progress'][0];ap=a['tables']['pack_progress'][0]
assert {k:v for k,v in bp.items() if k not in ['revision','updated_at']}=={k:v for k,v in ap.items() if k not in ['revision','updated_at']}
assert ap['revision']==bp['revision']+2
p=b['tables']['pack_preferences'][0];q=a['tables']['pack_preferences'][0]
assert {k:v for k,v in p.items() if k!='revision'}=={k:v for k,v in q.items() if k!='revision'}
assert q['revision']==p['revision']+2 and q['mode']=='vertical'
for k in ['videos','tags','video_tags','packs','pack_pages','pack_tag_definitions','pack_tag_links','tasks','file_operations','file_steps','trash_items']:
 assert d['tables'][k]==a['tables'][k],k
new=[v for v in a['tables']['request_records'] if v not in d['tables']['request_records']]
assert len(new)==1 and new[0]['id'].startswith('pack.opened:')
r=json.loads(new[0]['result']);assert r['page_index']==1 and r['offset_ratio']==0 and r['preferences']['mode']=='vertical' and r['revision']==17
trace=[json.loads(v) for v in (O/'trace/requests.jsonl').read_text().splitlines()]
posts=[v for v in trace if v['time']>=b['observed_at'] and v['method'] not in ['GET','HEAD']]
assert len(posts)==5 and all(v['status'] in [200,201] for v in posts),posts
assert sum(v['method']=='PATCH' and v['path'].endswith('/preferences') for v in posts)==2
assert sum(v['method']=='POST' and v['path']=='/api/v1/pack-sessions' for v in posts)==1
assert sum(v['method']=='POST' and v['path'].endswith('/opened') for v in posts)==2
assert b['opaque_table_digests']['access_tokens']==a['opaque_table_digests']['access_tokens']
for name,label in [('release13-horizontal-after','横向翻页'),('release13-vertical-reduced-after','纵向拼接')]:
 nodes=ET.parse(O/'screens'/f'{name}.xml').iter('node');assert any(v.get('content-desc')==label and v.get('selected')=='true' for v in nodes)
nodes=ET.parse(O/'screens/release13-tag-draft-after.xml').iter('node');assert any(v.get('content-desc')=='PACK_ONLY' and v.get('selected')=='false' for v in nodes)
nodes=ET.parse(O/'screens/release13-source-return.xml').iter('node');assert any(v.get('content-desc')=='图包操作 Upgrade Pack' for v in nodes)
result={'complete':True,'ordinary_code':13,'actual_modes_horizontal_then_vertical':True,'live_system_reduced_in_open_reader_settings':True,'tag_draft_deselected_then_cancelled':True,'returned_page_index':1,'page_id_offset_and_completed_equal':True,'final_preferences_same_except_two_revisions':True,'unchanged_business_tables_count':15,'cancel_content_tags_tasks_and_file_tables_equal':True,'actual_write_requests':posts,'deferred_exit_request_explained':new[0]['id'],'new_session_count':1,'original_audit_failure':'Incorrectly required request_records unchanged across reader exit; exact readback is one successful pack.opened for the same page/offset, with ordinary progress revision and recent timestamp. Original script/log retained; no command replay.'}
(O/'controls-result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps(result,ensure_ascii=False))
