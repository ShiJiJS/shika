import hashlib,json,subprocess,urllib.request
from pathlib import Path
L=Path(__file__).resolve().parent;R=L.parents[1];O=L/'normal';meta=json.loads((O/'runtime.json').read_text());actual={}
for kind,expected in meta['public_media_sha256'].items():
 root=O/kind;v={str(x.relative_to(root)):hashlib.sha256(x.read_bytes()).hexdigest() for x in sorted(root.rglob('*')) if x.is_file()};assert v==expected;actual[kind]=v
assert sum(len(x) for x in actual.values())==215
old={}
for ver,kind,sha in [('0.2.0-preview.14','normal','6d56fc8741cdff22daa3bea24f5bbf3fd86b3a29865620625e077a7683ba2769'),('0.1.4-rollback.14','rollback','72e36c4b1510500cd343b094aaf61c1325a2dac2d20287cf80edd774e9909c81'),('0.2.0-preview.15','normal','6f434977f50ff28f46d8b6297b6a3e6e4f1bd16ed6afa330cbe030fd232037dd'),('0.1.4-rollback.15','rollback','6c6b62db24cc3a1a083382cc27b1ac6e3649c907731996806cbe2b0ae1f0ac24')]:
 p=R/'tmp/releases'/('video-viewer-'+ver+'-arm64.apk');assert hashlib.sha256(p.read_bytes()).hexdigest()==sha;old[p.name]=sha
(L/'integrity-final.json').write_text(json.dumps({'source_media_files':215,'all_source_hashes_preserved':True,'source_sha256':actual,'old_packages_preserved':old,'prototype_tree':subprocess.check_output(['git','rev-parse','HEAD:design/reference/library-first'],cwd=R,text=True).strip()},indent=2)+'\n');print('source media and previous package pairs preserved')
