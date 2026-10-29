import json,subprocess,sqlite3,hashlib
from pathlib import Path
L=Path(__file__).resolve().parent;R=L.parents[1];O=L/'normal';runtime=json.loads((O/'runtime.json').read_text());donor=Path(runtime['donor']);data=(donor/'data').resolve()
ids=subprocess.check_output(['docker','ps','-q'],text=True).split()
for c in json.loads(subprocess.check_output(['docker','inspect',*ids])):
 for m in c['Mounts']:
  p=Path(m['Source']).resolve();assert not(p==data or p in data.parents or data in p.parents),(c['Name'],str(p))
assert not any(x.stat().st_size for x in data.glob('*-wal'))
for rel,sha in runtime['donor_hashes'].items():assert hashlib.sha256((data/rel).read_bytes()).hexdigest()==sha
c=sqlite3.connect((data/'library.sqlite3').as_uri()+'?mode=ro&immutable=1',uri=True);c.row_factory=sqlite3.Row
rows=[dict(r) for r in c.execute('SELECT * FROM settings')];c.close()
def canon(v):return json.dumps(sorted(v,key=lambda r:json.dumps(r,sort_keys=True)),sort_keys=True)
base=json.loads((O/'before-business-catalog.json').read_text());donor_matches_prebusiness=hashlib.sha256(canon(rows).encode()).hexdigest()==base['opaque_table_digests']['settings']['sha256']
scan_code="import sqlite3,json;c=sqlite3.connect('file:/data/library.sqlite3?mode=ro',uri=True);print(json.dumps(c.execute(\"SELECT value FROM settings WHERE key='pack_root_scan_v1:packs'\").fetchone()[0]));c.close()"
scan=json.loads(subprocess.check_output(['docker','exec','video-viewer-menu-dropdown-normal','python','-c',scan_code]))
reconstructed=[{**r,'value':scan} if r['key']=='pack_root_scan_v1:packs' else r for r in rows]
assert hashlib.sha256(canon(reconstructed).encode()).hexdigest()==base['opaque_table_digests']['settings']['sha256'],'unexpected pre-business setting difference'
before={r['key']:hashlib.sha256(r['value'].encode()).hexdigest() for r in rows}
code="import sqlite3,json,hashlib;c=sqlite3.connect('file:/data/library.sqlite3?mode=ro',uri=True);c.execute('BEGIN');print(json.dumps({k:hashlib.sha256(v.encode()).hexdigest() for k,v in c.execute('SELECT key,value FROM settings')}));c.rollback();c.close()"
after=json.loads(subprocess.check_output(['docker','exec','video-viewer-menu-dropdown-normal','python','-c',code]));changed=sorted(k for k in before.keys()|after.keys() if before.get(k)!=after.get(k));print(json.dumps({'donor_matches_prebusiness':donor_matches_prebusiness,'changed_keys':changed,'donor_keys':sorted(before)}));assert set(changed)<={'reader_defaults','active_pack_session','active_pack_opened','active_round','pack_root_scan_v1:packs'},changed
v={'donor_matches_prebusiness_digest':donor_matches_prebusiness,'prebusiness_reconstructed_only_startup_scan_marker':True,'donor_mount_guard_and_12_hashes':True,'before_per_key_sha256':before,'after_per_key_sha256':after,'changed_keys':changed};(L/'settings-delta-audit.json').write_text(json.dumps(v,indent=2)+'\n');print(json.dumps({'changed_setting_keys':changed}))
