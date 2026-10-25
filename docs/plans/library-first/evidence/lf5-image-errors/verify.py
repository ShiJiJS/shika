"""Verify fixed reader error inputs, native screenshots and SQL projections."""
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess

folder = Path(__file__).resolve().parent
root = folder.parents[4]
read = lambda name: json.loads((folder / name).read_text())
source = read('source.json')
for name, digest in read('manifest.json')['inputs'].items():
    assert hashlib.sha256((folder / name).read_bytes()).hexdigest() == digest, name
    subprocess.check_output(['git','ls-files','--error-unmatch',str((folder/name).relative_to(root))],cwd=root)
for name,digest in source['files'].items():
    assert hashlib.sha256((root/name).read_bytes()).hexdigest() == digest, name
    assert hashlib.sha256(subprocess.check_output(['git','show',source['commit']+':'+name],cwd=root)).hexdigest() == digest, name
for ref in ('HEAD',source['commit']):
    for path,key in [('apps/mobile/lib','app_lib_tree'),('apps/mobile/test','app_test_tree'),('services/server/video_viewer','server_production_tree')]:
        assert subprocess.check_output(['git','rev-parse',ref+':'+path],cwd=root,text=True).strip() == source[key]
for path,key in [('apps/mobile/lib','app_lib_tree'),('apps/mobile/test','app_test_tree')]:
    assert subprocess.check_output(['git','rev-parse',source['client_full_started_at']+':'+path],cwd=root,text=True).strip() == source[key]
for ref in ('HEAD',source['commit'],source['base'],'design-lf-2026-10-23'):
    assert subprocess.check_output(['git','rev-parse',ref+':design/reference/library-first'],cwd=root,text=True).strip() == '1cbf605af8f03fa067a4ce8e914bb809e3a487ca'
assert subprocess.check_output(['git','rev-parse',source['base']+':services/server/video_viewer'],cwd=root,text=True).strip() == source['server_production_tree']
client = (folder/'client-full.log').read_text()
assert '+456: All tests passed!' in client and not re.search(r'\+\d+ -\d+:',client)
assert 'No issues found!' in (folder/'analyze.log').read_text()
assert (folder/'ruff.log').read_text().strip() == 'All checks passed!'
assert '+0 -5: Some tests failed.' in (folder/'diagnostics/lf5-reader-image-errors-baseline-final.log').read_text()
for name,digest in read('diagnostics/lf5-reader-image-errors-baseline-restored.json').items():
    assert source['files'][name] == digest
names = {'missing-last-failure','missing-pack-end','missing-last-image','corrupt-last-failure','corrupt-pack-end','explicit-next-pack'}
rounds = []
previous_media = None
for n in range(1,4):
    p = folder/f'round-{n}'
    value = lambda name: json.loads((p/name).read_text())
    result = value('result.json')
    assert result['source'] == source['commit'] and result['source_files'] == source['files']
    viewport = [[360,740],[390,844],[844,390]][n-1]
    assert result['viewport'] == viewport and result['scale'] == (2 if n==1 else 1)
    assert result['exit_code'] == 0 and set(result['screens']) == names and len(result['screens']) == 6
    native = result['verified']
    assert native['failed_pack'] != native['good_pack'] and native['failed_progress'] is None
    assert native['recent'] == [native['good_pack']] and native['modes'] == ['missing','corrupt']
    db = value('database-proof.json')
    assert db['native'] == native
    rows = db['sql_rows']
    assert {v[0] for v in rows['packs']} == {native['failed_pack'],native['good_pack']}
    assert {v[1] for v in rows['packs']} == {'异常图包 A','正常图包 B'}
    assert len(rows['progress']) == 1 and rows['progress'][0][0] == native['good_pack']
    assert rows['recent'] == [['pack',native['good_pack']]]
    media = value('media-before.json')
    assert len(media)==6 and media == value('media-after.json')
    if previous_media is not None: assert media == previous_media
    previous_media = media
    restored = value('restored-viewport.json')
    assert restored['before'] == restored['after'] and restored['font_before'] == restored['font_after'] and not restored['watcher_errors']
    requests = value('requests.json')
    faults = [v for v in requests if 'fault' in v]
    assert {v['fault'] for v in faults} == {'missing','corrupt'}
    assert all(v['method']=='GET' and v['path'].endswith('/image') and v['status']==(404 if v['fault']=='missing' else 200) for v in faults)
    opened = [v for v in requests if v['path'].endswith('/opened') and v['method']=='POST']
    assert len(opened) == 1 and opened[0]['status'] == 200
    assert not any(v['path'] == '/api/v1/packs/'+native['failed_pack']+'/progress' and v['method'] != 'GET' for v in requests)
    assert not any(v['method']=='DELETE' or any(part in v['path'] for part in ('/file-operations','/pack-operations','/pack-purge','/management-backups')) and v['method'] not in ('GET',) for v in requests)
    log = (p/'flutter.log').read_text()
    assert 'All tests passed!' in log and 'READER_ERRORS_VERIFIED:' in log
    assert 'statusCode: 404' in log and 'Invalid image data' in log
    for name in names:
        raw = (p/(name+'.png')).read_bytes()
        assert raw.startswith(b'\x89PNG\r\n\x1a\n') and struct.unpack('>II',raw[16:24]) == tuple(v*3 for v in viewport)
        assert any('mCurrentFocus=' in row and 'io.github.shijijs.video_viewer' in row for row in (p/(name+'-window.txt')).read_text().splitlines())
    rounds.append({'round':n,'elapsed_seconds':result['elapsed_seconds'],'screens':6})
print(json.dumps({'verified':True,'source':source['commit'],'client_tests':456,'native_rounds':3,'screens':18,'source_images_unchanged':6,'rounds':rounds},ensure_ascii=False,indent=2))
