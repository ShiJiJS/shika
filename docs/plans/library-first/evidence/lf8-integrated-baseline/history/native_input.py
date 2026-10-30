import json,time
from pathlib import Path
from ui_driver import device,record
L=Path(__file__).resolve().parent.parent
# Grounded by input-devices.txt and input-display-390x905.txt: event1 is
# DIRECT, primary display0; raw0..32767; logical1170x2715 maps to the
# physical [23,0,1057,2400] frame in the1080x2400 display.
NODE='/dev/input/event1'
def raw(x,y):return round((23+x*1034/1170)*32768/1080),round(y*32768/2715)
def event(code,value):return f'sendevent {NODE} 3 {code} {value}'
def frame(slot,x,y,start=None):
 X,Y=raw(x,y);cmd=[event(47,slot)]
 if start is not None:cmd.extend([event(57,start),event(55,0),event(48,12),event(49,12),event(58,100)])
 return cmd+[event(53,X),event(54,Y),'sendevent '+NODE+' 0 0 0']
def up(slot):return [event(47,slot),event(57,-1),'sendevent '+NODE+' 0 0 0']
def run(name,commands,details):
 release='; '.join(up(0)+up(1));script='set -e\ntrap '+"'"+release+"' EXIT\n"+'\n'.join(commands)+'\n'
 path=L/(name+'-kernel-input.sh');assert not path.exists();path.write_text(script)
 record({'action':'kernel-touch','name':name,'device':NODE,'script':str(path.relative_to(L)),**details});device('shell',script)
def tap(name,x,y):run(name,frame(0,x,y,1000)+['sleep 0.06']+up(0),{'logical_point':[x,y]})
def pinch(name,cx=585,cy=1200,start=120,end=330):
 commands=frame(0,cx-start,cy,1100)+['sleep 0.04']+frame(1,cx+start,cy,1101)+['sleep 0.05']
 for i in range(1,13):
  span=start+(end-start)*i/12;commands+=frame(0,cx-span,cy)+frame(1,cx+span,cy)+['sleep 0.025']
 commands+=['sleep 0.12']+up(1)+up(0)
 run(name,commands,{'logical_center':[cx,cy],'initial_span':start*2,'final_span':end*2,'two_tracking_ids':[1100,1101]})
