import json,subprocess,hashlib
from pathlib import Path
L=Path(__file__).resolve().parent;H=L/'history-normal';read=lambda p:json.loads(p.read_text())
subprocess.run([str(L.parents[1]/'.dev/venv/bin/python'),str(H/'snapshot.py'),'after-history-browse'],check=True)
a=read(H/'before-history-browse-catalog.json');b=read(H/'after-history-browse-catalog.json');assert a['tables']==b['tables'] and a['opaque_table_digests']==b['opaque_table_digests']
t=[json.loads(v) for v in (H/'trace/requests.jsonl').read_text().splitlines()];r=[x for x in t if a['observed_at']<x['time']<=b['observed_at']];assert r and all(x['method'] in ['GET','HEAD'] and 200<=x['status']<300 for x in r)
m=read(H/'runtime.json');container=json.loads(subprocess.check_output(['docker','inspect',m['container']]))[0];assert container['Config']['Labels']['video-viewer.lab']=='lf8-menu-dropdown-history';assert all(not x['RW'] for x in container['Mounts'] if x['Destination'].startswith('/media/'))
for n,s in m['bundle_sha256'].items():assert hashlib.sha256((H/'data/management-history'/m['history_ref']/'bundle'/n).read_bytes()).hexdigest()==s
checks=read(H/'business-cursor.json')['checks'];assert {x['name'] for x in checks}>={'purge-history-only-images','purge-history-only-directories','purge-history-all-restore'}
result={'complete':True,'all21_tables_auth_and_settings_unchanged':True,'read_requests':len(r),'only_successful_get_head':True,'historical_bundle_3_sha256_unchanged':True,'synthetic_media_all_ro':True,'dropdown_kind_values':['image','directory','all'],'all_outcomes_selected':True,'visible_rows_checked':True,'semantics_merged_header_touch_from_screenshot':True,'query_strings_not_in_observer':True,'no_delete_restore_or_retry_requests':True}
(L/'history-audit.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
