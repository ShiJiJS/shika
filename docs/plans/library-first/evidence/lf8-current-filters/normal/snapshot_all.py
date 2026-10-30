"""Snapshot every business table from the live owning container, read only."""
import json,subprocess,sys
from pathlib import Path
L=Path(__file__).resolve().parent
CODE='''import sqlite3,json,hashlib,time
c=sqlite3.connect('file:/data/library.sqlite3?mode=ro',uri=True,timeout=5);c.row_factory=sqlite3.Row;c.execute('BEGIN')
names=[r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")];tables={};opaque={};settings={}
for n in names:
 rows=sorted([dict(r) for r in c.execute('SELECT * FROM "'+n.replace('"','""')+'"')],key=lambda r:json.dumps(r,sort_keys=True));canonical=json.dumps(rows,sort_keys=True)
 if n in ['access_tokens','settings']:opaque[n]={'rows':len(rows),'sha256':hashlib.sha256(canonical.encode()).hexdigest()}
 else:tables[n]=rows
 if n=='settings':settings={r['key']:hashlib.sha256(r['value'].encode()).hexdigest() for r in rows}
c.rollback();c.close();print(json.dumps({'tables':tables,'opaque_table_digests':opaque,'setting_key_sha256':settings,'observed_at':time.time()},indent=2))'''
def snapshot(kind,name):
 m=json.loads((L/'runtime.json').read_text());raw=subprocess.check_output(['docker','exec',m['container'],'python','-c',CODE],timeout=20);p=L/(name+'-all-catalog.json');assert not p.exists();p.write_bytes(raw);v=json.loads(raw);print(json.dumps({'snapshot':name,'kind':kind,'tables':len(v['tables']),'counts':{k:len(x) for k,x in v['tables'].items()}}));return v
if __name__=='__main__':snapshot(sys.argv[1],sys.argv[2])
