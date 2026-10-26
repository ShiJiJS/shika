"""Read-only verification: current checks and a distinctly labelled native stage."""
import hashlib
import json
import subprocess
from pathlib import Path
from PIL import Image
H=Path(__file__).resolve().parent
R=H.parents[4]
def read(p):return json.loads(p.read_text())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def git(*a):return subprocess.check_output(['git',*a],cwd=R,text=True).strip()
contract=read(H/'source.json');manifest=read(H/'manifest.json')
for p,h in manifest.items():
 assert sha(H/p)==h,p
 git('ls-files','--error-unmatch',str((H/p).relative_to(R)))
for tree,key in [('apps/mobile/lib','current_lib_tree'),('apps/mobile/test','current_test_tree'),('services/server/video_viewer','server_tree')]:
 assert git('rev-parse','HEAD:'+tree)==contract[key]==git('rev-parse',contract['current_commit']+':'+tree)
assert git('rev-parse','HEAD:design/reference/library-first')==contract['prototype_tree']=='1cbf605af8f03fa067a4ce8e914bb809e3a487ca'
for f in read(H/'reference/served-source.json'):
 assert f['status']==200 and sha(R/'design/reference/library-first'/f['path'])==f['sha256']
run=H/'stage-normal';source=read(run/'source.json');result=read(run/'result.json');metrics=read(run/'metrics.json');requests=read(run/'requests.json');db=read(run/'database.json');log=(run/'flutter.log').read_text()
assert source['commit']==contract['native_commit']!=contract['current_commit']
for p,h in source['files'].items():
 assert hashlib.sha256(subprocess.check_output(['git','show',source['commit']+':'+p],cwd=R)).hexdigest()==h,p
assert result['passed'] and len(metrics)==15 and result['screens']==[m['state'] for m in metrics]
for m in metrics:
 assert m['size']==[390,844] and m['textScale']==1
 assert Image.open(run/(m['state']+'.png')).size==(1170,2532)
 assert any('mCurrentFocus=' in l and 'io.github.shijijs.video_viewer' in l for l in (run/(m['state']+'-window.txt')).read_text().splitlines())
assert 'All tests passed!' in log and 'RECENT_HISTORY_ERROR:' not in log
before=read(run/'media-before.json');assert len(before)==26 and before==read(run/'media-after.json')
restore=read(run/'restored-viewport.json');assert restore['before']==restore['after'] and restore['font_before']==restore['font_after'] and not restore['errors']
p=json.loads(next(l.split('RECENT_HISTORY_VERIFIED:',1)[1] for l in log.splitlines() if l.startswith('RECENT_HISTORY_VERIFIED:')))
assert p['before_retry']==p['after_retry'] and p['before_retry']['page_index']==2 and p['recent_video_entries']==1
assert len(db['recent'])==4 and len(db['rounds'])==3 and len(db['sessions'])==3
assert sorted(s['candidate_count'] for s in db['sessions'])==[1,1,2]
assert json.loads(next(s for s in db['sessions'] if s['id']==p['recent_pack_range'])['source'])['kind']=='recent'
for endpoint in ['/api/v1/videos','/api/v1/packs']:
 rows=[r for r in requests if r['path']==endpoint and dict(r.get('query',[])).get('source')=='recent' and dict(r['query']).get('limit')!='1']
 assert any(r['status']==503 for r in rows) and any(r['status']==200 for r in rows)
 assert all(not dict(r['query']).get('search','') for r in rows)
assert '+516: All tests passed!' in (H/'checks/client.log').read_text()
assert '26 passed' in (H/'checks/server.log').read_text()
assert 'No issues found!' in (H/'checks/analyze.log').read_text()
assert 'All checks passed!' in (H/'checks/ruff.log').read_text()
recovery=read(H/'diagnostics/dev-landscape-v3/recovery.json')
assert recovery['same_avd_pid']==44007 and any(r.get('timeout') for r in recovery['actions'])
assert any(r.get('owned_container_removed') and r['code']==0 for r in recovery['actions'])
assert '未验证' in (H/'review/independent-review.md').read_text()
print(json.dumps({'verified':True,'scope':'stage-only; current native acceptance pending','native_source':source['commit'],'current_source':contract['current_commit'],'stage_screens':15,'client':516,'related_server':26,'manifest_inputs':len(manifest)},ensure_ascii=False))
