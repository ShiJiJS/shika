import hashlib,json,urllib.request
import api,media,ui
from snapshot_all import snapshot
L=ui.L;state=json.loads((L/'tall-native-state.json').read_text());assert state['phase']=='native_read_and_cold_resume_completed'
pack=next(p for p in api.all_pages('/api/v1/packs') if p['id']==state['pack_id']);page=api.call('GET','/api/v1/packs/'+pack['id']+'/pages')['items'][0];assert page['id']==state['page_id'] and pack['content_version']==3
auth=json.loads(api.TOKEN.read_text());headers={'Authorization':'Bearer '+auth['access_token'],'X-Management-Epoch':auth['management_epoch']};before=snapshot('normal26','tall-before-readonly-200');files=media.save('tall-before-readonly-200');results=[]
for kind,path in [('cover',pack['cover_url']),('image',page['image_url']),('thumbnail',page['thumbnail_url'])]:
    with urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:8788'+path,headers=headers),timeout=20) as response:
        data=response.read();assert response.status==200
        digest=hashlib.sha256(data).hexdigest()
        if kind=='image':assert digest==state['explicit_fixture_ctime_only_update']['sha256']
        results.append({'kind':kind,'status':response.status,'bytes':len(data),'sha256':digest})
after=snapshot('normal26','tall-after-readonly-200')
for key in ['tables','opaque_table_digests','setting_key_sha256']:assert before[key]==after[key],key
assert media.files()==files
initial=json.loads((L/'before-tall-inputs-files.json').read_text());assert len(initial)==46 and all(files[k]==v for k,v in initial.items())
seed=json.loads((L/'tall-preparation.json').read_text());all_inputs={**initial,**seed['new_files']};assert len(all_inputs)==51
media.compare_deleted(all_inputs,files,['Restore-read-tall/01.png','Restore-read-tall/02.png']);assert len(files)==49
(L/'tall-readonly-200.json').write_text(json.dumps({'pack_id':pack['id'],'same_page_id':page['id'],'responses':results,'all_37_tables_and_settings_equal_during_reads':True,'all_49_remaining_files_byte_identical':True,'initial_46_files_preserved':True,'only_two_explicitly_confirmed_tall_images_deleted':True,'progress_after_cold_back':pack['progress']},indent=2));print({'cover_image_thumbnail':200,'readonly_37_tables_equal':True,'remaining_files':49,'original_46_files_unchanged':True},flush=True)
