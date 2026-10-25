"""Verify fixed inputs and separately scoped App, SAF and server evidence."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

folder = Path(__file__).resolve().parent
root = folder.parents[4]
manifest = json.loads((folder/'manifest.json').read_text())
source = json.loads((folder/'source.json').read_text())
for name, digest in manifest['inputs'].items():
    assert hashlib.sha256((folder/name).read_bytes()).hexdigest() == digest, name
for name, digest in source['files'].items():
    assert hashlib.sha256((root/name).read_bytes()).hexdigest() == digest, name
    raw = subprocess.check_output(['git','show',source['commit']+':'+name],cwd=root)
    assert hashlib.sha256(raw).hexdigest() == digest, name
for ref in ('HEAD','design-lf-2026-10-23'):
    actual = subprocess.check_output(['git','rev-parse',ref+':design/reference/library-first'],cwd=root,text=True).strip()
    assert actual == '1cbf605af8f03fa067a4ce8e914bb809e3a487ca'
for ref in (source['commit'],source['server_full_started_at']):
    assert subprocess.check_output(['git','rev-parse',ref+':services/server'],cwd=root,text=True).strip()==source['server_tree']
server = (folder/'server-full.log').read_text()
assert re.search(r'\b398 passed, 1 warning in ',server)
assert not re.search(r'^FAILED |^ERROR |^=+ FAILURES ',server,re.M)
client = (folder/'client-full.log').read_text()
assert re.search(r'\+433: All tests passed!',client) and not re.search(r'\+\d+ -\d+:',client)
assert 'No issues found!' in (folder/'analyze.log').read_text()
assert (folder/'ruff.log').read_text().strip() == 'All checks passed!'
assert 'VV_COMPILE_OK 127' in (folder/'compile.log').read_text()
for n in range(1,4):
    base = folder/f'app-{n}'
    result = json.loads((base/'result.json').read_text())
    assert result['source'] == source['commit'] and result['exit_code'] == 0
    assert result['viewport'] == ([360,740] if n==1 else [390,844])
    assert result['font_scale'] == (2 if n==1 else 1)
    log = (base/'flutter.log').read_text()
    assert 'ARCHIVE_APP_VERIFIED:roots=27,epoch_changed=true,snapshot=' in log and 'All tests passed!' in log
    assert len(list(base.glob('*.png'))) == 5
    assert json.loads((base/'media-before.json').read_text()) == json.loads((base/'media-after.json').read_text())
    requests = json.loads((base/'requests.json').read_text())
    for path in ('/api/v1/auth/login','/api/v1/management-backups',
                 '/api/v1/management-backups/imports','/api/v1/management-backups/restores'):
        assert sum(v['method']=='POST' and v['path']==path for v in requests)==1, (n,path)
    assert sum(v['method']=='POST' and '/from-snapshot/' in v['path'] for v in requests)==1
    assert any(v['method']=='GET' and v['path'].endswith('/roots') and v['query'].get('offset')=='24' for v in requests)
    saved = json.loads((base/'restored-viewport.json').read_text())
    assert saved['before']==saved['after'] and saved['before_font']==saved['after_font']
    base = folder/f'saf-{n}'
    result = json.loads((base/'result.json').read_text())
    assert result['exit_code']==0 and result['stages']==['cancel-save','save-large','cancel-pick','pick-large','pick-over-limit','programmatic-cancel']
    assert result['sha256']=='c5546c34a17fb13781fa3267ee1d3f3b4f4c6bdb654d1f9ca6b1d65d37acf161'
    assert (base/'saved-sha256.txt').read_text().split()[0] == result['sha256']
    log = (base/'flutter.log').read_text()
    assert 'SAF_VERIFIED:bytes=42008576,sha256='+result['sha256'] in log and 'All tests passed!' in log
print(json.dumps({'verified':True,'source':source['commit'],'client_tests':433,'server_tests':398,
                  'native_app_rounds':3,'native_saf_rounds':3,'native_file_bytes':42008576},indent=2))
