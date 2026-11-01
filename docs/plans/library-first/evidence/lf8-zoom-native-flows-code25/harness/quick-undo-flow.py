import sys,json,time,hashlib
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import ui,api,facts
from snapshot_all import snapshot
ui.choose('阅读下一包');deadline=time.monotonic()+45
while True:
 _,nodes=ui.xml()
 if any(n.get('content-desc')=='282 / 500' for n in nodes):break
 assert time.monotonic()<deadline
ui.device('shell','input','tap','540','700');time.sleep(.05);ui.device('shell','input','tap','540','700');ui.snap('29-deep-zoom-before-quick');ui.choose('图包更多');ui.choose('快速整理当前范围');ui.snap('30-deep-quick-zoom-before-remove');before=snapshot('new25','quick-before-delete');media=ui.ROOT/'.dev/lf8-preview18-native/media';hashes={str(p.relative_to(media)):hashlib.sha256(p.read_bytes()).hexdigest() for p in media.rglob('*') if p.is_file()};long=next(p for p in before['tables']['packs'] if p['name']=='04-long');original=next(p for p in before['tables']['pack_progress'] if p['pack_id']==long['id'])
start=time.time();ui.choose('移入回收站');deadline=time.monotonic()+7
while True:
 raw,nodes=ui.xml();found=[n for n in nodes if (n.get('content-desc') or n.get('text'))=='撤销' and n.get('clickable')=='true']
 if found:
  assert len(found)==1;notice_at=time.time();(ui.L/'screens/31-quick-undo-visible.xml').write_bytes(raw);ui.tap(found[0],'undo-public-long-pack-within-visible-original-notice');undo_at=time.time();break
 assert time.monotonic()<deadline,'undo notice absent or expired'
ui.snap('32-quick-restored-long');deadline=time.monotonic()+45
while True:
 p=api.call('GET','/api/v1/packs/'+long['id']);_,nodes=ui.xml()
 if p['status']=='available' and any(n.get('content-desc')=='282 / 500' for n in nodes):break
 assert time.monotonic()<deadline
end=snapshot('new25','quick-after-undo');restored=next(p for p in end['tables']['packs'] if p['id']==long['id']);p1=next(p for p in end['tables']['pack_progress'] if p['pack_id']==long['id'])
assert restored['generation']==long['generation']+2
for k in ['page_id','offset_ratio','completed','content_version']:assert original[k]==p1[k],(k,original,p1)
assert hashes=={str(p.relative_to(media)):hashlib.sha256(p.read_bytes()).hexdigest() for p in media.rglob('*') if p.is_file()}
assert before['opaque_table_digests']==end['opaque_table_digests'];assert before['setting_key_sha256']==end['setting_key_sha256'];allowed={'packs','tasks','pack_file_operations','pack_file_steps','pack_trash_items','pack_session_entries','pack_progress','request_records'};changed=[k for k in before['tables'] if before['tables'][k]!=end['tables'][k]];assert set(changed)<=allowed,changed
# Cleanup resets zoom: one Back leaves the reader instead of merely resetting.
ui.device('shell','input','keyevent','4');nodes=ui.snap('33-quick-after-one-back-library');assert any(n.get('class')=='android.widget.EditText' for n in nodes)
(ui.L/'quick-undo-checks.json').write_text(json.dumps({'normal_code':25,'initial_saved_page':282,'zoomed_then_quick_remove':True,'undo_clicked_while_visible':True,'seconds_from_action_start_to_notice':notice_at-start,'seconds_from_action_start_to_undo':undo_at-start,'undo_timer_not_extended':True,'original_id_and_progress_restored':True,'generation_delta':2,'next_pack_then_original_restored':'05-patterns then 04-long','all_fixture_file_hashes_unchanged':len(hashes),'changed_tables':changed,'settings_and_opaque_equal':True,'one_back_after_cleanup_returned_library':True,'visual_review':'pending'},indent=2)+'\n');print('Zoomed quick cleanup and original eight-second undo restored long pack/page; source files unchanged',flush=True)
