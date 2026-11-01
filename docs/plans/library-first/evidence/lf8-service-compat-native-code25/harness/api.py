import json
from pathlib import Path
from urllib.request import Request,urlopen
L=Path(__file__).resolve().parent;TOKEN=L/'config/session-private.json'
def call(method,path,body=None):
 headers={'Content-Type':'application/json'}
 if TOKEN.exists():
  s=json.loads(TOKEN.read_text());headers.update({'Authorization':'Bearer '+s['access_token'],'X-Management-Epoch':s['management_epoch']})
 with urlopen(Request('http://127.0.0.1:8787'+path,data=json.dumps(body).encode() if body is not None else None,headers=headers,method=method),timeout=30) as r:return json.load(r) if r.status!=204 else None
if __name__=='__main__':
 TOKEN.write_text(json.dumps(call('POST','/api/v1/auth/login',{'passphrase':(L/'config/passphrase').read_text()})));TOKEN.chmod(0o600)
 state=call('GET','/api/v1/library-state')
 (L/'initial-library-state.json').write_text(json.dumps(state,indent=2)+'\n')
 print({'scanning':state['scanning'],'root_count':len(state['roots']),'root_statuses':[r.get('scan',{}).get('status') if r.get('scan') else None for r in state['roots']]})
