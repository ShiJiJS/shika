"""Independently cross-check captured data, native requests and immutable build."""
import hashlib,json,struct,subprocess
from pathlib import Path
import media
L=Path(__file__).resolve().parent;R=L.parents[1]
def read(name):return json.loads((L/name).read_text())
def catalog(name):return read(name+'-all-catalog.json')
def identical(a,b,keys):
    for key in keys:assert a[key]==b[key],key
baseline=catalog('original-before-scan-fix');started=catalog('candidate-after-start')
identical(baseline,started,['tables','opaque_table_digests','setting_key_sha256'])
assert len(baseline['tables'])+len(baseline['opaque_table_digests'])==37
before=catalog('before-first-fixed-scan');after=catalog('after-first-fixed-scan')
protected=[k for k in before['tables'] if k not in ['directories','observations','pack_file_steps','pack_pages','packs','roots','tasks']]
assert len(protected)==28 and all(before['tables'][k]==after['tables'][k] for k in protected)
assert before['opaque_table_digests']['access_tokens']==after['opaque_table_digests']['access_tokens']
assert set(before['setting_key_sha256'])==set(after['setting_key_sha256'])
assert all(v==after['setting_key_sha256'][k] for k,v in before['setting_key_sha256'].items() if k not in ['pack_root_scan_v1:purge','root_scan_progress_v1:purge'])
scan=read('original-scan-state.json');assert scan['phase']=='fixed_scans_and_reading_verified'
assert scan['first_terminal_task_with_stability_wait']['result']['roots'][0]['status']=='deferred'
assert scan['scan_task']['result']['packs']['deferred']==0
assert scan['scan_task']['result']['packs']['failure_reasons']=={'pack_empty':8}
assert len(scan['image_responses'])==6 and all(r['status']==200 for r in scan['image_responses'])
identical(catalog('before-post-scan-image-reads'),catalog('after-post-scan-image-reads'),['tables','opaque_table_digests','setting_key_sha256'])
original='1958716a-589a-4942-8a00-0a812b165e28';duplicate='62d5fe84-0cc6-434b-b391-75da4740f722';tall='b7212acf-a7f2-4a9a-8127-b85d120d4868'
oldpacks={p['id']:p for p in before['tables']['packs']};newpacks={p['id']:p for p in after['tables']['packs']}
assert oldpacks[original]['status']=='missing' and oldpacks[duplicate]['status']=='available'
assert newpacks[original]['status']==newpacks[tall]['status']=='available' and duplicate not in newpacks
assert len(oldpacks)==25 and len(newpacks)==24
assert len(before['tables']['pack_pages'])==48 and len(after['tables']['pack_pages'])==43
files=read('original-before-scan-fix-files.json');assert media.files()==files and len(files)==49
native=[json.loads(x) for x in (L/'requests.jsonl').read_text().splitlines()]
prep=[json.loads(x) for x in (L/'preparation-requests.jsonl').read_text().splitlines()]
assert len([r for r in prep if r['method']=='POST' and r['path']=='/api/v1/scans'])==2
posts=[r for r in native if r['method']=='POST' and r['path']=='/api/v1/scans']
assert len(posts)==1 and posts[0]['command']=={'root_id':'purge'} and posts[0]['status']==202
ns=read('native-scan-state.json');assert ns['phase']=='native_scoped_scan_verified'
assert ns['task']['result']['scope']=={'all':False,'root_ids':['purge']}
na,nb=catalog('before-native-directory-scan'),catalog('after-native-directory-scan')
strip=lambda rows:{r['id']:{k:v for k,v in r.items() if k!='seen_scan'} for r in rows}
assert strip(na['tables']['pack_pages'])==strip(nb['tables']['pack_pages'])
assert all(na['tables'][k]==nb['tables'][k] for k in protected)
nr=read('native-read-state.json');assert nr['phase']=='native_cold_read_verified'
assert nr['old_app_pid']!=nr['new_app_pid'] and nr['old_pid_absent'] and nr['same_android_boot_no_emulator_reboot']
for key in ['first_progress','cold_progress','after_back_progress']:
    assert nr[key]['offset_ratio']==.45 and nr[key]['page_id']==nr['page_id']
assert nr['recent_total']==3
sources=[r['command'] for r in native if r['method']=='POST' and r['path']=='/api/v1/pack-sessions' and r['command'].get('anchor_pack_id')==tall]
assert [r['source'] for r in sources]==['tags','recent'] and sources[0]['scope']['tag_ids'] and not sources[1]['scope']['tag_ids']
assert len([r for r in native if r['path']=='/api/v1/pages/'+nr['page_id']+'/image' and r['status']==200])>=2
assert any(r['path']=='/api/v1/pages/e461e7c1-6de6-4765-bf7f-ddb9ccdcf54f/image' and r['status']==200 for r in native)
guard=read('old-purge-after-scan.json');assert guard['task']['error']=='stale_pack_state' and guard['task']['result']['pages_deleted']==2
retries=[r for r in native if r['method']=='POST' and r['path']=='/api/v1/pack-operations/'+guard['task_id']+'/retry'];assert len(retries)==1
assert not [r for r in native if r['method']=='POST' and r['path'].startswith(('/api/v1/pack-trash/permanent','/api/v1/pack-restore'))]
ga,gb=catalog('before-old-purge-after-scan'),catalog('after-old-purge-after-scan')
assert all(ga['tables'][k]==gb['tables'][k] for k in ga['tables'] if k not in ['tasks','request_records'])
identical(ga,gb,['opaque_table_digests','setting_key_sha256'])
assert all(t['status'] not in ['queued','running'] for t in gb['tables']['tasks'])
runtime=read('runtime-source.json');assert len(runtime['files'])==79 and runtime['other_76_files_unchanged']
for path,digest in runtime['files'].items():assert hashlib.sha256(subprocess.check_output(['git','show',runtime['source']+':services/server/'+path])).hexdigest()==digest
build=read('build-result.json');archive=R/'tmp/releases'/build['archive']['name'];assert hashlib.sha256(archive.read_bytes()).hexdigest()==build['archive']['sha256']
assert subprocess.check_output(['git','diff','8416a3f7359af94f1da802185b136770d6499986','--','apps/mobile'])==b''
assert hashlib.sha256((R/'tmp/releases/video-viewer-0.2.0-preview.20-arm64.apk').read_bytes()).hexdigest()==read('installation.json')['apk_sha256']
assert '524 passed' in (L/'full-server.log').read_text() and 'FAILED ' not in (L/'full-server.log').read_text()
assert '15 passed' in (L/'scan-final-15.log').read_text() and '53 passed' in (L/'scan-after-fix-targeted.log').read_text()
assert '7 failed, 6 passed' in (L/'scan-before-fix.log').read_text()
assert 'All checks passed' in (L/'ruff-final.log').read_text() and '149 files already formatted' in (L/'format-final.log').read_text()
screens=sorted(p for p in (L/'screens').glob('*.png') if 2<=int(p.name[:2])<=13)
assert len(screens)==12 and all(struct.unpack('!II',p.read_bytes()[16:24])==(1080,2400) for p in screens)
result={'source':runtime['source'],'runtime_files_matched':79,'old_identity_recovered':original,'unmanaged_duplicate_retired':duplicate,'tall_id_preserved':tall,'same_page_offset_ratio':.45,'actual_app_pid_pair':[nr['old_app_pid'],nr['new_app_pid']],'same_android_boot':True,'preparation_scan_posts':2,'first_scan_terminal_deferred_then_explicit_followup':True,'native_scan_posts':1,'native_scope':{'all':False,'root_ids':['purge']},'native_old_task_retry_posts':1,'old_task_after_scan':'stale_pack_state, 2/3 unchanged','native_new_permanent_restore_posts':0,'recent_total_recovered':3,'initial_and_final_files':49,'all_source_file_bytes_unchanged':True,'scan_protected_tables':protected,'read_all_37_tables_settings_unchanged':True,'full_server_passed':524,'fixed_new_cases_passed':15,'intermediate_targeted_passed':53,'old_product_red_cases':'7 failed / 6 passed','client_unchanged_code26':True,'screens_reviewed_by_primary':12,'private_backup_retained':True,'nas_accessed':False}
(L/'verified-phase.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
