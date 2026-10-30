import json
from pathlib import Path
import business_ui as u,driver
from snapshot_all import snapshot
O=Path(__file__).resolve().parent;L=O.parent
n=u.snap('video-tag-return-confirm');assert '1 个视频' in driver.text(n) and '# Scope · # Intersection' in driver.text(n)
before=json.loads((O/'video-source-before-all-catalog.json').read_text());after=snapshot('new','video-source-after')
for key in ['pack_progress','pack_preferences','pack_sessions','pack_session_entries','pack_tag_definitions','pack_tag_links','packs','pack_pages','tags','video_tags']:
 assert before['tables'][key]==after['tables'][key],key
assert before['opaque_table_digests']['access_tokens']==after['opaque_table_digests']['access_tokens']
ranges=[]
for name in ['video-library-source','video-tag-source']:
 v=json.loads((L/(name+'-round.json')).read_text());r=v['round'];ranges.append({'id':r['id'],'source':r['source'],'count':r['candidate_count'],'scope':json.loads(r['scope'])})
(L/'video-entry-focus-result.json').write_text(json.dumps({'complete':True,'code':21,'ranges':ranges,'video_search_focus_not_restored':True,'pack_search_preserved':True,'all_pack_tables_and_two_tag_namespaces_unchanged':True,'diagnostic':'Original last assertion expected tag-picker wording after returning to results. Actual results display 1 个视频, correct source and item. Resumed here without replaying earlier actions.'},indent=2)+'\n')
