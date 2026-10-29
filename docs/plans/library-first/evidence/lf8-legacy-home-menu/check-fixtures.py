import hashlib,json,subprocess,time,urllib.request,urllib.error
from pathlib import Path
R=Path(__file__).resolve().parents[2];L=R/'.dev/lf8-legacy-home-menu';read=lambda p:json.loads(p.read_text());results={}
for kind in ['legacy','modern']:
 O=L/kind;m=read(O/'runtime.json');base='http://127.0.0.1:'+str(m['port']);end=time.monotonic()+45
 while True:
  try:
   with urllib.request.urlopen(base+'/health',timeout=3) as r:assert r.status==200
   break
  except (urllib.error.URLError,ConnectionError):assert time.monotonic()<end;time.sleep(.2)
 h={'Content-Type':'application/json'}
 def api(path,method='GET',body=None):
  req=urllib.request.Request(base+path,headers=h,method=method,data=None if body is None else json.dumps(body).encode())
  with urllib.request.urlopen(req,timeout=10) as r:
   b=r.read();return json.loads(b) if b else None
 token=api('/api/v1/auth/login','POST',{'passphrase':(O/'config/passphrase').read_text().strip()})['access_token'];h['Authorization']='Bearer '+token;info=api('/api/v1/info');assert ('capabilities' not in info) if kind=='legacy' else ('fixed_video_sessions' in info['capabilities'])
 while api('/api/v1/library-state')['scanning']:
  assert time.monotonic()<end;time.sleep(.2)
 videos=api('/api/v1/videos')['items'];assert len(videos)==2;api('/api/v1/auth/session','DELETE')
 schema=subprocess.check_output(['docker','exec',m['container'],'python','-c',"import sqlite3;c=sqlite3.connect('file:/data/library.sqlite3?mode=ro',uri=True);print(c.execute('select version_num from alembic_version').fetchone()[0]);c.close()"],text=True).strip();assert schema==('0004' if kind=='legacy' else '0014')
 v={'image':m['image'],'schema':schema,'info':info,'video_ids':sorted(x['id'] for x in videos),'video_count':2,'probe_token_revoked':True,'native_capabilities_absent':kind=='legacy'};(O/'service-proof.json').write_text(json.dumps(v,indent=2)+'\n');results[kind]={'image':m['image'],'schema':schema,'native_capabilities_absent':kind=='legacy'}
# Compare original service Python bytes in the immutable old image to 0.1.4 source.
code="import hashlib,json,pathlib;root=pathlib.Path('/app/video_viewer');print(json.dumps({str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in root.rglob('*.py')}))"
actual=json.loads(subprocess.check_output(['docker','exec',read(L/'legacy/runtime.json')['container'],'python','-c',code]));base='f5fe32c9e8136fa0b54a272609d8b7f2ac1d83ba';prefix='services/server/video_viewer/';paths=subprocess.check_output(['git','ls-tree','-r','--name-only',base,'--',prefix],text=True).splitlines();expected={p[len(prefix):]:hashlib.sha256(subprocess.check_output(['git','show',base+':'+p])).hexdigest() for p in paths if p.endswith('.py')};assert actual==expected,{'unexpected':sorted(set(actual)-set(expected)),'missing':sorted(set(expected)-set(actual)),'different':[k for k in expected.keys()&actual.keys() if expected[k]!=actual[k]]}
proof={'source':base,'image':results['legacy']['image'],'all_python_source_files_match':True,'files':actual};(L/'legacy-source-proof.json').write_text(json.dumps(proof,indent=2)+'\n');print(json.dumps({'services':results,'old_service_python_files_match':len(actual)}))
