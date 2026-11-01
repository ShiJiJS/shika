"""Build S0/S1 using only own generated media and public management APIs."""
import hashlib,json,subprocess,urllib.request
from pathlib import Path
import api,media
from snapshot_all import snapshot
L=Path(__file__).resolve().parent
assert not (L/'preparation-state.json').exists()
runtime=json.loads((L/'runtime.json').read_text())
fresh=not (L/'generated-native-inputs-files.json').exists()
if fresh:api.call('PUT','/api/v1/roots/main',{'name':'Synthetic backup only','path':'/media','kind':'pack','enabled':True})
code="""from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
p=Path('/media/Gate-pack');p.mkdir();font=ImageFont.load_default(size=32)
for page in range(1,4):
 im=Image.new('RGB',(600,3000),'white');draw=ImageDraw.Draw(im)
 for row in range(30):
  y=row*100;draw.rectangle((0,y,599,y+99),fill=(228-row%2*16,236-page*5,245-row%3*10));draw.line((0,y,599,y),fill=(40,65,90),width=3);draw.text((24,y+28),'SYNTHETIC %02d / ROW %02d'%(page,row),font=font,fill=(15,35,60))
 im.save(p/('%02d.png'%page));im.close()
"""
if fresh:subprocess.run(['docker','exec',runtime['id'],'python','-c',code],check=True,capture_output=True);files=media.save('generated-native-inputs')
else:files=json.loads((L/'generated-native-inputs-files.json').read_text())
assert len(files)==3 and media.files()==files
scans=[t for t in api.call('GET','/api/v1/tasks?limit=100')['items'] if t['kind']=='scan']
assert len(scans)==1 and scans[0]['status']=='completed' and scans[0]['result']['packs']['deferred']==1
(L/'first-terminal-stability-wait.json').write_text(json.dumps(scans[0],indent=2))
submitted=api.call('POST','/api/v1/scans',{'root_id':'main'});(L/'explicit-stable-followup-scan.json').write_text(json.dumps(submitted,indent=2))
task=api.wait(submitted['id']);assert task['status']=='completed' and task['result']['packs']['deferred']==0
pack=api.call('GET','/api/v1/packs')['items'][0];pages=api.call('GET','/api/v1/packs/'+pack['id']+'/pages')['items'];assert len(pages)==3
tag0=api.call('POST','/api/v1/pack-tags',{'request_id':'baseline-tag','name':'Before backup'})
api.call('PATCH','/api/v1/pack-tag-links',{'request_id':'baseline-link','pack_ids':[pack['id']],'tag_ids':[tag0['id']],'mode':'add'})
reading=api.call('POST','/api/v1/pack-sessions',{'request_id':'baseline-reading','anchor_pack_id':pack['id'],'source':'library','sort':'name','order':'sequential'})
opened=api.call('POST','/api/v1/pack-sessions/'+reading['id']+'/opened',{'request_id':'baseline-open','pack_id':pack['id'],'page_id':pages[-1]['id'],'content_version':pack['content_version'],'expected_session_revision':reading['revision'],'expected_revision':0})
api.call('PATCH','/api/v1/packs/'+pack['id']+'/progress',{'request_id':'baseline-progress','session_id':reading['id'],'page_id':pages[-1]['id'],'content_version':pack['content_version'],'expected_session_revision':opened['session_revision'],'expected_revision':opened['revision'],'offset_ratio':.45,'completed':False})
baseline=snapshot('preparation-api','S0-one-tag-before-export')
exported=api.wait(api.call('POST','/api/v1/management-backups',{'request_id':'baseline-export'})['id']);assert exported['status']=='completed'
auth=json.loads(api.TOKEN.read_text());headers={'Authorization':'Bearer '+auth['access_token'],'X-Management-Epoch':auth['management_epoch']}
with urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:8788/api/v1/management-backups/'+exported['id']+'/download',headers=headers),timeout=30) as response:raw=response.read()
assert hashlib.sha256(raw).hexdigest()==exported['result']['file_sha256']
assert auth['access_token'].encode() not in raw and (L/'config/passphrase').read_bytes().strip() not in raw
(L/'baseline-private.vvbackup').write_bytes(raw);(L/'baseline-private.vvbackup').chmod(0o600)
request=urllib.request.Request('http://127.0.0.1:8788/api/v1/management-backups/imports',data=raw,headers={**headers,'Content-Type':'application/x-ndjson','Idempotency-Key':'baseline-import'},method='POST')
with urllib.request.urlopen(request,timeout=30) as response:accepted=json.load(response)
with (L/'preparation-requests.jsonl').open('a') as log:log.write(json.dumps({'method':'POST','path':'/api/v1/management-backups/imports','status':202,'body_bytes':len(raw),'idempotency_key':'baseline-import'})+'\n')
preview=api.wait(accepted['id']);assert preview['status']=='completed'
tag1=api.call('POST','/api/v1/pack-tags',{'request_id':'snapshot-tag','name':'Saved in restore point'})
api.call('PATCH','/api/v1/pack-tag-links',{'request_id':'snapshot-link','pack_ids':[pack['id']],'tag_ids':[tag1['id']],'mode':'add'})
snapshot('preparation-api','S1-two-tags-before-preparation-restore')
restore=api.call('POST','/api/v1/management-backups/restores',{'request_id':'preparation-restore','preview_id':preview['id'],'root_mapping':{'main':'/media'},'confirmed':True})
state={'phase':'preparation_restore_submitted','preparation_restore_id':restore['id'],'baseline_export':exported,'baseline_preview':preview,'pack_id':pack['id'],'page_id':pages[-1]['id'],'S0_tag':tag0,'S1_added_tag':tag1,'progress_seeded_via_preparation_api':True,'files':files}
(L/'preparation-state.json').write_text(json.dumps(state,indent=2))
result=api.wait(restore['id']);assert result['status']=='completed'
info=api.call('GET','/api/v1/info');auth['management_epoch']=info['management_epoch'];api.TOKEN.write_text(json.dumps(auth))
current=api.call('GET','/api/v1/packs/'+pack['id']);assert current['tag_ids']==[tag0['id']] and current['progress']['page_id']==pages[-1]['id'] and current['progress']['offset_ratio']==.45
assert media.files()==files
snapshot('preparation-api','S0-active-native-entry')
state.update(phase='native_ready_S0_with_S1_restore_point',preparation_restore=result,current_pack=current,latest_restore_point=api.call('GET','/api/v1/management-backups/latest-restore'),baseline_archive_bytes=len(raw),baseline_archive_sha256=hashlib.sha256(raw).hexdigest(),default_stability_seconds=2,only_one_preparation_restore=True)
(L/'preparation-state.json').write_text(json.dumps(state,indent=2));print({'pack':pack['id'],'page':pages[-1]['id'],'initial_active_tags':1,'restore_point_tags':2,'offset':.45,'media_files':3,'preparation_restore':result['id']},flush=True)
