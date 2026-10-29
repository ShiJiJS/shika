"""Read guarded inactive copies; compare hashes without publishing values."""
import hashlib,json,sqlite3,subprocess
from pathlib import Path
O=Path(__file__).resolve().parent;D=O.parents[1]/'lf8-overlays-motion/normal'
mounts=[m['Source'] for c in json.loads(subprocess.check_output(['docker','inspect',*subprocess.check_output(['docker','ps','-q'],text=True).split()])) for m in c['Mounts']]
rows=[]
for p in [D/'data/library.sqlite3',O/'data/library.sqlite3']:
 assert not any(p.is_relative_to(Path(m)) for m in mounts)
 w=Path(str(p)+'-wal');assert not w.exists() or w.stat().st_size==0
 c=sqlite3.connect('file:'+str(p)+'?mode=ro&immutable=1',uri=True);c.row_factory=sqlite3.Row;rows.append([dict(v) for v in c.execute('select * from settings')]);c.close()
b,a=rows
def digest(v):return hashlib.sha256(json.dumps(sorted(v,key=lambda r:json.dumps(r,sort_keys=True)),sort_keys=True).encode()).hexdigest()
assert digest(a)==json.loads((O/'after-real-undo-catalog.json').read_text())['opaque_table_digests']['settings']['sha256']
# The production logical trash removes only its active-opened marker and
# persists last-delete ID. Reconstruct the observed BEFORE hash, not merely count.
reconstructed=[r for r in a if r['key']!='last_pack_delete_operation']+[r for r in b if r['key']=='active_pack_opened']
assert digest(reconstructed)==json.loads((O/'before-real-undo-catalog.json').read_text())['opaque_table_digests']['settings']['sha256']
marker=next(r['value'] for r in a if r['key']=='last_pack_delete_operation')
tasks=json.loads((O/'after-real-undo-catalog.json').read_text())['tables']['tasks']
assert any(t['kind']=='pack_trash' and t['id']==marker for t in tasks)
(O/'actual-undo-settings-result.json').write_text(json.dumps({'complete':True,'mode':'guarded inactive mode=ro&immutable=1','before_settings_sha256_reconstructed_exactly':digest(reconstructed),'after_settings_sha256':digest(a),'only_operation_settings_changes':['active_pack_opened removed','last_pack_delete_operation added'],'startup_scan_marker_same_during_action':True,'values_not_published':True},indent=2)+'\n')
print('Exact before/after settings accounted for; no command replay')
