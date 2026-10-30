import hashlib,json,subprocess
from pathlib import Path
L=Path(__file__).resolve().parent;R=L.parents[1];O=L/'normal';meta=json.loads((O/'runtime.json').read_text());actual={}
for kind,expected in meta['public_media_sha256'].items():
 root=O/kind;v={str(x.relative_to(root)):hashlib.sha256(x.read_bytes()).hexdigest() for x in sorted(root.rglob('*')) if x.is_file()};assert v==expected;actual[kind]=v
build=json.loads((R/'.dev/lf8-current-filters/build-1/result.json').read_text())
for kind in ['forward','rollback']:assert hashlib.sha256(Path(build[kind]['path']).read_bytes()).hexdigest()==build[kind]['sha256']
source=build['source'];head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=R,text=True).strip();lib=lambda r:subprocess.check_output(['git','rev-parse',r+':apps/mobile/lib'],cwd=R,text=True).strip();assert lib(head)==lib(source)
(L/'integrity-final.json').write_text(json.dumps({'source_media_files':sum(len(x) for x in actual.values()),'source_sha256':actual,'source_hashes_unchanged':True,'app_source':source,'head':head,'same_lib_tree':lib(head),'normal_apk_sha256':build['forward']['sha256'],'rollback_apk_sha256':build['rollback']['sha256'],'apk_pair_unchanged':True,'prototype_tree':subprocess.check_output(['git','rev-parse','HEAD:design/reference/library-first'],cwd=R,text=True).strip()},indent=2)+'\n');print('215 public sources, both APKs and production lib verified')
