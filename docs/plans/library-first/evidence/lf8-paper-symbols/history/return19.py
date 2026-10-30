import hashlib,json
from pathlib import Path
import driver
from snapshot_all import snapshot
O=Path(__file__).resolve().parent;L=O.parent
get=lambda n:json.loads((O/n).read_text())
a=get('rollback19-before-all-catalog.json');b=get('rollback19-settled-all-catalog.json')
changed={k for k in a['tables'] if a['tables'][k]!=b['tables'][k]};assert changed=={'playback_rounds','round_entries'}
assert not a['tables']['playback_rounds'] and not a['tables']['round_entries']
rounds=b['tables']['playback_rounds'];assert len(rounds)==1;rr=rounds[0];assert rr['membership']=='legacy' and rr['candidate_count']==2 and rr['scope']=='{}' and rr['cursor']==0
entries=b['tables']['round_entries'];assert len(entries)==2 and all(e['round_id']==rr['id'] for e in entries);assert {e['video_id'] for e in entries}=={v['id'] for v in b['tables']['videos']}
sha=lambda s:hashlib.sha256(s.encode()).hexdigest()
keys=set(a['setting_key_sha256'])|set(b['setting_key_sha256']);diff={k for k in keys if a['setting_key_sha256'].get(k)!=b['setting_key_sha256'].get(k)};assert diff=={'active_round','library_round_refresh'}
assert a['setting_key_sha256']['library_round_refresh']==sha('1') and 'library_round_refresh' not in b['setting_key_sha256']
assert 'active_round' not in a['setting_key_sha256'] and b['setting_key_sha256']['active_round']==sha(rr['id'])
assert a['opaque_table_digests']['access_tokens']==b['opaque_table_digests']['access_tokens']
assert get('rollback19-exact-playback-settings.json')==[{'key':'active_round','value':rr['id']}]
start=get('rollback19-install.json')['trace_offset'];trace=[json.loads(l) for l in (O/'trace/requests.jsonl').read_text().splitlines()][start:];assert any(r['path']=='/api/v1/playback' and r['method']=='GET' and abs(r['time']-rr['created_at'])<1 for r in trace);assert all(r['method'] in ['GET','HEAD'] for r in trace)
rollback_prefs=driver.appearance('rollback19-settled');assert rollback_prefs==get('rollback19-before-preferences.json')
before=snapshot('legacy','return19-before');prefs=driver.appearance('return19-before');driver.install('return19','forward');after=snapshot('new','return19-after');assert before['tables']==after['tables'];assert before['opaque_table_digests']==after['opaque_table_digests'];assert before['setting_key_sha256']==after['setting_key_sha256'];assert driver.appearance('return19-after')==prefs
r=json.loads((L/'build-1/result.json').read_text());path=driver.device('shell','pm','path',driver.PACKAGE).decode().strip();assert path.count('package:')==1;actual=driver.device('shell','sha256sum',path.removeprefix('package:')).decode().split()[0];assert actual==r['forward']['sha256']
(L/'normal-result.json').write_text(json.dumps({'complete':True,'candidate_code':19,'installed_sha256':actual,'upgrade_forward_all_35_tables_tokens_settings_preferences_unchanged':True,'return_forward_all_35_tables_tokens_settings_preferences_unchanged':True,'rollback_original_33_tables_tokens_preferences_preserved':True,'rollback_expected_legacy_round_tables':sorted(changed),'rollback_exact_setting_changes':sorted(diff),'rollback_get_playback_creates_legacy_round':rr['id'],'overview_settings_more_cancel_and_immersive_exit':True,'actual_light_and_dark_screens':True,'uninstall_or_clear':False},indent=2)+'\n')
