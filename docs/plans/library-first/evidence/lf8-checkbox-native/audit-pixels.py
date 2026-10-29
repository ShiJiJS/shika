import json,subprocess
from pathlib import Path
L=Path(__file__).resolve().parent;O=L/'native-5';events=json.loads((O/'events.json').read_text());results=[]
for clip in json.loads((O/'recordings.json').read_text()):
 name=clip['name'];start=next(i for i,e in enumerate(events) if e['action']=='begin' and e['name']==name);end=next(i for i,e in enumerate(events) if e['action']=='end' and e['name']==name)
 pts={tuple(e['point']) for e in events[start:end] if e.get('action')=='tap'};assert len(pts)==1;cx,cy=pts.pop();w=h=48;crop=[cx-24,cy-24,w,h]
 raw=subprocess.check_output(['ffmpeg','-v','error','-i',str(O/(name+'.mp4')),'-vf',f'crop={w}:{h}:{crop[0]}:{crop[1]},format=rgb24','-fps_mode','passthrough','-enc_time_base','demux','-f','rawvideo','pipe:1'],timeout=40)
 frame_bytes=w*h*3;assert len(raw)%frame_bytes==0;ratios=[];whites=[]
 for i in range(0,len(raw),frame_bytes):
  frame=raw[i:i+frame_bytes];dark=sum(1 for j in range(0,len(frame),3) if frame[j]<160 and frame[j+1]<180 and frame[j+2]<150 and frame[j+1]>=frame[j]+6);ratios.append(dark/(w*h));whites.append(sum(1 for j in range(0,len(frame),3) if min(frame[j:j+3])>200)/(w*h))
 lo=min(ratios);hi=max(ratios);assert lo<.35 and hi>.5,(name,lo,hi)
 candidates=[i for i in range(len(ratios)-2) if all(.5<ratios[j]<.95 and whites[j]>.04 for j in range(i,i+3)) and max(ratios[i:i+3])-min(ratios[i:i+3])<.01];assert candidates,(name,'no stable visible tick');peak=candidates[0]+2;out=O/(name+'-visible-tick.png')
 assert not out.exists()
 subprocess.run(['ffmpeg','-v','error','-i',str(O/(name+'.mp4')),'-vf',f'select=eq(n\\,{peak})','-frames:v','1',str(out)],check=True,timeout=30)
 results.append({'name':name,'native_tap_center':[cx,cy],'crop_xywh':crop,'decoded_frames':len(ratios),'minimum_dark_green_fraction':lo,'maximum_dark_green_fraction':hi,'selected_frame_index':peak,'dark_fraction_at_selected':ratios[peak],'light_fraction_at_selected':whites[peak],'method':'actual decoded crop occupancy and stable light tick on filled box; confirms visible marked/unmarked change, not absolute video/native-flag sync'})
(L/'pixel-proof-v2.json').write_text(json.dumps(results,indent=2)+'\n');print(json.dumps(results))
