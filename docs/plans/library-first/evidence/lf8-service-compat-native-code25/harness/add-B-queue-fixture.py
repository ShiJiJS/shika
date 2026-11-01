import sys,json,hashlib,importlib.util
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import ui,api
assert not api.call('GET','/api/v1/library-state')['scanning'];target=ui.L/'new-media/packs-b/B Queue';assert not target.exists();target.mkdir();spec=importlib.util.spec_from_file_location('fixture',ui.ROOT/'scripts/fixtures/generate-lf0-packs.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);rows=[]
for i in range(1,601):
 p=target/f'{i}.png';m.png(p,240,360,(125,80+i%90,140));rows.append({'name':p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(ui.L/'new-B-queue-fixture.json').write_text(json.dumps({'private_media':False,'generated_files':600,'dimensions':[240,360],'purpose':'Observe A finished while B remains active; generated test files only','files':rows},indent=2)+'\n');print({'added_public_B_files':600,'scan_not_requested_yet':True})
