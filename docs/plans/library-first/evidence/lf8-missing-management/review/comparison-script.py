import json
from pathlib import Path
from PIL import Image, ImageDraw
out=Path('/tmp/lf8-missing-review/final');out.mkdir(exist_ok=True)
records=[]
for profile in ['normal','large','landscape']:
    root=Path('/tmp/lf8-missing-v2-final-'+profile)
    log=root/'lf7-roots-missing-android-test.log'
    if not log.exists(): continue
    metrics=[json.loads(l.split('MISSING_METRICS:',1)[1]) for l in log.read_text().splitlines() if 'MISSING_METRICS:' in l]
    for state,ref in [('missing-paged','missing'),('missing-empty-video','empty'),('missing-confirm-cancel','confirm')]:
        if not (root/f'lf7-roots-missing-{state}.png').exists():continue
        m=next(x for x in metrics if x['state']==state)
        im=Image.open(root/f'lf7-roots-missing-{state}.png').convert('RGB');d=m['dpr'];top,bottom=m['viewPadding'][1],m['viewPadding'][3]
        im=im.crop((0,round(top*d),im.width,im.height-round(bottom*d)))
        im=im.resize((round(im.width/d),round(im.height/d)),Image.Resampling.LANCZOS)
        im.save(out/f'{profile}-{state}-logical.png')
        if profile=='large':continue
        ref_path=Path('/tmp/lf8-missing-reference')/((ref+'-landscape' if profile=='landscape' and ref=='missing' else ref)+'.png')
        if profile=='landscape' and ref!='missing':continue
        reference=Image.open(ref_path).convert('RGB')
        sheet=Image.new('RGB',(reference.width+im.width+16,max(reference.height,im.height)+28),'#dddeda');draw=ImageDraw.Draw(sheet)
        sheet.paste(reference,(0,28));sheet.paste(im,(reference.width+16,28));draw.text((8,8),'Frozen browser reference',fill='black');draw.text((reference.width+24,8),'Current native safe area (different catalog)',fill='black');sheet.save(out/f'{profile}-{state}-comparison.png')
        records.append({'source_commit':json.loads((root/'source.json').read_text())['commit'],'profile':profile,'state':state,'dpr':d,'safe_top':top,'safe_bottom':bottom,'native_size':list(im.size),'reference_size':list(reference.size),'method':'Actual safe-area crop; proportional DPR-only downsample; neutral padding. No element movement or stretching.'})
(out/'normalization.json').write_text(json.dumps(records,indent=2)+'\n')
