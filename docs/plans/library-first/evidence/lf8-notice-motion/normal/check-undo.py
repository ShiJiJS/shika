import hashlib,json,time
from pathlib import Path
import driver,snapshot
R=Path('/Users/jiangxinyi/Documents/Project/video-viewer')
media=R/'.dev/lf8-preview-package/upgrade/packs'
source={str(p.relative_to(media)):hashlib.sha256(p.read_bytes()).hexdigest() for p in media.rglob('*') if p.is_file()}
before=snapshot.snapshot('before-real-undo')
nodes=driver.capture('release12-confirm-ready')
confirm=[n for n in nodes if n.get('content-desc')=='移入回收站' and n.get('clickable')=='true']
assert len(confirm)==1
offset=driver.trace_count();start=time.monotonic();driver.tap(confirm[0],'confirm disposable whole-pack trash')
nodes=driver.capture('release12-undo-visible');driver.show(nodes)
undo=[n for n in nodes if n.get('content-desc')=='撤销' and n.get('clickable')=='true']
assert len(undo)==1,'Actual undo action absent; do not resubmit'
seen=time.monotonic()-start;driver.tap(undo[0],'actual undo within observed prompt');tapped=time.monotonic()-start
end=time.monotonic()+25
while True:
 nodes=driver.capture('release12-undo-result');s=driver.text(nodes)
 if 'Upgrade Pack' in s and '图包操作 Upgrade Pack' in s:break
 assert time.monotonic()<end,s
 time.sleep(.25)
after=snapshot.snapshot('after-real-undo')
assert before['tables']['packs']==after['tables']['packs']
for name in ['pack_pages','pack_tag_definitions','pack_tag_links','pack_progress','pack_preferences']:
 assert before['tables'][name]==after['tables'][name],name
ops=[v for v in after['tables']['file_operations'] if v not in before['tables']['file_operations']]
assert len(ops)==2,ops
assert source=={str(p.relative_to(media)):hashlib.sha256(p.read_bytes()).hexdigest() for p in media.rglob('*') if p.is_file()}
driver.save('actual-undo-result.json',{'complete':True,'ordinary_release_code':12,'disposable_pack':'Upgrade Pack','real_ui_action_count':2,'new_file_operations':ops,'prompt_observed_seconds':seen,'undo_tapped_seconds':tapped,'source_files_equal':source,'pack_pages_tags_progress_preferences_equal':True,'trace_start_offset':offset,'trace_end_offset':driver.trace_count(),'no_server_api_shortcut_or_automatic_command_retry':True})
driver.show(nodes)
