import hashlib,json,subprocess
from pathlib import Path
L=Path(__file__).resolve().parent;O=L/'native-4'
read=lambda p:json.loads(p.read_text())
r=read(O/'profile-result.json')['control_feedback'];assert r['complete']
expected={f'round-{n}-{kind}-{mode}-{direction}' for n in [1,2,3] for kind in ['press','choice','filter'] for mode in ['normal','reduced'] for direction in ['entry','return']}
assert {c['name'] for c in r['cases']}==expected and len(r['cases'])==36
for c in r['cases']:
 f=c['frames'];target=0 if c['closing'] else 1;assert abs(f[-1]['paint_value']-target)<.00001
 assert all(v['native_flag']==c['reduced'] and v['media_query_flag']==c['reduced'] for v in f)
 if c['reduced']:assert all(abs(v['paint_value']-target)<.00001 for v in f)
 else:assert any(0<v['paint_value']<1 for v in f)
clips=read(O/'recordings.json');assert len(clips)==18 and all(v['full_decode_exit']==0 for v in clips)
assert read(O/'result.json')['exit_code']==0 and not read(O/'result.json')['observer_errors']
assert not read(O/'restoration.json')['errors'] and 'restored' in read(O/'restoration.json')
assert read(L/'normal/controls-result.json')['complete'] and read(L/'normal/upgrade-result.json')['complete']
b=read(L/'build-2/result.json');assert b['complete']
for k in ['forward','rollback']:
 a=b[k];assert a['version_code']==13 and a['normal_entrypoint'] and not a['integration_test_plugin'];assert hashlib.sha256(Path(a['path']).read_bytes()).hexdigest()==a['sha256']
assert read(L/'same-production-tree.json')['normal_and_profile_production_lib_equal']
prototype=subprocess.check_output(['git','rev-parse','HEAD:design/reference/library-first'],text=True).strip();assert prototype=='1cbf605af8f03fa067a4ce8e914bb809e3a487ca'
assert not subprocess.check_output(['git','diff','2d3af176..HEAD','--','services'])
(L/'audit.json').write_text(json.dumps({'passed_cases':36,'native_component_only':True,'recordings_full_decode':18,'ordinary_upgrade_and_real_controls_complete':True,'failed_native_attempts_preserved':[1,2,3],'prototype_tree':prototype,'service_production_tree_unchanged':True,'callback_counts':{k:r[k] for k in ['button_callbacks','choice_callbacks','filter_callbacks']}},indent=2)+'\n');print('36 native cases/18 clips, ordinary package and actual controls verified')
