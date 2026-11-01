"""Scan the exact retained sample once; persist the task id before waiting."""
import hashlib,json,urllib.request
from pathlib import Path
import api,media
from snapshot_all import snapshot
L=Path(__file__).resolve().parent
assert not (L/'original-scan-state.json').exists()
before=snapshot('preparation-api','before-first-fixed-scan');files=media.save('before-first-fixed-scan')
original='1958716a-589a-4942-8a00-0a812b165e28';duplicate='62d5fe84-0cc6-434b-b391-75da4740f722';tall='b7212acf-a7f2-4a9a-8127-b85d120d4868'
pack_ids=[original,tall];page_ids=['e461e7c1-6de6-4765-bf7f-ddb9ccdcf54f','508632ed-3b55-4791-9ebc-51f5a316ecc6']
submitted=api.call('POST','/api/v1/scans',{'root_id':'purge'})
state={'phase':'submitted_original_fixed_scan','task_id':submitted['id'],'entry':'explicit preparation API, not native UI'}
(L/'original-scan-state.json').write_text(json.dumps(state,indent=2))
task=api.wait(submitted['id']);assert task['status']=='completed',task
assert all(r['status']=='completed' for r in task['result']['roots']),task
after=snapshot('preparation-api','after-first-fixed-scan')
protected=[k for k in before['tables'] if k not in ['directories','observations','pack_file_steps','pack_pages','packs','roots','tasks']]
assert all(before['tables'][k]==after['tables'][k] for k in protected)
assert before['opaque_table_digests']==after['opaque_table_digests']
assert before['setting_key_sha256']==after['setting_key_sha256']
assert media.files()==files and len(files)==49
assert not any(p['id']==duplicate for p in after['tables']['packs'])
results=[]
for identity,page_id in zip(pack_ids,page_ids):
    pack=api.call('GET','/api/v1/packs/'+identity);pages=api.call('GET','/api/v1/packs/'+identity+'/pages')['items']
    assert pack['status']=='available' and pack['page_count']==1 and pack['tag_ids']
    assert len(pages)==1 and pages[0]['id']==page_id
    assert pack['progress']['page_id']==page_id
    if identity==tall:assert pack['progress']['offset_ratio']==.45
    results.append({'pack':pack,'remaining_page':pages[0]})
recent=api.call('GET','/api/v1/recent?kind=pack');assert recent['total']==3
state.update(phase='first_fixed_scan_verified',scan_task=task,packs=results,protected_28_tables_unchanged=protected,settings_and_credentials_unchanged=True,all_49_files_byte_identical=True,unmanaged_duplicate_retired=duplicate,original_id_restored=original,tall_original_id_preserved=tall,tall_offset_ratio=.45,api_recent=recent)
(L/'original-scan-state.json').write_text(json.dumps(state,indent=2))
read_before=snapshot('preparation-api','before-post-scan-image-reads')
auth=json.loads(api.TOKEN.read_text());headers={'Authorization':'Bearer '+auth['access_token'],'X-Management-Epoch':auth['management_epoch']};responses=[]
for row in results:
    for kind,path in [('cover',row['pack']['cover_url']),('image',row['remaining_page']['image_url']),('thumbnail',row['remaining_page']['thumbnail_url'])]:
        with urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:8788'+path,headers=headers),timeout=25) as response:
            data=response.read();assert response.status==200
            responses.append({'pack_id':row['pack']['id'],'page_id':row['remaining_page']['id'],'kind':kind,'status':200,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
            if kind=='image':assert responses[-1]['sha256']==files[row['pack']['name']+'/03.png']['sha256']
read_after=snapshot('preparation-api','after-post-scan-image-reads')
for key in ['tables','opaque_table_digests','setting_key_sha256']:assert read_before[key]==read_after[key],key
assert media.files()==files
state.update(phase='first_fixed_scan_and_reading_verified',image_responses=responses,read_37_tables_settings_unchanged=True)
(L/'original-scan-state.json').write_text(json.dumps(state,indent=2));print({'same_original_id_recovered':original,'same_tall_id_and_45_percent':tall,'recent_total':recent['total'],'file_count_unchanged':len(files),'cover_original_thumbnail_each_pack':200,'task':task['id']},flush=True)
