import json,xml.etree.ElementTree as ET,subprocess
from pathlib import Path
from PIL import Image,ImageChops
L=Path(__file__).resolve().parent;O=L/'normal/screens';base=next(O.glob('*-pinch-v3-baseline-page-three.png'));crop=(0,315,1170,2160);reference=Image.open(base).convert('RGB').crop(crop);proof=[]
for i in [1,2,3]:
 row={'round':i}
 for state in ['zoomed','panned','back-reset']:
  p=next(O.glob(f'*-pinch-v3-round-{i}-{state}.png'));nodes=list(ET.parse(p.with_suffix('.xml')).iter('node'));labels=[n.get('content-desc') or n.get('text') for n in nodes];assert '返回来源' in labels and '阅读设置' in labels and '3 / 6' in labels
  picture=Image.open(p).convert('RGB').crop(crop);diff=ImageChops.difference(reference,picture);mask=diff.convert('L').point(lambda n:255 if n>4 else 0);changed=sum(mask.histogram()[1:])/(mask.width*mask.height);row[state+'_changed_fraction_vs_fit']=changed
  if state=='back-reset':assert changed<.001
  else:assert changed>.15
  service=json.loads((L/f'pinch-v3-round-{i}-{state}-reader-service.json').read_text());before=json.loads((L/'pinch-v3-before-reader-service.json').read_text());assert service['progress']==before['progress'];row[state+'_progress_unchanged']=True
 proof.append(row)
subprocess.run(['ffmpeg','-v','error','-i',str(L/'pinch-v3.mp4'),'-f','null','-'],check=True,timeout=45)
(L/'pinch-v3-pixel-proof.json').write_text(json.dumps({'complete':True,'crop':crop,'frames':proof,'reader_present_at_all_9_states':True,'full_progress_objects_equal':True,'full_recording_decode_exit':0},indent=2)+'\n');print(json.dumps(proof))
