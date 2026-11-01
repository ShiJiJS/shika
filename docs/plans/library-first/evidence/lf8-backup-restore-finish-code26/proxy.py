"""Local native observer. Never hold responses or store credentials/archive bodies."""
import hashlib,http.client,json,threading,time
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit,parse_qs
L=Path(__file__).resolve().parent;lock=threading.Lock();sequence=0
def digest(v):return hashlib.sha256(v.encode()).hexdigest() if v else None
class Handler(BaseHTTPRequestHandler):
    protocol_version='HTTP/1.1'
    def log_message(self,*args):pass
    def forward(self):
        global sequence
        path=urlsplit(self.path)
        if path.netloc or path.scheme:self.send_error(400);return
        with lock:sequence+=1;seq=sequence
        record={'seq':seq,'time':time.time(),'method':self.command,'path':path.path,'query':{k:v for k,v in parse_qs(path.query).items() if k in ['limit','offset','v','source','sort','kind','status']},'request_epoch_sha256':digest(self.headers.get('X-Management-Epoch'))}
        upstream=None
        try:
            if self.headers.get('Transfer-Encoding','').lower()=='chunked':
                chunks=[];size_total=0
                while True:
                    size=int(self.rfile.readline().strip().split(b';',1)[0],16)
                    if not size:
                        while self.rfile.readline().strip():pass
                        break
                    size_total+=size;assert size_total<=32*1024*1024
                    chunks.append(self.rfile.read(size));assert self.rfile.read(2)==b'\r\n'
                body=b''.join(chunks)
            else:
                size_total=int(self.headers.get('Content-Length','0'));assert size_total<=32*1024*1024
                body=self.rfile.read(size_total) if size_total else None
            record['request_bytes']=size_total
            if body and 'json' in self.headers.get('Content-Type','') and not path.path.startswith('/api/v1/auth/'):
                parsed=json.loads(body)
                keys=['request_id','preview_id','root_mapping','confirmed','pack_id','page_id','content_version','expected_revision','expected_session_revision','offset_ratio','completed','source','scope','sort','order','anchor_pack_id']
                record['command']={k:parsed[k] for k in keys if k in parsed}
            headers={k:v for k,v in self.headers.items() if k.lower() not in ['connection','proxy-connection','transfer-encoding','accept-encoding']};headers['Connection']='close'
            if body is not None:headers['Content-Length']=str(len(body))
            upstream=http.client.HTTPConnection('127.0.0.1',8788,timeout=30);upstream.request(self.command,self.path,body,headers);response=upstream.getresponse();data=response.read()
            record.update(status=response.status,response_bytes=len(data),response_epoch_sha256=digest(response.getheader('X-Management-Epoch')))
            if 'application/json' in response.getheader('Content-Type',''):
                view=json.loads(data) if data else {}
                if isinstance(view,dict) and 'id' in view:
                    record['response_task']={k:view[k] for k in ['id','kind','status','phase','error'] if k in view}
            self.send_response(response.status)
            for key,value in response.getheaders():
                if key.lower() not in ['connection','transfer-encoding','content-length']:self.send_header(key,value)
            length=response.getheader('Content-Length','0') if self.command=='HEAD' else str(len(data))
            self.send_header('Content-Length',length);self.send_header('Connection','close');self.end_headers()
            if self.command!='HEAD':self.wfile.write(data)
        except Exception as error:
            record['observer_error']=type(error).__name__
            if 'status' not in record:
                record['status']=502;self.send_error(502)
        finally:
            record['finished_at']=time.time()
            with lock:
                with (L/'requests.jsonl').open('a') as f:f.write(json.dumps(record)+'\n')
            if upstream:upstream.close()
    do_GET=do_POST=do_PATCH=do_PUT=do_DELETE=do_HEAD=forward
print('Own local observer 8783 -> 8788; no injected response errors',flush=True)
ThreadingHTTPServer(('127.0.0.1',8783),Handler).serve_forever()
