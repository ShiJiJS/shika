import hashlib,http.client,json,os,socket,threading,time,urllib.parse
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
L=Path(__file__).resolve().parent
LOCK=threading.Lock();COUNTER=0;CLAIMED=set()
def event(v):
 with LOCK:
  with (L/'proxy-events.jsonl').open('a') as f:f.write(json.dumps({'time':time.time(),'proxy_pid':os.getpid(),**v},ensure_ascii=False)+'\n')
class Handler(BaseHTTPRequestHandler):
 protocol_version='HTTP/1.1'
 def log_message(self,*args):pass
 def do_HEAD(self):self.forward()
 def do_GET(self):self.forward()
 def do_POST(self):self.forward()
 def do_PUT(self):self.forward()
 def do_PATCH(self):self.forward()
 def do_DELETE(self):self.forward()
 def forward(self):
  global COUNTER
  parsed=urllib.parse.urlsplit(self.path);query=urllib.parse.parse_qs(parsed.query)
  with LOCK:COUNTER+=1;identity=COUNTER
  rule=None
  if self.command=='GET' and parsed.path in ['/api/v1/videos','/api/v1/packs']:
   config=json.loads((L/'proxy-rules.json').read_text())
   for candidate in config.get('rules',[]):
    if candidate['path']==parsed.path and all(query.get(k)==[str(v)] for k,v in candidate['query'].items()):
     with LOCK:
      if candidate.get('once',False) and candidate['id'] in CLAIMED:continue
      CLAIMED.add(candidate['id'])
     rule=candidate;break
  base={'request':identity,'method':self.command,'path':parsed.path,'query':parsed.query,'rule':None if rule is None else rule['id']}
  self.connection.settimeout(30)
  if 'chunked' in self.headers.get('Transfer-Encoding','').lower():
   chunks=[]
   while True:
    size=int(self.rfile.readline().split(b';',1)[0].strip(),16)
    if size==0:
     while self.rfile.readline().strip():pass
     break
    chunks.append(self.rfile.read(size));assert self.rfile.read(2)==b'\r\n'
   body=b''.join(chunks)
  else:body=self.rfile.read(int(self.headers.get('Content-Length','0')))
  headers={k:v for k,v in self.headers.items() if k.lower() not in ['host','connection','proxy-connection','accept-encoding','transfer-encoding','content-length']};headers['Connection']='close'
  if body or self.command in ['POST','PUT','PATCH']:headers['Content-Length']=str(len(body))
  con=http.client.HTTPConnection('127.0.0.1',8777,timeout=30)
  try:
   con.request(self.command,self.path,body=body,headers=headers);response=con.getresponse();status=response.status;replyheaders=response.getheaders();raw=response.read()
  except Exception as exc:
   event({**base,'event':'upstream_error','error_type':type(exc).__name__});self.respond(502,[('Content-Type','application/json')],b'{"error":{"code":"fixture_upstream","message":"upstream unavailable"}}',base);return
  finally:con.close()
  if rule and rule['action']=='fail':
   assert any(k.lower()=='x-management-epoch' for k,v in replyheaders)
   raw=json.dumps({'error':{'code':'fixture_catalog_read','message':'测试读取暂不可用，请重试'}}).encode();event({**base,'event':'injected_failure','status':503,'authenticated_authority_header_preserved':True});self.respond(503,replyheaders,raw,base);return
  if self.command=='GET' and parsed.path in ['/api/v1/videos','/api/v1/packs'] and status==200:
   value=json.loads(raw);event({**base,'event':'catalog_response','status':status,'body_sha256':hashlib.sha256(raw).hexdigest(),'body_summary':{'total':value.get('total'),'offset':value.get('offset'),'limit':value.get('limit'),'ids':[x['id'] for x in value.get('items',[])]}})
  if rule and rule['action']=='hold':
   try:
    value=json.loads(raw);summary={'total':value.get('total'),'ids':[x['id'] for x in value.get('items',[])]}
   except (ValueError,TypeError,KeyError):summary={}
   event({**base,'event':'held','status':status,'body_sha256':hashlib.sha256(raw).hexdigest(),'body_summary':summary})
   end=time.monotonic()+90
   while not (L/('release-'+rule['id'])).exists():
    if time.monotonic()>end:event({**base,'event':'hold_timeout'});return
    time.sleep(.05)
   event({**base,'event':'released','status':status})
  self.respond(status,replyheaders,raw,base)
 def respond(self,status,headers,raw,base):
  try:
   self.send_response(status)
   for k,v in headers:
    if k.lower() not in ['connection','transfer-encoding','content-length','server','date']:self.send_header(k,v)
   length=next((v for k,v in headers if k.lower()=='content-length'),str(len(raw))) if self.command=='HEAD' else str(len(raw))
   self.send_header('Content-Length',length);self.send_header('Connection','close');self.end_headers()
   if self.command!='HEAD':self.wfile.write(raw);self.wfile.flush()
   event({**base,'event':'sent','status':status,'bytes':len(raw)})
  except (BrokenPipeError,ConnectionResetError,OSError) as exc:event({**base,'event':'client_closed','status':status,'error_type':type(exc).__name__})
  self.close_connection=True
server=ThreadingHTTPServer(('127.0.0.1',8778),Handler);server.daemon_threads=True
(L/'proxy-process.json').write_text(json.dumps({'pid':os.getpid(),'argv':['python3',str(Path(__file__).resolve())],'listen':'127.0.0.1:8778','upstream':'127.0.0.1:8777'},indent=2)+'\n');event({'event':'proxy_started','pid':os.getpid()});server.serve_forever()
