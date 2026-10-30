import hashlib,json,re,struct
from pathlib import Path
import native_input as n
from ui_driver import device,record
L=Path(__file__).resolve().parent.parent
assert device('shell','uname','-m').decode().strip()=='aarch64'
assert struct.calcsize('<qqHHi')==24
paths={}
for name,events in [('down1',n.frame(0,585,1200,1200)),('up1',n.up(0)),('down2',n.frame(0,585,1200,1201)),('up2',n.up(0))]:
 data=b''
 for event in events:
  match=re.fullmatch(r'sendevent /dev/input/event1 (\d+) (\d+) (-?\d+)',event);assert match,event
  data+=struct.pack('<qqHHi',0,0,*map(int,match.groups()))
 local=L/('double-'+name+'.bin');assert not local.exists();local.write_bytes(data);remote='/sdcard/lf8-current-double-'+name+'.bin';device('push',str(local),remote);paths[name]=remote
(L/'batched-input.json').write_text(json.dumps({'event_bytes':24,'device':'/dev/input/event1','files':{k:{'path':v,'sha256':hashlib.sha256((L/('double-'+k+'.bin')).read_bytes()).hexdigest()} for k,v in paths.items()}},indent=2)+'\n')
def double(name):
 cmds=['set -e', "trap 'dd if="+paths['up2']+" of=/dev/input/event1 bs=24 status=none' EXIT"]
 for k,delay in [('down1',.05),('up1',.10),('down2',.05),('up2',None)]:
  cmds.append('dd if='+paths[k]+' of=/dev/input/event1 bs=24 status=none')
  if delay is not None:cmds.append('sleep '+str(delay))
 script='\n'.join(cmds)+'\n';p=L/(name+'-batched-input.sh');assert not p.exists();p.write_text(script);record({'action':'kernel-batched-double-tap','name':name,'script':p.name,'intended_gap_seconds':.10});device('shell',script)
