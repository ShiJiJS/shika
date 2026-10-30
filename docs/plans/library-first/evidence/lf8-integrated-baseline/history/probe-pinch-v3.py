import json,subprocess,time
from pathlib import Path
import business_ui as u,driver,native_input as n,reader_observer as o
from ui_driver import device,record,ADB,SERIAL
L=Path(__file__).resolve().parent.parent
nodes=u.snap('pinch-v3-baseline-page-three');assert '3 / 6' in driver.text(nodes)
def pids(name):
 r=subprocess.run([ADB,'-s',SERIAL,'shell','pidof',name],capture_output=True,timeout=15)
 assert r.returncode in [0,1] and not r.stderr,r.stderr
 return r.stdout.decode().split()
before=o.read('pinch-v3-before');p='/sdcard/lf8-integrated-pinch-v3.mp4';assert not pids('screenrecord') and not pids('getevent')
trace=(L/'pinch-v3-getevent.txt').open('wb');watch=subprocess.Popen([ADB,'-s',SERIAL,'shell','getevent','-lt','/dev/input/event1'],stdout=trace,stderr=subprocess.STDOUT)
movie=subprocess.Popen([ADB,'-s',SERIAL,'shell','screenrecord','--size','780x1810','--bit-rate','1500000','--time-limit','180',p],stdout=(L/'pinch-v3-record.log').open('wb'),stderr=subprocess.STDOUT)
try:
 end=time.monotonic()+10
 while not pids('screenrecord'):
  assert movie.poll() is None and time.monotonic()<end;time.sleep(.1)
 (L/'pinch-v3-live.json').write_text(json.dumps({'host_recorder_pid':movie.pid,'host_getevent_pid':watch.pid,'device_recorder_pids':pids('screenrecord'),'qemu_pid':88655,'remote_path':p},indent=2)+'\n')
 checks=[]
 for i in [1,2,3]:
  label=f'pinch-v3-round-{i}'
  assert movie.poll() is None,'recorder exited before gesture'
  n.pinch(label)
  assert movie.poll() is None,'recorder exited during gesture'
  nodes=u.snap(label+'-zoomed');assert '3 / 6' in driver.text(nodes) and '夏日祭' in driver.text(nodes)
  zoom=o.read(label+'-zoomed');assert zoom['progress']['page_id']==before['progress']['page_id']
  device('shell','input','swipe','850','1200','400','1200','550');nodes=u.snap(label+'-panned');assert '3 / 6' in driver.text(nodes)
  pan=o.read(label+'-panned');assert pan['progress']['page_id']==before['progress']['page_id']
  device('shell','input','keyevent','4');nodes=u.snap(label+'-back-reset');assert '3 / 6' in driver.text(nodes) and '夏日祭' in driver.text(nodes)
  reset=o.read(label+'-back-reset');assert reset['progress']['page_id']==before['progress']['page_id']
  checks.append({'name':label,'page_id':before['progress']['page_id'],'native_kernel_two_finger_input':True,'zoom_pan_and_first_back_kept_same_reader_page':True})
 (L/'pinch-v3-result.json').write_text(json.dumps({'complete':True,'checks':checks,'not_image_scale_pixel_verification_yet':True},indent=2)+'\n')
finally:
 pid=pids('screenrecord')
 if movie.poll() is None and len(pid)==1:
  cmd=device('shell','cat','/proc/'+pid[0]+'/cmdline');assert p.encode() in cmd;device('shell','kill','-2',pid[0])
 exitcode=movie.wait(timeout=20);device('pull',p,str(L/'pinch-v3.mp4'));watch.terminate();watch.wait(timeout=10);trace.close();assert exitcode==0 and (L/'pinch-v3.mp4').stat().st_size>1000
