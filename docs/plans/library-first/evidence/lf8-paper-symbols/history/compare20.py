import json
from pathlib import Path
from PIL import Image,ImageChops
L=Path(__file__).resolve().parent;S=L/'normal/screens';O=L/'compare20';O.mkdir(exist_ok=True)
def screenshot(pattern):
 matches=list(S.glob('*-'+pattern+'.png'));assert len(matches)==1,pattern;return matches[0]
def native(path):
 with Image.open(path) as im:
  assert im.size==(1170,2715);return im.convert('RGB').crop((0,147,1170,2643)).resize((390,832),Image.Resampling.LANCZOS)
rows=[]
for scene in ['home','reader']:
 old=screenshot('baseline18-'+scene+'-light');new=screenshot('candidate20-'+scene+'-light')
 ref=Path('docs/plans/library-first/evidence/lf8-integrated-baseline/reference')/('home.png' if scene=='home' else 'reader-content832.png')
 r=Image.open(ref).convert('RGB');r=r.crop((0,0,390,832))
 a,b=native(old),native(new)
 pair=Image.new('RGB',(1170,832));pair.paste(r,(0,0));pair.paste(a,(390,0));pair.paste(b,(780,0));pair.save(O/(scene+'-reference-before-after.png'))
 if scene=='reader':
  old_canvas=Image.open(old).convert('RGB').crop((0,315,1170,2160));new_canvas=Image.open(new).convert('RGB').crop((0,315,1170,2160));assert ImageChops.difference(old_canvas,new_canvas).getbbox() is None
 rows.append({'scene':scene,'before':str(old.relative_to(L)),'after':str(new.relative_to(L)),'reference':str(ref),'native_crop':[0,147,1170,2643],'native_resample':1/3,'html_reader_not_cropped':scene=='reader','panel_order':['reference','code18','code20'],'reader_canvas_identical':scene=='reader'})
(O/'geometry.json').write_text(json.dumps(rows,indent=2)+'\n')
print(json.dumps(rows))
