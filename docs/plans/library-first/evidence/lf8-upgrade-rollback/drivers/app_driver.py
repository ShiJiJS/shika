import json,subprocess,time
from pathlib import Path
from ui_driver import capture,device,record,tap,fill,OUT,ADB,SERIAL
PACKAGE='io.github.shijijs.video_viewer'
def trace_count(phase):return len((OUT/'trace'/phase/'requests.jsonl').read_text().splitlines())
def save(name,value):(OUT/name).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')
def text(nodes):return '\n'.join(n.get('text','')+'\n'+n.get('content-desc','') for n in nodes)
def show(nodes):
 for n in nodes:
  value=n.get('text') or n.get('content-desc')
  if value:print(value,n.get('bounds'))
def current_pid():
 p=subprocess.run([ADB,'-s',SERIAL,'shell','pidof',PACKAGE],capture_output=True,text=True)
 return p.stdout.strip() if p.returncode==0 else None

def cold_start(phase,kind):
 assert kind in ['legacy','new'];before=current_pid();device('shell','am','force-stop',PACKAGE);assert current_pid() is None
 offset=trace_count(phase);device('shell','am','start','-n',PACKAGE+'/.MainActivity')
 name=phase+'-landing';deadline=time.monotonic()+50
 while True:
  nodes=capture(name);value=text(nodes)
  expected='媒体库' if kind=='new' else '视频库'
  if expected in value:break
  if time.monotonic()>deadline:raise AssertionError('Expected '+kind+' landing not ready')
  time.sleep(.5)
 after=current_pid();assert after and after!=before
 save(phase+'-app-start.json',{'previous_pid':before,'new_pid':after,'cold_start':True,'trace_start_offset':offset,'expected_mode':kind,'landing_capture':name})
 show(nodes);return nodes

if __name__=='__main__':
 import sys
 if sys.argv[1]=='start':cold_start(sys.argv[2],sys.argv[3])
