import json,re,subprocess,time
from pathlib import Path
from ui_driver import capture,device,record,tap,fill,OUT,ADB,SERIAL
PACKAGE='io.github.shijijs.video_viewer'
def save(name,v):(OUT/name).write_text(json.dumps(v,indent=2,ensure_ascii=False)+'\n')
def text(nodes):return '\n'.join(n.get('text','')+'\n'+n.get('content-desc','') for n in nodes)
def show(nodes):
 for n in nodes:
  v=n.get('text') or n.get('content-desc')
  if v:print(v,n.get('bounds'))
def snap(name):
 n=capture(name);show(n);return n
def tap_label(name,label=None,prefix=None):
 n=capture(name)
 matches=[v for v in n if v.get('content-desc')==label] if label else [v for v in n if v.get('content-desc','').startswith(prefix)]
 assert len(matches)==1,(label,prefix,[v.get('content-desc') for v in matches]);tap(matches[0],label or prefix)
def trace_count():return len((OUT/'trace/requests.jsonl').read_text().splitlines())
def cold(name,kind):
 device('shell','am','force-stop',PACKAGE);offset=trace_count();device('shell','am','start','-n',PACKAGE+'/.MainActivity');deadline=time.monotonic()+50
 while True:
  n=capture(name+'-landing');v=text(n)
  if ('媒体库' if kind=='new' else '视频库') in v:break
  assert time.monotonic()<deadline,'landing not ready';time.sleep(.4)
 save(name+'-startup.json',{'trace_offset':offset,'trace_end_offset':trace_count(),'pid':device('shell','pidof',PACKAGE).decode().strip(),'kind':kind});show(n);return n
if __name__=='__main__':
 import sys
 if sys.argv[1]=='cold':cold(sys.argv[2],sys.argv[3])
 elif sys.argv[1]=='snap':snap(sys.argv[2])
 elif sys.argv[1]=='tap':tap_label(sys.argv[2],label=sys.argv[3]);snap(sys.argv[2]+'-after')

def package_state(name):
 dump=device('shell','dumpsys','package',PACKAGE).decode();(OUT/(name+'-package.txt')).write_text(dump)
 fields={key:re.search(r'\b'+key+r'=([^\n]+)',dump).group(1).strip() for key in ['versionCode','versionName','firstInstallTime','lastUpdateTime','dataDir','appId']}
 save(name+'-package.json',fields);return fields

def appearance(name):
 raw=device('exec-out','cat','/data/user/0/'+PACKAGE+'/files/appearance.json');v=json.loads(raw);save(name+'-preferences.json',v);return v

def install(name,kind):
 manifest=json.loads((OUT.parent/'build-1/result.json').read_text());entry=manifest[kind]
 import hashlib
 p=Path(entry['path']);assert hashlib.sha256(p.read_bytes()).hexdigest()==entry['sha256']
 device('shell','am','force-stop',PACKAGE);before=package_state(name+'-before');offset=trace_count();out=device('install','-r',str(p)).decode();assert 'Success' in out
 after=package_state(name+'-after');assert before['firstInstallTime']==after['firstInstallTime'];assert before['dataDir']==after['dataDir'];assert before['appId']==after['appId'];assert after['versionCode'].split()[0]==str(entry['version_code']);assert after['versionName']==entry['version']
 save(name+'-install.json',{'command':['adb','-s',SERIAL,'install','-r',p.name],'output':out,'before':before,'after':after,'sha256':entry['sha256'],'trace_offset':offset,'no_uninstall_or_clear':True})
 return cold(name,'legacy' if kind=='rollback' else 'new')
