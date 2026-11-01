import json,subprocess,time
from pathlib import Path
import media
from snapshot_all import snapshot
L=Path(__file__).resolve().parent;P=L.parent/'lf8-pack-purge-native26';A=L.parent/'lf8-restored-image-read26'
r=json.loads((L/'runtime.json').read_text());build=json.loads((L/'build-source.json').read_text())
assert (L/'original-scan-conflict-reproduced.json').is_file() and (L/'before-scan-fix-private.tar').is_file()
old=json.loads(subprocess.check_output(['docker','inspect',r['id']]))[0]
assert old['Config']['Labels']['vv.owned']=='lf8-pack-purge-native26' and old['Config']['Labels']['vv.source'].startswith('82eacdbd')
before=snapshot('normal26','before-candidate-upgrade');files=media.save('before-candidate-upgrade')
assert len(files)==49
subprocess.run(['docker','stop','--time','30',r['id']],check=True,capture_output=True)
assert not json.loads(subprocess.check_output(['docker','inspect',r['id']]))[0]['State']['Running']
subprocess.run(['docker','rm',r['id']],check=True,capture_output=True)
args=['docker','run','-d','--name',r['name'],'--label','vv.owned=lf8-pack-purge-native26','--user','0:0','-p','127.0.0.1:8788:8760','-e','PYTHONPATH=/fixture:/app','-e','VV_SCAN_INTERVAL=0']
for mount in old['Mounts']:
    assert Path(mount['Source']).is_relative_to(P)
    args+=['--mount','type=bind,source='+mount['Source']+',target='+mount['Destination']+(',readonly' if not mount['RW'] else '')]
args+=['--entrypoint','python',build['runtime'],*old['Config']['Cmd']]
cid=subprocess.check_output(args,text=True).strip();r.update(id=cid,source=build['source'],image=build['runtime'],previous_id=old['Id'],phase='scan_fix_candidate_before_scan')
r.pop('stopped_for_issue',None)
for path in [L/'runtime.json',P/'runtime.json',A/'runtime.json']:path.write_text(json.dumps(r,indent=2))
deadline=time.monotonic()+45
while True:
    current=json.loads(subprocess.check_output(['docker','inspect',cid]))[0]
    if current['State']['Health']['Status']=='healthy':break
    assert current['State']['Running'] and time.monotonic()<deadline;time.sleep(.2)
assert sorted(old['Config']['Env'])==sorted(current['Config']['Env'])
for key in ['User','Cmd','Entrypoint','Healthcheck']:assert old['Config'][key]==current['Config'][key],key
assert sorted((m['Source'],m['Destination'],m['RW']) for m in old['Mounts'])==sorted((m['Source'],m['Destination'],m['RW']) for m in current['Mounts'])
after=snapshot('normal26','candidate-after-start')
for key in ['tables','opaque_table_digests','setting_key_sha256']:assert before[key]==after[key],key
assert media.files()==files
result={'previous_container':old['Id'],'current_container':cid,'old_source':old['Config']['Labels']['vv.source'],'new_source':build['source'],'same_mounts_env_user_command_entrypoint_healthcheck':True,'all_37_tables_settings_equal_before_any_scan':True,'all_49_fixture_files_byte_identical':True,'private_backup_already_retained':True,'healthy':True,'restart_count':current['RestartCount'],'nas_accessed':False,'no_new_scan_restore_permanent_request':True}
(L/'upgrade-public.json').write_text(json.dumps(result,indent=2));print(json.dumps(result),flush=True)
