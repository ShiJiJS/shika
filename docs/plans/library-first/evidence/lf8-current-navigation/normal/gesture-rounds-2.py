import json,subprocess,time
from pathlib import Path
import business_ui as u,driver,native_input as n,reader_observer as observer
from ui_driver import device,ADB,SERIAL
L=Path(__file__).resolve().parent.parent
nodes=u.snap('gesture2-baseline');assert '3 / 6' in driver.text(nodes) and '26 / 27' in driver.text(nodes)
def pids(name):
 r=subprocess.run([ADB,'-s',SERIAL,'shell','pidof',name],capture_output=True,timeout=15);assert r.returncode in [0,1] and not r.stderr;return r.stdout.decode().split()
from batched_touch import double
before=observer.read('gesture2-before');remote='/sdcard/lf8-current-navigation-gestures2.mp4';assert not pids('screenrecord') and not pids('getevent')
trace=(L/'gesture2-getevent.txt').open('wb');watch=subprocess.Popen([ADB,'-s',SERIAL,'shell','getevent','-lt','/dev/input/event1'],stdout=trace,stderr=subprocess.STDOUT)
log=(L/'gesture2-record.log').open('wb');movie=subprocess.Popen([ADB,'-s',SERIAL,'shell','screenrecord','--size','780x1810','--bit-rate','1500000','--time-limit','180',remote],stdout=log,stderr=subprocess.STDOUT)
checks=[]
try:
 end=time.monotonic()+10
 while not pids('screenrecord'):
  assert movie.poll() is None and time.monotonic()<end;time.sleep(.1)
 (L/'gesture2-live.json').write_text(json.dumps({'host_recorder_pid':movie.pid,'host_getevent_pid':watch.pid,'qemu_pid':json.loads((L/'device.json').read_text())['pid'],'remote_path':remote},indent=2)+'\n')
 for i in [1,2,3]:
  name=f'gesture2-round-{i}'
  for kind in ['pinch','double']:
   assert movie.poll() is None
   n.pinch(name+'-pinch') if kind=='pinch' else double(name+'-double')
   for state in ['zoomed','panned','back-reset']:
    if state=='panned':device('shell','input','swipe','850','1200','400','1200','550')
    if state=='back-reset':device('shell','input','keyevent','4')
    label=name+'-'+kind+'-'+state;nodes=u.snap(label);labels=driver.text(nodes);assert '3 / 6' in labels and '26 / 27' in labels and '返回来源' in labels
    value=observer.read(label);assert value['progress']==before['progress'];checks.append({'round':i,'kind':kind,'state':state,'page_id':value['progress']['page_id']})
 (L/'gesture2-result.json').write_text(json.dumps({'complete':True,'checks':checks,'actual_two_finger_pinch_and_double_tap':True},indent=2)+'\n')
finally:
 pid=pids('screenrecord')
 if movie.poll() is None and len(pid)==1:
  assert remote.encode() in device('shell','cat','/proc/'+pid[0]+'/cmdline');device('shell','kill','-2',pid[0])
 exitcode=movie.wait(timeout=20);device('pull',remote,str(L/'gestures2.mp4'));watch.terminate();watch.wait(timeout=10);trace.close();log.close();assert exitcode==0 and (L/'gestures2.mp4').stat().st_size>1000
