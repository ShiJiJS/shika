import json,re,subprocess,time,xml.etree.ElementTree as E
from pathlib import Path
L=Path(__file__).resolve().parent;ROOT=L.parents[1];ADB=ROOT/'.dev/android-sdk/platform-tools/adb';PACKAGE='io.github.shijijs.video_viewer'
def device(*a):return subprocess.check_output([str(ADB),'-s','emulator-5554',*a],timeout=40)
def xml():
 path='/sdcard/lf8-native25-compat-ui.xml'
 for attempt in range(2):
  device('shell','rm','-f',path)
  result=device('shell','uiautomator','dump',path)
  if b'dumped to:' in result.lower():
   raw=device('exec-out','cat',path);return raw,list(E.fromstring(raw).iter('node'))
  record({'action':'observation-only-retry','attempt':attempt+1,'detail':'no fresh UI XML','stdout':result.decode(errors='replace')})
  time.sleep(.2)
 raise RuntimeError('No fresh UI XML; no action was retried')

def record(v):
 with (L/'ui-events.jsonl').open('a') as f:f.write(json.dumps({'time':time.time(),**v},ensure_ascii=False)+'\n')
def tap(node,label):
 b=list(map(int,re.findall(r'\d+',node.get('bounds'))));assert b[2]>b[0] and b[3]>b[1];assert node.get('enabled')!='false';device('shell','input','tap',str((b[0]+b[2])//2),str((b[1]+b[3])//2));record({'action':'tap','label':label,'bounds':node.get('bounds')})
def fill(index,value,password=False):
 raw,nodes=xml();fields=[v for v in nodes if v.get('class')=='android.widget.EditText'];tap(fields[index],'fixture-field-'+str(index));device('shell','input','keyevent','123');device('shell','input','keyevent',*(['67']*max(32,len(fields[index].get('text',''))+2)));device('shell','input','text',value);record({'action':'fill','index':index,'value':'[fixture password]' if password else value})
def choose(label):
 raw,nodes=xml();found=[n for n in nodes if n.get('clickable')=='true' and (n.get('content-desc')==label or n.get('text')==label)];assert len(found)==1,(label,len(found));tap(found[0],label)
def snap(name):
 raw,nodes=xml();(L/'screens'/f'{name}.xml').write_bytes(raw);png=device('exec-out','screencap','-p');assert png.startswith(b'\x89PNG');(L/'screens'/f'{name}.png').write_bytes(png);return nodes
