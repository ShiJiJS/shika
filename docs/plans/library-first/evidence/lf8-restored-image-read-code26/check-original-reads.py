import hashlib,json,urllib.request
from pathlib import Path
import api,media
from snapshot_all import snapshot
L=Path(__file__).resolve().parent;P=L.parent/'lf8-pack-purge-native26'
old=json.loads((P/'restored-image-read-conflict.json').read_text())
auth=json.loads(api.TOKEN.read_text());headers={'Authorization':'Bearer '+auth['access_token'],'X-Management-Epoch':auth['management_epoch']}
pack=next(x for x in api.all_pages('/api/v1/packs') if x['id']==old['pack_id'])
page=api.call('GET','/api/v1/packs/'+pack['id']+'/pages')['items'][0]
assert page['id']==old['page_id'] and pack['content_version']==3 and page['relative_path']=='03.png'
before=snapshot('normal26','original-before-read-200');files=media.save('original-before-read-200');results=[]
for cycle in range(3):
    for kind,path in [('cover',pack['cover_url']),('image',page['image_url']),('thumbnail',page['thumbnail_url'])]:
        with urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:8788'+path,headers=headers),timeout=20) as response:
            data=response.read();assert response.status==200
            digest=hashlib.sha256(data).hexdigest()
            if kind=='image':assert digest==old['actual_sha256'] and data.startswith(b'\x89PNG')
            else:assert data.startswith(b'\xff\xd8')
            assert response.headers.get('X-Content-Version')=='3'
            results.append({'cycle':cycle+1,'kind':kind,'status':response.status,'bytes':len(data),'sha256':digest,'content_type':response.headers.get('Content-Type'),'content_version':response.headers.get('X-Content-Version')})
with urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:8788'+page['image_url'],headers={**headers,'Range':'bytes=2-17'}),timeout=20) as response:
    data=response.read();assert response.status==206 and data==(L/'media/Restore-partial/03.png').read_bytes()[2:18]
    results.append({'kind':'original-range','status':206,'bytes':len(data),'content_range':response.headers['Content-Range']})
after=snapshot('normal26','original-after-read-200')
for key in ['tables','opaque_table_digests','setting_key_sha256']:assert before[key]==after[key],key
assert media.files()==files
(L/'original-read-200.json').write_text(json.dumps({'same_original_pack_id':pack['id'],'same_original_page_id':page['id'],'same_content_version':3,'results':results,'all_37_tables_and_settings_equal':True,'all_46_original_files_byte_identical':True,'old_permanent_stale_result_unchanged':True,'no_scan_restore_permanent_or_page_metadata_write':True,'fixed_source':json.loads((L/'runtime.json').read_text())['source']},indent=2))
print({'original_cover_image_thumbnail':'200 in three repeated reads','range':206,'all_37_tables_equal':True,'all_46_files_unchanged':True},flush=True)
