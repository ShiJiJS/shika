import ui,time
from pathlib import Path
DEV='/dev/input/event1'
def run(name,build):
 lines=['#!/system/bin/sh',f"trap 'sendevent {DEV} 3 47 0; sendevent {DEV} 3 57 -1; sendevent {DEV} 3 47 1; sendevent {DEV} 3 57 -1; sendevent {DEV} 0 0 0' EXIT"]
 def ev(t,c,v):lines.append(f'sendevent {DEV} {t} {c} {v}')
 def pos(slot,x,y,start=None):
  assert 0<=x<1080 and 0<=y<2400
  ev(3,47,slot)
  if start is not None:
   ev(3,57,start);ev(3,55,0);ev(3,48,12);ev(3,49,12);ev(3,58,100)
  ev(3,53,round(x*32767/1079));ev(3,54,round(y*32767/2399))
 def sync(delay=.04):ev(0,0,0);lines.append('sleep '+str(delay))
 def lift(slot):ev(3,47,slot);ev(3,57,-1)
 build(pos,sync,lift);lift(0);lift(1);sync(.1)
 p=ui.L/(name+'.sh');p.write_text('\n'.join(lines)+'\n');remote='/data/local/tmp/lf8-native25-flow-'+name+'.sh';ui.device('push',str(p),remote);ui.record({'action':'kernel-pointer-gesture','script':p.name,'device':'virtio_input_multi_touch_1','slots':[0,1],'display':[1080,2400]});ui.device('shell','sh',remote);time.sleep(.5)
def expand(pos,sync,lift):
 pos(0,450,800,2500);pos(1,630,800,2501);sync(.06)
 for i in range(1,11):pos(0,450-i*32,800);pos(1,630+i*32,800);sync()
def handoff(pos,sync,lift):
 pos(0,300,1300,2510);sync(.06)
 for i in range(1,6):pos(0,300,1300-i*12);sync()
 pos(1,700,1240,2511);sync(.1)
 for i in range(1,7):pos(0,300-i*20,1240);pos(1,700+i*20,1240);sync()
 lift(1);sync(.1)
 for i in range(1,13):pos(0,180,1240-i*50);sync(.07)
 sync(.15)
def shrink(pos,sync,lift):
 pos(0,130,850,2520);pos(1,950,850,2521);sync(.06)
 for i in range(1,13):pos(0,130+i*32,850);pos(1,950-i*32,850);sync()
