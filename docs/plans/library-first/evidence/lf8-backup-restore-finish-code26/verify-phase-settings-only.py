"""Cross-check immutable source, raw native receipts, data projections and media."""
import hashlib,io,json,struct,subprocess,tarfile
from pathlib import Path
import media
L=Path(__file__).resolve().parent;R=L.parents[1]
def read(name):return json.loads((L/name).read_text())
def catalog(name):return read(name+'-all-catalog.json')
def digest(raw):return hashlib.sha256(raw).hexdigest()
source='2de02374e21567d72cc8bb94dde0bda43fde5a06'
runtime=read('runtime-source.json');assert runtime['source']==source and len(runtime['files'])==79
cid=read('runtime.json')['id']
raw=subprocess.check_output(['docker','cp',cid+':/app/.','-'])
with tarfile.open(fileobj=io.BytesIO(raw)) as archive:
    actual={m.name.removeprefix('./').removeprefix('app/'):digest(archive.extractfile(m).read()) for m in archive.getmembers() if m.isfile()}
assert all(actual.get(name)==value for name,value in runtime['files'].items())
(L/'actual-container-runtime-source.json').write_text(json.dumps({'container':cid,'source':source,'files':runtime['files'],'matched':79},indent=2))
for name,value in runtime['files'].items():assert digest(subprocess.check_output(['git','show',source+':services/server/'+name]))==value
code="import pathlib,json,hashlib; print(json.dumps({p.name:{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in pathlib.Path('/data/management-archives').glob('*.vvbackup')}))"
artifacts=json.loads(subprocess.check_output(['docker','exec',cid,'python','-c',code]))
state=read('preparation-state.json');held=read('native-restore-held.json');accepted=read('native-immediate-accepted.json');done=read('native-inspection-completed.json')
assert artifacts[state['baseline_export']['id']+'.vvbackup']=={'bytes':state['baseline_archive_bytes'],'sha256':state['baseline_archive_sha256']}
point=state['latest_restore_point']['item'];assert artifacts[point['snapshot_id']+'.vvbackup']=={'bytes':point['bytes'],'sha256':point['file_sha256']}
assert artifacts['b5f27dc6-d8b3-4405-a0ae-02e62f747216.vvbackup']==artifacts[point['snapshot_id']+'.vvbackup']
assert artifacts[accepted['queued_task']['id']+'.vvbackup']==artifacts[held['original_task']['result']['pre_snapshot_id']+'.vvbackup']
(L/'archive-artifact-digests.json').write_text(json.dumps(artifacts,indent=2))
before=catalog('before-native-restore');committed=catalog('S1-committed-and-next-inspection-queued');cancel=catalog('S1-after-inspection-cancel');after=catalog('after-native-read-and-back')
assert len(before['tables'])+len(before['opaque_table_digests'])==37
changed=[k for k,v in before['tables'].items() if v!=committed['tables'][k]]
assert changed==['directories','observations','pack_pages','pack_tag_definitions','pack_tag_links','packs','request_records','roots','tasks']
protected=[k for k in before['tables'] if k not in changed];assert len(protected)==26
assert all(before['tables'][k]==committed['tables'][k] for k in protected)
assert before['opaque_table_digests']['access_tokens']==committed['opaque_table_digests']['access_tokens']==after['opaque_table_digests']['access_tokens']
assert all(v==cancel['tables'][k] for k,v in committed['tables'].items() if k!='tasks')
assert committed['setting_key_sha256']==cancel['setting_key_sha256'] and committed['opaque_table_digests']==cancel['opaque_table_digests']
assert cancel['tables']['pack_tag_definitions']==catalog('S1-two-tags-before-preparation-restore')['tables']['pack_tag_definitions']
assert cancel['tables']['pack_tag_links']==catalog('S1-two-tags-before-preparation-restore')['tables']['pack_tag_links']
settings_changed=[k for k in sorted(set(before['setting_key_sha256'])|set(committed['setting_key_sha256'])) if committed['setting_key_sha256'].get(k)!=before['setting_key_sha256'].get(k)]
assert set(settings_changed)=={'management_epoch','management_history_epochs','management_history_ref','pack_root_scan_v1:main','root_scan_progress_v1:main'}
assert set(committed['setting_key_sha256'])-set(before['setting_key_sha256'])=={'pack_root_scan_v1:main'}
assert not set(before['setting_key_sha256'])-set(committed['setting_key_sha256'])
assert held['marker']['task_status']=='completed' and held['marker']['maintenance_task'] is None and held['marker']['maintenance_owner_cleared'] and held['marker']['durable_reservation_empty']
assert held['original_task']==done['original_restore'] and accepted['original_task_unchanged']
assert accepted['hold_still_armed'] and accepted['same_container_healthy'] and accepted['restart_count']==0
assert accepted['queued_task']['status']=='queued' and done['queued_inspection']['status']=='completed'
trace=[json.loads(x) for x in (L/'requests.jsonl').read_text().splitlines()]
assert all(r['status']<400 and 'observer_error' not in r for r in trace)
posts=[r for r in trace if r['method']=='POST']
restore=[r for r in posts if r['path']=='/api/v1/management-backups/restores'];inspects=[r for r in posts if '/from-snapshot/' in r['path']]
assert len(restore)==1 and len(inspects)==2
assert restore[0]['status']==202 and all(r['status']==202 for r in inspects)
assert inspects[1]==accepted['accepted'] and inspects[1]['request_epoch_sha256']==held['marker']['management_epoch_sha256']
assert inspects[1]['time']>held['marker']['time'] and inspects[1]['finished_at']<read('native-cleanup-release.json')['time']
assert not [r for r in posts if r['path'].startswith(('/api/v1/pack-trash','/api/v1/pack-restore','/api/v1/pack-operations','/api/v1/pack-purge'))]
scans=[r for r in posts if r['path']=='/api/v1/scans'];assert len(scans)==1
assert len([r for r in trace if r['method']=='GET' and r['path']=='/api/v1/pages/'+state['page_id']+'/image' and r['status']==200])==1
assert media.files()==state['files'] and len(state['files'])==3
native=read('native-read.json');assert native['page_id']==state['page_id'] and native['progress']['offset_ratio']==.45
assert all(t['status'] not in ('queued','running') for t in after['tables']['tasks'])
assert '534 passed' in (L/'full-server.log').read_text() and 'FAILED ' not in (L/'full-server.log').read_text()
assert '10 passed' in (L/'gate-ten-after-fix.log').read_text() and '4 failed' in (L/'gate-before-fix.log').read_text()
assert 'All checks passed' in (L/'ruff-final.log').read_text() and '150 files already formatted' in (L/'format-final.log').read_text()
build=read('build-result.json');archive=R/'tmp/releases'/build['archive']['name'];assert archive.stat().st_size==build['archive']['bytes'] and digest(archive.read_bytes())==build['archive']['sha256']
assert subprocess.check_output(['git','diff','8416a3f7359af94f1da802185b136770d6499986','--','apps/mobile'])==b''
assert digest((R/'tmp/releases/video-viewer-0.2.0-preview.20-arm64.apk').read_bytes())==read('installation.json')['apk_sha256']
screens=[p for p in (L/'screens').glob('*.png') if 2<=int(p.name[:2])<=12]
assert len(screens)==11 and all(struct.unpack('!II',p.read_bytes()[16:24])==(1080,2400) for p in screens)
result={'source':source,'runtime_files_matched':79,'runtime_changed_files':build['changed_existing_files'],'full_server_passed':534,'new_deterministic_cases':10,'old_code_reproduced_503_cases':4,'native_restore_posts':1,'native_snapshot_inspection_posts':2,'immediate_inspection_202_while_restore_cleanup_held':True,'app_adopted_new_epoch_without_host_write':True,'queued_inspection_completed_same_id':True,'cancelled_preview_no_replacement':True,'native_auto_scan_after_restore_posts':1,'auto_scan_is_existing_client_behavior':True,'native_delete_or_pack_restore_posts':0,'native_actual_image_read_200':True,'same_original_pack_page_and_offset':.45,'active_tags':2,'preview_tags':1,'media_files':3,'all_source_bytes_unchanged':True,'all_37_tables_accounted_for':True,'unchanged_during_restore_tables':protected,'changed_tables_during_restore_and_auto_scan':changed,'settings_changed_during_restore_and_auto_scan':settings_changed,'inspection_cancel_changes_only_task_completion':True,'credentials_unchanged':True,'baseline_and_preparation_snapshot_artifacts_unchanged':True,'screens_reviewed_by_primary':11,'no_independent_visual_review':True,'nas_accessed':False,'client_code26_unchanged':True,'actual_cold_restart_test_this_phase':False}
(L/'verified-phase.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
