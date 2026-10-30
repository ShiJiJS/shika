import json,urllib.request,urllib.parse
from pathlib import Path
L=Path(__file__).resolve().parent;O=L/'normal';seed=json.loads((L/'seed.json').read_text());lines=[json.loads(s) for s in (O/'trace/requests.jsonl').read_text().splitlines()]
result={}
for kind,path in [('video','/api/v1/videos/selection'),('pack','/api/v1/packs/selection')]:
 rows=[x for x in lines if x['path']==path and urllib.parse.parse_qs(x.get('query','')).get('search')==['Scope']];assert rows;row=rows[-1];req=urllib.request.Request('http://127.0.0.1:8776'+path+'?'+row['query'],headers={'Authorization':'Bearer '+(O/'config/observer-token').read_text().strip()})
 with urllib.request.urlopen(req,timeout=20) as r:v=json.load(r)
 expected={x['id'] for x in seed['videos' if kind=='video' else 'packs'] if x['name'].startswith('Scope ')};assert len(expected)==27 and len(v['ids'])==27 and set(v['ids'])==expected and v['kind']==kind
 result[kind]={'app_request':row,'readback':v}
(L/'selection-responses.json').write_text(json.dumps(result,indent=2)+'\n');print('selection memberships verified')
