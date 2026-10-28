import json,re,subprocess,time,xml.etree.ElementTree as ET
from pathlib import Path
ROOT=Path('/Users/jiangxinyi/Documents/Project/video-viewer');OUT=ROOT/'.dev/lf8-app-rollback';ADB=str(ROOT/'.dev/android-sdk/platform-tools/adb');SERIAL='emulator-5556'
def device(*args):return subprocess.check_output([ADB,'-s',SERIAL,*args],timeout=30)
def record(value):
 with (OUT/'ui-events.jsonl').open('a') as output:output.write(json.dumps({'time':time.time(),**value},ensure_ascii=False)+'\n')
def capture(name):
 device('shell','uiautomator','dump','/sdcard/lf8-app-rollback-ui.xml');raw=device('exec-out','cat','/sdcard/lf8-app-rollback-ui.xml');(OUT/'screens'/f'{name}.xml').write_bytes(raw);(OUT/'screens'/f'{name}.png').write_bytes(device('exec-out','screencap','-p'));focus=device('shell','dumpsys','window').decode();(OUT/'screens'/f'{name}-window.txt').write_text('\n'.join(s.strip() for s in focus.splitlines() if 'mCurrentFocus=' in s or 'mFocusedApp=' in s)+'\n');return list(ET.fromstring(raw).iter('node'))
def tap(node,label):
 x1,y1,x2,y2=map(int,re.findall(r'\d+',node.get('bounds')));assert x2>x1 and y2>y1;record({'action':'tap','label':label,'bounds':node.get('bounds')});device('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2))
def fill(index,value,name):
 nodes=capture(name+'-before');fields=[n for n in nodes if n.get('class')=='android.widget.EditText'];node=fields[index];tap(node,name);device('shell','input','keyevent','123');device('shell','input','keyevent',*(['67']*(len(node.get('text',''))+2)));cleared=capture(name+'-cleared');assert [n for n in cleared if n.get('class')=='android.widget.EditText'][index].get('text')=='';device('shell','input','text',value);record({'action':'fill','label':name,'value':'[fixture password]' if node.get('password')=='true' else value})
