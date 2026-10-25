"""Verify the clicked-image navigation proof and its actual history."""
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
for name,digest in read('manifest.json')['inputs'].items():
    assert hashlib.sha256((folder/name).read_bytes()).hexdigest() == digest, name
    subprocess.check_output(['git','ls-files','--error-unmatch',str((folder/name).relative_to(root))],cwd=root)
for name,digest in source['files'].items():
    assert hashlib.sha256((root/name).read_bytes()).hexdigest() == digest, name
    assert hashlib.sha256(subprocess.check_output(['git','show',source['commit']+':'+name],cwd=root)).hexdigest()==digest, name
for ref in ('HEAD',source['commit']):
    for path,key in [('apps/mobile/lib','app_lib_tree'),('apps/mobile/test','app_test_tree'),('services/server/video_viewer','server_production_tree')]:
        assert subprocess.check_output(['git','rev-parse',ref+':'+path],cwd=root,text=True).strip()==source[key]
for ref in ('HEAD',source['commit'],source['base'],'design-lf-2026-10-23'):
    assert subprocess.check_output(['git','rev-parse',ref+':design/reference/library-first'],cwd=root,text=True).strip()=='1cbf605af8f03fa067a4ce8e914bb809e3a487ca'
assert subprocess.check_output(['git','rev-parse',source['base']+':services/server/video_viewer'],cwd=root,text=True).strip()==source['server_production_tree']
log=(folder/'client-full.log').read_text()
assert '+457: All tests passed!' in log and not re.search(r'\+\d+ -\d+:',log)
assert 'No issues found!' in (folder/'analyze.log').read_text()
assert (folder/'ruff.log').read_text().strip()=='All checks passed!'
assert 'Some tests failed.' in (folder/'diagnostics/lf5-visible-skip-before.log').read_text()
assert '+6: All tests passed!' in (folder/'diagnostics/lf5-visible-skip-after.log').read_text()
names={'visible-last-before','visible-last-end','visible-last-returned','visible-last-resumed','visible-last-next-pack'}
rounds=[]
previous_media=None
for n in (1,2,3,4):
    p=folder/(f'round-{n}' if n<4 else 'compatibility')
    value=lambda name: json.loads((p/name).read_text())
    result=value('result.json')
    assert result['source']==source['commit'] and result['source_files']==source['files']
    assert result['exit_code']==0 and result['scale']==1
    assert result['scenario']==('visible' if n<4 else 'last')
    assert result['viewport']==([390,844] if n<4 else [844,390])
    native=result['verified']; rows=value('database-proof.json')['sql_rows']
    assert value('database-proof.json')['native']==native
    assert {v[0] for v in rows['packs']}=={native['failed_pack'],native['good_pack']}
    marks={v[0]:v for v in rows['progress']}
    assert native['good_pack'] in marks
    requests=value('requests.json')
    assert not any(v['method']=='DELETE' for v in requests)
    faults=[v for v in requests if 'fault' in v]
    if n<4:
        assert native['viewport_index']==1 and native['clicked_index']==2 and .7<native['ratio']<1
        assert native['previous_page']!=native['failed_page']
        assert native['before']==native['after']
        for key in ('before','after','final_progress'):
            assert native[key]['page_id']==native['previous_page'] and native[key]['completed'] is False
            assert abs(native[key]['offset_ratio']-native['ratio'])<1e-8
        assert native['final_progress']['revision']>=native['before']['revision']
        assert marks[native['failed_pack']][1:]==[native['previous_page'],0,native['final_progress']['revision']]
        assert all(v[1]!=native['failed_page'] for v in rows['progress'])
        assert {v[1] for v in rows['recent']}=={native['failed_pack'],native['good_pack']}
        assert faults and all(v['path']=='/api/v1/pages/'+native['failed_page']+'/image' and v['method']=='GET' and v['status']==404 for v in faults)
        assert not any(v['method']!='GET' for v in requests if v.get('phase') in ('visible-last-before','visible-last-end'))
        opened=[v for v in requests if v['method']=='POST' and v['path'].endswith('/opened')]
        assert len(opened)==3 and all(v['status']==200 for v in opened)
        expected=names
    else:
        assert native['failed_progress'] is None and native['failed_pack'] not in marks
        assert rows['recent']==[['pack',native['good_pack']]]
        expected={'missing-last-failure','missing-pack-end','missing-last-image','corrupt-last-failure','corrupt-pack-end','explicit-next-pack'}
    assert set(result['screens'])==expected and len(result['screens'])==len(expected)
    media=value('media-before.json')
    assert len(media)==6 and media==value('media-after.json')
    if previous_media is not None: assert previous_media==media
    previous_media=media
    restored=value('restored-viewport.json')
    assert restored['before']==restored['after'] and restored['font_before']==restored['font_after'] and not restored['watcher_errors']
    assert 'All tests passed!' in (p/'flutter.log').read_text()
    for name in expected:
        raw=(p/(name+'.png')).read_bytes()
        assert raw.startswith(b'\x89PNG\r\n\x1a\n') and struct.unpack('>II',raw[16:24])==tuple(v*3 for v in result['viewport'])
        assert any('mCurrentFocus=' in row and 'io.github.shijijs.video_viewer' in row for row in (p/(name+'-window.txt')).read_text().splitlines())
    rounds.append({'round':n if n<4 else 'compatibility','elapsed_seconds':result['elapsed_seconds'],'screens':len(expected)})
print(json.dumps({'verified':True,'source':source['commit'],'client_tests':457,'visible_rounds':3,'compatibility_rounds':1,'screens':21,'source_images_unchanged':6,'rounds':rounds},ensure_ascii=False,indent=2))
