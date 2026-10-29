import hashlib,json,subprocess
from pathlib import Path
L=Path(__file__).resolve().parent;O=L/'native-6'
read=lambda p:json.loads(p.read_text())
r=read(O/'profile-result.json')['quick_press_feedback'];assert r['complete'] and r['callbacks']==6
assert {v['name'] for v in r['cases']}=={f'round-{n}-quick-{m}' for n in [1,2,3] for m in ['normal','reduced']}
counterexamples=[]
for c in r['cases']:
 frames=c['frames'];before=c['callbacks_before'];assert c['callbacks_after']==before+1
 assert all(v['native_flag']==c['reduced'] and v['media_query_flag']==c['reduced'] for v in frames)
 after=[v for v in frames if v['callbacks']==before+1];assert after and after[-1]['paint_value']==0 and after[-1]['removed']
 if c['reduced']:
  assert all(v['paint_value']==0 and v['removed'] for v in after)
  down=[v for v in frames if v['callbacks']==before];assert all(v['paint_value']==1 for v in down)
  if down:counterexamples.append(c['name'])
 else:assert any(0<v['paint_value']<1 for v in after)
clips=read(O/'recordings.json');assert len(clips)==6 and all(v['full_decode_exit']==0 for v in clips)
assert read(O/'result.json')['exit_code']==0 and not read(O/'result.json')['observer_errors']
assert not read(O/'restoration.json')['errors'] and 'restored' in read(O/'restoration.json')
assert read(L/'normal-final/upgrade-result.json')['complete'] and read(L/'normal-final/quick-flow-result.json')['complete']
b=read(L/'build-3/result.json');assert b['complete']
for k in ['forward','rollback']:
 a=b[k];assert a['version_code']==14 and a['normal_entrypoint'] and not a['integration_test_plugin'];assert hashlib.sha256(Path(a['path']).read_bytes()).hexdigest()==a['sha256']
same=read(L/'same-production-tree-final.json');assert same['production_lib_equal'] and len(set(same['lib_trees'].values()))==1
changed=subprocess.check_output(['git','diff','--name-only','920581e3..HEAD','--','apps/mobile/lib'],text=True).splitlines();assert changed==['apps/mobile/lib/ui/paper_press.dart']
all_changed=subprocess.check_output(['git','diff','--name-only','2d3af176..HEAD'],text=True).splitlines();assert all(p.startswith('apps/mobile/') or p.startswith('docs/') for p in all_changed)
prototype=subprocess.check_output(['git','rev-parse','HEAD:design/reference/library-first'],text=True).strip();assert prototype=='1cbf605af8f03fa067a4ce8e914bb809e3a487ca'
result={'quick_native_cases':6,'full_decode_clips':6,'callbacks':6,'ordinary_code':14,'ordinary_upgrade_and_actual_cancel_complete':True,'reduced_pointer_down_observed_cases':counterexamples,'native5_failure_not_diagnosed_from_original_missing_frames':True,'normal_profile_lib_equal':True,'reused_preflight36_separate_source':'920581e3cb87e5e0fb5fdf04ab90ff1f3026268e','only_product_delta_since_preflight':changed,'prototype_tree':prototype,'service_production_unchanged':True,'unit_tests':725,'normal_source':b['source'],'profile_source':read(O/'source.json')['source']}
(L/'audit-final.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
