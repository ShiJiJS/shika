import json,struct,zlib,hashlib,sys
from pathlib import Path
L=Path(__file__).resolve().parent;root=L.parents[1];target=root/'.dev/lf8-preview18-native/media/packs-a/05-patterns'
assert target.exists();assert sorted(p.name for p in target.iterdir())==['1-tall.png','2-wide.png','3-portrait.png','4-landscape.png','5-square.png']
def chunk(t,d):return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d))
manifest=[]
for name,w,h in [('1-tall.png',600,6000),('2-wide.png',6000,600),('3-portrait.png',1600,2400),('4-landscape.png',2400,1600),('5-square.png',8000,8000)]:
 p=target/name;c=zlib.compressobj(6)
 with p.open('wb') as f:
  f.write(b'\x89PNG\r\n\x1a\n');f.write(chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0)))
  rowcache={}
  for y in range(h):
   band=y//max(1,h//24)
   key=(band,y%max(1,h//24)<max(1,h//600))
   if key not in rowcache:
    row=bytearray()
    for x in range(w):
     col=x//max(1,w//12);edge=x%(max(1,w//12))<max(1,w//300) or y%(max(1,h//24))<max(1,h//600)
     row.extend((30,35,40) if edge else ((45+col*17)%230,(70+band*23)%230,(140+col*11+band*7)%230))
    rowcache[key]=b'\0'+bytes(row)
   data=c.compress(rowcache[key])
   if data:f.write(chunk(b'IDAT',data))
  f.write(chunk(b'IDAT',c.flush()));f.write(chunk(b'IEND',b''))
 manifest.append({'relative_path':str(p.relative_to(root)), 'width':w,'height':h,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(L/'added-pattern-fixture.json').write_text(json.dumps({'private_media':False,'purpose':'synthetic visible grid; no NAS/media changes; not photo performance','files':manifest},indent=2)+'\n');print({'created_test_files':len(manifest),'dimensions':[[v['width'],v['height']] for v in manifest]})
