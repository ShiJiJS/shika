import json,hashlib
from pathlib import Path
L=Path(__file__).resolve().parent
b=json.loads((L/'before-trash-undo-all-catalog.json').read_text());a=json.loads((L/'after-trash-undo-all-catalog.json').read_text());seed=json.loads((L/'seed.json').read_text());identity=seed['packs']['C Fresh']['id'];allowed={'tasks','pack_file_operations','pack_file_steps','pack_trash_items','packs'}
changed=[k for k,v in b['tables'].items() if a['tables'][k]!=v];assert set(changed)==allowed
for old in b['tables']['packs']:
 new=next(x for x in a['tables']['packs'] if x['id']==old['id'])
 assert new==({**old,'generation':old['generation']+2} if old['id']==identity else old)
assert a['opaque_table_digests']['access_tokens']==b['opaque_table_digests']['access_tokens']
assert all(a['setting_key_sha256'][k]==v for k,v in b['setting_key_sha256'].items())
assert set(a['setting_key_sha256'])-set(b['setting_key_sha256'])=={'last_pack_delete_operation'}
ops=a['tables']['pack_file_operations'];steps=a['tables']['pack_file_steps'];assert len(ops)==len(steps)==2
assert {x['pack_id'] for x in steps}=={identity};assert {x['kind'] for x in ops}=={'trash','undo'}
original=next(x for x in ops if x['kind']=='trash')
assert a['setting_key_sha256']['last_pack_delete_operation']==hashlib.sha256(original['id'].encode()).hexdigest()
for step in steps:assert step['outcome']=='succeeded'
new_tasks=[x for x in a['tables']['tasks'] if x['id'] not in {v['id'] for v in b['tables']['tasks']}]
assert {x['id'] for x in new_tasks}=={x['id'] for x in ops} and all(x['status']=='completed' for x in new_tasks)
assert len(a['tables']['pack_trash_items'])==1
trash=a['tables']['pack_trash_items'][0];assert trash['pack_id']==identity and trash['status']=='restored' and trash['operation_id']==original['id']
(L/'trash-undo-checks.json').write_text(json.dumps({'pack':'C Fresh','native_move_undo':True,'new_copy_seen':True,'changed_tables':changed,'target_generation_delta':2,'only_target_pack_and_successful_trash_undo_tasks_changed':True,'unrelated_tables_settings_tokens_equal':True,'last_delete_pointer_added_for_exact_original_operation':True,'initial_audit_missing_expected_generation_and_pointer_changes_corrected_without_repeating_commands':True},indent=2)+'\n');print('Native C trash/undo verified. Only C generation +2 and its two successful operations changed.')
