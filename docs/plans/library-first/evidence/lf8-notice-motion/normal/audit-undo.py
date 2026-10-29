"""Audit existing observations only. Never repeat a file command."""
import hashlib,json,subprocess,xml.etree.ElementTree as ET
from pathlib import Path
O=Path(__file__).resolve().parent;R=O.parents[2]
def read(n):return json.loads((O/n).read_text())
b=read('before-real-undo-catalog.json');a=read('after-real-undo-catalog.json')
changes=[k for k in b['tables'] if b['tables'][k]!=a['tables'][k]]
assert set(changes)=={'packs','tasks'},changes
bp=b['tables']['packs'][0];ap=a['tables']['packs'][0]
diff={k:[bp[k],ap[k]] for k in bp if bp[k]!=ap[k]}
assert diff=={'generation':[3,5]},diff
new=[v for v in a['tables']['tasks'] if v not in b['tables']['tasks']]
assert len(new)==2 and {v['kind'] for v in new}=={'pack_trash','pack_undo'}
for v in new:
 assert v['status']=='completed';v['result']=json.loads(v['result']);assert v['result']['succeeded']==1 and v['result']['failed']==0
trash=next(v for v in new if v['kind']=='pack_trash');undo=next(v for v in new if v['kind']=='pack_undo')
assert undo['finished_at']<trash['result']['undo_expires_at']
assert b['opaque_table_digests']['access_tokens']==a['opaque_table_digests']['access_tokens']
assert read('actual-undo-settings-result.json')['complete']
trace=[json.loads(v) for v in (O/'trace/requests.jsonl').read_text().splitlines()]
write=[v for v in trace if v['time']>=trash['created_at'] and v['method']!='GET']
assert len(write)==2 and all(v['status']==202 for v in write),write
assert write[0]['path']=='/api/v1/packs/trash' and write[1]['path']==f"/api/v1/pack-operations/{trash['id']}/undo"
events=[json.loads(v) for v in (O/'ui-events.jsonl').read_text().splitlines()]
confirm=next(v for v in events if v.get('label')=='confirm disposable whole-pack trash');tap=next(v for v in events if v.get('label')=='actual undo within observed prompt')
assert 0<tap['time']-confirm['time']<8
nodes=list(ET.parse(O/'screens/release12-undo-result.xml').iter('node'))
assert any(v.get('content-desc')=='图包操作 Upgrade Pack' for v in nodes)
meta=read('runtime.json');cmd=meta['command'];media=[v for v in cmd if v.endswith(':/media/packs:ro')];assert len(media)==1
assert json.loads((O.parent/'normal-cleanup.json').read_text())['owned_container_removed']==meta['container']
p=Path(media[0].removesuffix(':/media/packs:ro'));hashes={str(v.relative_to(p)):hashlib.sha256(v.read_bytes()).hexdigest() for v in p.rglob('*') if v.is_file()}
result={'complete':True,'ordinary_release_code':12,'disposable_pack':'Upgrade Pack','successful_tasks':new,'actual_post_requests':write,'undo_tap_seconds_after_confirm':tap['time']-confirm['time'],'undo_completed_before_server_deadline':True,'pack_change_only':diff,'all_other_pack_fields_and_19_tables_equal':True,'opaque_auth_equal':True,'operation_settings_changes_explained_by_exact_before_hash':True,'source_mount_readonly':True,'source_hashes_observed_after_only':hashes,'initial_audit_assertion_failure':'Incorrectly required generation unchanged and expected logical-trash tasks in file_operations. The intermediate audit also incorrectly required settings unchanged; its failed assertion is retained. Exact hash reconstruction accounts for active-opened and last-delete markers. Original script/log retained; audited existing observations without replaying commands.'}
(O/'actual-undo-result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps(result,ensure_ascii=False))
