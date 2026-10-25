"""Verify fixed native inputs, original SQLite and absence of command writes."""
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import struct
import subprocess

folder = Path(__file__).resolve().parent
root = folder.parents[4]
read = lambda name: json.loads((folder / name).read_text())
source, setup, manifest = read('source.json'), read('setup.json'), read('manifest.json')
for name, digest in manifest['inputs'].items():
    assert hashlib.sha256((folder / name).read_bytes()).hexdigest() == digest, name
    subprocess.check_output(['git','ls-files','--error-unmatch',str((folder/name).relative_to(root))],cwd=root)
for name, digest in source['files'].items():
    assert hashlib.sha256((root/name).read_bytes()).hexdigest() == digest, name
    raw = subprocess.check_output(['git','show',source['commit']+':'+name],cwd=root)
    assert hashlib.sha256(raw).hexdigest() == digest, name
for ref in ('HEAD',source['commit'],source['client_full_started_at']):
    for name,key in [('apps/mobile/lib','app_lib_tree'),('apps/mobile/test','app_test_tree')]:
        assert subprocess.check_output(['git','rev-parse',ref+':'+name],cwd=root,text=True).strip() == source[key]
for ref in ('HEAD',source['commit'],source['server_full_started_at']):
    assert subprocess.check_output(['git','rev-parse',ref+':services/server'],cwd=root,text=True).strip() == source['server_tree']
for ref in ('HEAD',source['commit'],'design-lf-2026-10-23'):
    assert subprocess.check_output(['git','rev-parse',ref+':design/reference/library-first'],cwd=root,text=True).strip() == '1cbf605af8f03fa067a4ce8e914bb809e3a487ca'
client, server = (folder/'client-full.log').read_text(), (folder/'server-full.log').read_text()
assert re.search(r'\+451: All tests passed!',client) and not re.search(r'\+\d+ -\d+:',client)
assert re.search(r'\b402 passed, 1 warning in ',server) and not re.search(r'^FAILED |^ERROR |^=+ FAILURES ',server,re.M)
assert 'No issues found!' in (folder/'analyze.log').read_text()
assert (folder/'ruff.log').read_text().strip() == 'All checks passed!'
assert 'PYTHON_SYNTAX_OK 132' in (folder/'compile.log').read_text()
formatting = read('format-comparison.json')
assert formatting['current']['files'] == formatting['baseline']['files'] and len(formatting['current']['files']) == 23
assert not formatting['new_unformatted']
dart_formatting = read('dart-format-comparison.json')
assert len(dart_formatting['inherited_unformatted']) == 2
for name, refs in dart_formatting['inherited_unformatted'].items():
    assert len(set(refs.values())) == 1
    for ref, digest in refs.items():
        assert subprocess.check_output(['git','rev-parse',ref+':'+name],cwd=root,text=True).strip() == digest

bundle = folder/'original-history-bundle'
with sqlite3.connect((bundle/'index.sqlite3').as_uri()+'?mode=ro&immutable=1',uri=True) as db:
    graphs = db.execute('SELECT identity,filename,digest FROM history_graphs').fetchall()
    assert len(graphs) == 2
    for identity,filename,digest in graphs:
        assert hashlib.sha256((bundle/filename).read_bytes()).hexdigest() == digest
    graph_file = next(filename for identity,filename,_ in graphs if identity == setup['graph_id'])
with sqlite3.connect((bundle/graph_file).as_uri()+'?mode=ro&immutable=1',uri=True) as db:
    kind,status,raw = db.execute('SELECT kind,status,result FROM tasks WHERE id=?',(setup['purge_id'],)).fetchone()
    assert kind == 'pack_permanent' and status == 'completed'
    counters = json.loads(raw)
    assert [counters[k] for k in ('total','succeeded','failed','pages_total','pages_deleted')] == [27,26,1,153,126]
    assert db.execute('SELECT plan_id FROM pack_purge_executions WHERE id=?',(setup['purge_id'],)).fetchone()[0] == setup['plan_id']
    assert db.execute('SELECT count(*),sum(image_count) FROM pack_purge_entries WHERE plan_id=?',(setup['plan_id'],)).fetchone() == (27,153)
    raw,count = db.execute('SELECT manifest,image_count FROM pack_purge_entries WHERE plan_id=? AND trash_id=?',(setup['plan_id'],setup['large_member']['trash_id'])).fetchone()
    files = json.loads(raw)['files']
    assert len(files) == count == 127 and files[100]['relative_path'] == '0101.png' and files[-1]['relative_path'] == '0127.png'
    assert db.execute("SELECT s.relative_path,s.error FROM pack_purge_steps s JOIN pack_file_steps p ON p.id=s.parent_id WHERE p.operation_id=? AND s.kind='image' AND s.outcome='failed'",(setup['purge_id'],)).fetchall() == [('0101.png','permission_denied')]
    assert db.execute('SELECT count(*) FROM pack_purge_steps s JOIN pack_file_steps p ON p.id=s.parent_id WHERE p.operation_id=?',(setup['purge_id'],)).fetchone()[0] == 207

names = {'history-original-partial','history-query-error-kept-page','history-result-next-page','history-directory-results','history-last-three-packs','history-last-image-page','history-original-preview'}
rounds = []
media_previous = history_previous = None
for n in range(1,4):
    base = folder/f'round-{n}'
    value = lambda name: json.loads((base/name).read_text())
    result = value('result.json')
    assert result['source'] == source['commit'] and result['source_files'] == source['files']
    assert result['viewport'] == ([360,740] if n==1 else [390,844]) and result['scale'] == (2 if n==1 else 1)
    assert result['exit_code'] == 0 and set(result['screens']) == names and len(result['screens']) == 7
    verified = result['verified']
    assert all(verified[k] == setup[k] for k in ('graph_id','plan_id','purge_id'))
    assert verified['packs'] == 27 and verified['images_in_large_pack'] == 127 and verified['journals_unchanged']
    assert 'All tests passed!' in (base/'flutter.log').read_text() and 'HISTORY_PURGE_VERIFIED:' in (base/'flutter.log').read_text()
    media, history = value('media-before.json'), value('history-before.json')
    assert media == value('media-after.json') and history == value('history-after.json')
    assert len(media) == setup['source_files_expected'] == 54
    if media_previous is not None:
        assert media == media_previous and history == history_previous
    media_previous,history_previous = media,history
    for i in range(1,128):
        assert ('packs/原图包 00/'+f'{i:04d}.png' in media) == (i>=101)
    assert len([v for v in media if v.endswith('.txt')]) == 27
    prefix = 'management-history/'+setup['restore_id']+'/bundle/'
    for p in bundle.glob('*.sqlite3'):
        assert history[prefix+p.name]['sha256'] == hashlib.sha256(p.read_bytes()).hexdigest()
    restored = value('restored-viewport.json')
    assert restored['before'] == restored['after'] and restored['before_font'] == restored['after_font'] and not restored['watcher_errors']
    requests = value('requests.json')
    writes = [v for v in requests if v['method'] != 'GET']
    assert sum(v['path']=='/api/v1/auth/login' and v['method']=='POST' for v in writes) == 1
    assert all(v['method']=='POST' and v['path'] in ('/api/v1/auth/login','/api/v1/scan') for v in writes)
    original_reads = [v for v in requests if v['path'].startswith('/api/v1/management-history/tasks/')]
    assert original_reads and all(v['query'].get('graph_id') == setup['graph_id'] and v['method']=='GET' for v in original_reads)
    failures = [v for v in original_reads if v['status']==503]
    assert len(failures)==1 and failures[0]['path'].endswith('/purge-pages') and failures[0]['query']['offset']=='24'
    at = requests.index(failures[0])
    assert any(v['path']==failures[0]['path'] and v['query']==failures[0]['query'] and v['status']==200 for v in requests[at+1:])
    assert any(v['path'].endswith('/purge-review') and v['query'].get('offset')=='24' for v in original_reads)
    assert any(v['path'].endswith('/purge-review/files') and v['query'].get('offset')=='100' and v['query'].get('trash_id')==setup['large_member']['trash_id'] for v in original_reads)
    assert any('/tasks/'+setup['plan_id']+'/purge-review' in v['path'] for v in original_reads)
    for name in names:
        raw = (base/(name+'.png')).read_bytes()
        assert raw.startswith(b'\x89PNG\r\n\x1a\n')
        assert struct.unpack('>II',raw[16:24]) == tuple(v*3 for v in result['viewport'])
        assert any('mCurrentFocus=' in row and 'io.github.shijijs.video_viewer' in row for row in (base/(name+'-window.txt')).read_text().splitlines())
    rounds.append({'round':n,'elapsed_seconds':result['elapsed_seconds'],'screens':len(names)})
print(json.dumps({'verified':True,'source':source['commit'],'client_tests':451,'server_tests':402,'native_rounds':3,'screens':21,'source_files_retained':54,'rounds':rounds},ensure_ascii=False,indent=2))
