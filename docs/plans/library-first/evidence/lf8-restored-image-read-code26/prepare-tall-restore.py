"""Create only a new synthetic pack; seed reading metadata via a separate API log."""
import json,subprocess,time
from pathlib import Path
import api,media
from snapshot_all import snapshot
L=Path(__file__).resolve().parent;name='Restore-read-tall';root=L/'media'/name
assert (L/'original-native-open.json').exists() and not root.exists()
before=media.save('before-tall-inputs');runtime=json.loads((L/'runtime.json').read_text())
code="""from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
p=Path('/media/Restore-read-tall');p.mkdir()
font=ImageFont.load_default(size=32)
for page in range(1,4):
 image=Image.new('RGB',(600,3000),'white');draw=ImageDraw.Draw(image)
 for row in range(30):
  y=row*100;draw.rectangle((0,y,599,y+99),fill=(228-row%2*16,236-page*5,245-row%3*10));draw.line((0,y,599,y),fill=(40,65,90),width=3)
  draw.text((24,y+28),'SYNTHETIC %02d / ROW %02d'%(page,row),font=font,fill=(15,35,60))
 image.save(p/('%02d.png'%page));image.close()
(p/'notes.txt').write_text('Retain attachment in this generated pack.\\n');(p/'extras').mkdir();(p/'extras/data.bin').write_bytes(b'Synthetic non-image attachment\\0')
"""
subprocess.run(['docker','exec',runtime['id'],'python','-c',code],check=True,capture_output=True)
after=media.save('after-tall-inputs');assert len(after)-len(before)==5 and all(after[k]==v for k,v in before.items())
for scan in range(2):
    result=api.wait(api.call('POST','/api/v1/scans')['id']);assert result['status']=='completed'
    if scan==0:time.sleep(2.1)
pack=next(p for p in api.all_pages('/api/v1/packs') if p['name']==name);pages=api.call('GET','/api/v1/packs/'+pack['id']+'/pages')['items'];assert len(pages)==3 and all(p['width']==600 and p['height']==3000 for p in pages)
tag=json.loads((L.parent/'lf8-pack-purge-native26/fixture-setup.json').read_text())['tag']
api.call('PATCH','/api/v1/pack-tag-links',{'request_id':'read-tall-tag','pack_ids':[pack['id']],'tag_ids':[tag['id']],'mode':'add'})
session=api.call('POST','/api/v1/pack-sessions',{'request_id':'read-tall-session','scope':{'search':name},'source':'library','sort':'name','order':'sequential','anchor_pack_id':pack['id']})
opened=api.call('POST','/api/v1/pack-sessions/'+session['id']+'/opened',{'request_id':'read-tall-open','pack_id':pack['id'],'page_id':pages[-1]['id'],'content_version':pack['content_version'],'expected_session_revision':session['revision'],'expected_revision':0})
progress=api.call('PATCH','/api/v1/packs/'+pack['id']+'/progress',{'request_id':'read-tall-progress','session_id':session['id'],'page_id':pages[-1]['id'],'content_version':pack['content_version'],'expected_session_revision':opened['session_revision'],'expected_revision':opened['revision'],'offset_ratio':0.45,'completed':False})
trashed=api.wait(api.call('POST','/api/v1/packs/trash',{'request_id':'read-tall-trash','pack_ids':[pack['id']]})['id']);assert trashed['result']['succeeded']==1
trash=next(t for t in api.all_pages('/api/v1/pack-trash') if t['pack']['id']==pack['id'])
snapshot('normal26','tall-seeded-trash')
(L/'tall-preparation.json').write_text(json.dumps({'name':name,'pack':pack,'pages':pages,'trash':trash,'progress':progress,'seeded_via_preparation_api_not_native_reading':True,'images':3,'image_size':[600,3000],'non_image_attachments':2,'earlier_46_files_unchanged':True,'new_files':{k:v for k,v in after.items() if k not in before}},indent=2))
print({'new_synthetic_pack':name,'images':3,'original_page':'03.png','seeded_offset_ratio':0.45,'initial_files':5},flush=True)
