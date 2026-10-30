import json,re
from pathlib import Path
import driver
from ui_driver import capture,tap,device,record
O=Path(__file__).resolve().parent

def snap(label):
 p=O/'business-cursor.json';v=json.loads(p.read_text()) if p.exists() else {'sequence':0,'checks':[]};v['sequence']+=1;p.write_text(json.dumps(v,indent=2)+'\n');name=f"biz-{v['sequence']:04d}-"+re.sub('[^a-z0-9-]','-',label.lower())[:65]
 n=capture(name);print(name,flush=True);driver.show(n);return n

def matches(nodes,label=None,prefix=None):
 return [n for n in nodes if n.get('clickable')=='true' and ((label is not None and label in [n.get('content-desc'),n.get('text')]) or (prefix is not None and (n.get('content-desc','').startswith(prefix) or n.get('text','').startswith(prefix))))]

def choose(label=None,prefix=None,context='action'):
 n=snap(context+'-before');items=matches(n,label,prefix);assert len(items)==1,(label,prefix,[x.get('content-desc') or x.get('text') for x in items]);tap(items[0],label or prefix);return snap(context+'-after')

def back(context):
 record({'action':'back','context':context});device('shell','input','keyevent','4');return snap(context+'-back')

def expect_text(nodes,label):
 assert label in driver.text(nodes),label

def check(name,details):
 p=O/'business-cursor.json';v=json.loads(p.read_text());assert name not in [x['name'] for x in v['checks']];v['checks'].append({'name':name,'trace_end':driver.trace_count(),'last_capture_sequence':v['sequence'],**details});p.write_text(json.dumps(v,indent=2,ensure_ascii=False)+'\n');print('CHECK',name,flush=True)
