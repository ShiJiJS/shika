#!/usr/bin/env python3
"""Use the existing Ego page; rasterize only public frozen SVGs outside reference."""

import argparse
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument("--space", type=int, required=True)
p.add_argument("--page", required=True)
p.add_argument("--output", type=Path, required=True)
args = p.parse_args()
source = (ROOT / "design/reference/library-first/runtime/prototype.js").read_text()
packs = json.loads(source[source.index("[") : source.index("\n];") + 2])
assert [pack["id"] for pack in packs] == ["summer", "field", "newyear", "kimono"]
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=False)
(out / "raster").mkdir()
(out / "reference").mkdir()
(out / "packs.json").write_text(json.dumps(packs, ensure_ascii=False, indent=2) + "\n")
script = """
const fs=await import('node:fs/promises');
const task=await taskSpace(SPACE), page=task.page(PAGE);
const out=OUTPUT, packs=PACKS;
const scenes=['home','packs','video-tags','pack-tags','settings','settings-bottom','dark','dark-bottom'];
const all=[];
for(const state of scenes){
 await page.cdp('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:false});
 await page.goto('http://127.0.0.1:8767/library-first/app.html?snapshot=1'+(state==='home'?'':'&state='+state.replace('-bottom','')));
 await page.waitForFunction(()=>document.querySelector('.app') && document.fonts.status==='loaded' && [...document.images].every(i=>i.complete&&i.naturalWidth>0));
 if(state.endsWith('-bottom'))await page.evaluate(()=>{const e=document.querySelector('.settings-page');e.scrollTop=e.scrollHeight;});
 await page.evaluate(async()=>{await Promise.all(document.getAnimations().filter(a=>Number.isFinite(a.effect?.getTiming().iterations)).map(a=>a.finished.catch(()=>{})));});
 const metrics=await page.evaluate(()=>({size:[innerWidth,innerHeight],dpr:devicePixelRatio,fontStatus:document.fonts.status,
  regions:[...document.querySelectorAll('.app,header,nav,section,h1,h2,h3,.kindbar,.search-row,.librarybar,.tile-cover,.home-indicator')].flatMap(e=>{const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width&&r.height?[{tag:e.tagName,class:e.className,text:(e.textContent||'').trim().slice(0,70),rect:[r.x,r.y,r.width,r.height],fontSize:s.fontSize,fontFamily:s.fontFamily}]:[]})}));
 if(metrics.size[0]!==390||metrics.size[1]!==844||metrics.dpr!==1) throw Error('Wrong actual viewport');
 await page.screenshot({path:out+'/reference/'+state+'.png'});
 all.push({state,...metrics});
}
const raster=await page.evaluate(async(packs)=>{const output=[];for(const p of packs)for(const path of p.pages){
 const im=new Image();im.src=new URL(path,location.href).href;await im.decode();
 const s=Math.min(1,900/Math.max(im.naturalWidth,im.naturalHeight));
 const c=document.createElement('canvas');c.width=Math.round(im.naturalWidth*s);c.height=Math.round(im.naturalHeight*s);
 c.getContext('2d').drawImage(im,0,0,c.width,c.height);
 output.push({file:path.split('/').pop().replace('.svg','.png'),width:c.width,height:c.height,data:c.toDataURL('image/png').split(',')[1]});
}return output;},packs);
for(const r of raster)await fs.writeFile(out+'/raster/'+r.file,Buffer.from(r.data,'base64'));
await fs.writeFile(out+'/reference/metrics.json',JSON.stringify(all,null,2)+'\\n');
await fs.writeFile(out+'/raster/dimensions.json',JSON.stringify(raster.map(({data,...r})=>r),null,2)+'\\n');
console.log({space:task.spaceId,page:page.label,states:all.map(s=>s.state),rasterized:raster.length});
"""
for key, value in {
    "SPACE": args.space,
    "PAGE": args.page,
    "OUTPUT": str(out),
    "PACKS": packs,
}.items():
    script = script.replace(key, json.dumps(value, ensure_ascii=False))
subprocess.run(
    ["ego-browser", "nodejs"], input=script, text=True, check=True, timeout=120
)
