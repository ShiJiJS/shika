"""Local-only observer: no bodies/headers/auth values are written to the trace."""
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
import http.client,json,threading,time
from pathlib import Path
from urllib.parse import urlsplit,parse_qs
L=Path(__file__).resolve().parent;lock=threading.Lock();sequence=max([json.loads(s)['seq'] for s in (L/'requests.jsonl').read_text().splitlines()] or [0]) if (L/'requests.jsonl').exists() else 0
class Handler(BaseHTTPRequestHandler):
 protocol_version='HTTP/1.1'
 def log_message(self,*args):pass
 def forward(self):
  global sequence
  parsed=urlsplit(self.path)
  if parsed.scheme or parsed.netloc:self.send_error(400);return
  with lock:sequence+=1;seq=sequence
  record={'seq':seq,'time':time.time(),'method':self.command,'path':parsed.path,'query':{k:v for k,v in parse_qs(parsed.query).items() if k in ['offset','limit','v','version','content_version']}}
  upstream=None
  try:
   length=int(self.headers.get('Content-Length','0'))
   if length>16*1024*1024:self.send_error(413);return
   if self.headers.get('Transfer-Encoding','').lower()=='chunked':
    chunks=[];length=0
    while True:
     size=int(self.rfile.readline().strip().split(b';',1)[0],16)
     if size==0:
      while self.rfile.readline().strip():pass
      break
     length+=size
     if length>16*1024*1024:raise ValueError('request too large')
     chunks.append(self.rfile.read(size))
     if self.rfile.read(2)!=b'\r\n':raise ValueError('invalid chunk delimiter')
    body=b''.join(chunks)
    record['input_framing']='chunked'
   else:
    body=self.rfile.read(length) if length else None
    record['input_framing']='content-length'
   record['request_bytes']=length
   if parsed.path=='/api/v1/scans' and body:
    scoped=json.loads(body);record['scan_request']={'all':not bool(scoped.get('root_id')),'root_id':scoped.get('root_id')}
   headers={k:v for k,v in self.headers.items() if k.lower() not in ['connection','proxy-connection','transfer-encoding','accept-encoding']}
   headers['Connection']='close'
   if body is not None:headers['Content-Length']=str(len(body))
   upstream=http.client.HTTPConnection('127.0.0.1',8787,timeout=40)
   upstream.request(self.command,self.path,body,headers);response=upstream.getresponse();record['status']=response.status
   self.send_response(response.status)
   for k,v in response.getheaders():
    if k.lower() not in ['connection','transfer-encoding','keep-alive']:self.send_header(k,v)
   self.send_header('Connection','close');self.end_headers();self.close_connection=True
   capture=bytearray() if parsed.path.endswith('/pages') and 'json' in response.getheader('Content-Type','') else None
   total=0
   if self.command!='HEAD':
    while True:
     chunk=response.read(65536)
     if not chunk:break
     self.wfile.write(chunk);total+=len(chunk)
     if capture is not None and len(capture)<1024*1024:capture.extend(chunk)
   record['response_bytes']=total
   if capture is not None:
    data=json.loads(capture);record['page_result']={k:data.get(k) for k in ['offset','limit','total','content_version']};record['page_result']['items']=len(data.get('items',[]))
  except (BrokenPipeError,ConnectionResetError):record['client_cancelled']=True
  except Exception as exc:
   record['error']=type(exc).__name__
   if 'status' not in record:
    self.send_error(502)
  finally:
   if upstream is not None:upstream.close()
   record['finished_at']=time.time()
   with lock:
    with (L/'requests.jsonl').open('a') as f:f.write(json.dumps(record,separators=(',',':'))+'\n')
 do_GET=do_HEAD=do_POST=do_PATCH=do_PUT=do_DELETE=forward
server=ThreadingHTTPServer(('127.0.0.1',8783),Handler)
print('Local observer bound to 127.0.0.1:8783; forwards only 127.0.0.1:8787',flush=True)
try:server.serve_forever()
finally:server.server_close()
