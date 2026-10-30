import json
from pathlib import Path
from PIL import Image
L=Path(__file__).resolve().parent;S=L/'normal/screens'
def one(pattern):
 values=list(S.glob('*-'+pattern+'.png'));assert len(values)==1;return values[0]
a=Image.open(one('candidate19-home-dark')).convert('RGB');b=Image.open(one('candidate20-home-dark')).convert('RGB');assert a.size==b.size==(1170,2715)
values=[]
# Both211dp covers start at nativey768. Sample inside the34dp circular
# overlay, outside the centered20dp glyph; no image/component is moved.
for x,y in [(347,1085),(902,1085)]:
 old=a.getpixel((x,y));new=b.getpixel((x,y));assert min(old)>160 and max(new)<90,(x,y,old,new);values.append({'point':[x,y],'code19':old,'code20':new})
(L/'dark-play-pixels.json').write_text(json.dumps({'points':values,'old_light_overlay_replaced_by_dark_overlay_on_both_videos':True},indent=2)+'\n');print(json.dumps(values))
