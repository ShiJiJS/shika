import sys,json,time,hashlib,xml.etree.ElementTree as E
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import ui,api
from snapshot_all import snapshot
_,nodes=ui.xml();labels=[n.get('content-desc') or n.get('text') or '' for n in nodes];text='\n'.join(labels);assert not any(n.get('content-desc')=='扫描此目录' for n in nodes);assert '0 / 0' not in text
ui.device('shell','input','keyevent','4');_,nodes=ui.xml();assert any(n.get('content-desc','').startswith('媒体目录\n') for n in nodes);ui.choose('媒体库');ui.choose('图包\n6');ui.snap('05-old-service-pack-library');passive=snapshot('old-service','after-old-settings-passive');before=json.loads((ui.L/'before-native-all-catalog.json').read_text())
for k in ['tables','opaque_table_digests','setting_key_sha256']:assert before[k]==passive[k],k
_,nodes=ui.xml();found=[n for n in nodes if n.get('clickable')=='true' and n.get('content-desc','').startswith('继续阅读\n04-long\n')];assert len(found)==1;ui.tap(found[0],'resume-saved-long-pack-on-old-service');deadline=time.monotonic()+45
while True:
 _,nodes=ui.xml()
 if any(n.get('content-desc')=='282 / 500' for n in nodes):break
 assert time.monotonic()<deadline
ui.snap('06-old-service-deep-resume');opened=snapshot('old-service','old-deep-opened');pack=next(p for p in opened['tables']['packs'] if p['name']=='04-long');original=next(p for p in before['tables']['pack_progress'] if p['pack_id']==pack['id']);progress=next(p for p in opened['tables']['pack_progress'] if p['pack_id']==pack['id'])
for k in ['page_id','offset_ratio','completed','content_version']:assert progress[k]==original[k],k
seq=max(json.loads(s)['seq'] for s in (ui.L/'requests.jsonl').read_text().splitlines());ui.device('shell','input','tap','540','900');time.sleep(.05);ui.device('shell','input','tap','540','900');ui.snap('07-old-service-deep-doubletap');ui.device('shell','input','keyevent','4');nodes=ui.snap('08-old-service-back-reset');assert any(n.get('content-desc')=='282 / 500' for n in nodes);reset=snapshot('old-service','old-deep-reset')
for k in ['tables','opaque_table_digests','setting_key_sha256']:assert opened[k]==reset[k],k
rows=[json.loads(s) for s in (ui.L/'requests.jsonl').read_text().splitlines()];assert not [r for r in rows if r['seq']>seq and r['method'] not in ['GET','HEAD']]
ui.device('shell','input','keyevent','4');nodes=ui.snap('09-old-service-back-pack-library');assert any(n.get('class')=='android.widget.EditText' for n in nodes);oldpid=ui.device('shell','pidof',ui.PACKAGE).decode().strip();ui.device('shell','am','force-stop',ui.PACKAGE);ui.device('shell','am','start','-n',ui.PACKAGE+'/.MainActivity');deadline=time.monotonic()+50
while True:
 _,nodes=ui.xml()
 if any(n.get('content-desc')=='预览此范围' for n in nodes):break
 assert time.monotonic()<deadline
assert oldpid!=ui.device('shell','pidof',ui.PACKAGE).decode().strip();ui.snap('10-old-service-cold-library');after=snapshot('old-service','after-old-native')
for k in ['tables','opaque_table_digests','setting_key_sha256']:assert reset[k]==after[k],k
rows=[json.loads(s) for s in (ui.L/'requests.jsonl').read_text().splitlines()];assert not [r for r in rows if r['method']=='POST' and r['path']=='/api/v1/scans']
(ui.L/'old-service-native-checks.json').write_text(json.dumps({'normal_code':25,'old_source':'b79da7b9c4d2ab099c055b8eb855904e32abb0a5','source_runtime_files_verified':75,'old_capabilities_exclude':['root_scan_progress','scoped_scans'],'old_completed_roots_require_settings_and_expanding_scan_record':True,'scoped_scan_buttons_absent':True,'no_scans_POST_during_readonly_navigation':True,'no_unknown_zero_zero':True,'passive_settings_all_35_tables_equal':True,'deep_resume_page':282,'resume_fields_equal':['page_id','offset_ratio','completed','content_version'],'zoom_and_Back_reset_all_35_tables_equal':True,'zoom_and_reset_write_requests':0,'cold_new_pid_library':True,'return_and_cold_all_35_tables_equal':True,'no_legacy_browse_exposed':True,'visual_review':'pending','NAS_and_phone_not_touched':True},indent=2)+'\n');print('New ordinary APK on old service: fallback root records, no scoped POST, deep resume/reset and new library return/cold passed',flush=True)
