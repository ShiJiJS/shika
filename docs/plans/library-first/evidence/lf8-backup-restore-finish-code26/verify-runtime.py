import gzip,hashlib,json,shutil,subprocess,tarfile
from pathlib import Path
L=Path(__file__).resolve().parent;R=L.parents[1];build=json.loads((L/'build-source.json').read_text());source=build['source'];tag=build['runtime']
old=json.loads((R/'docs/plans/library-first/evidence/lf8-restored-pack-scan-code26/runtime-source.json').read_text())['files']
names=sorted(old)
expected={p:hashlib.sha256(subprocess.check_output(['git','show',source+':services/server/'+p])).hexdigest() for p in names}
changed=[p for p in old if old[p]!=expected[p]]
assert changed==['video_viewer/backups.py','video_viewer/management_archives.py'],changed
code="import hashlib,json,pathlib,importlib.util;names="+repr(names)+";print(json.dumps({'files':{p:hashlib.sha256((pathlib.Path('/app')/p).read_bytes()).hexdigest() for p in names},'pytest_present':importlib.util.find_spec('pytest') is not None}))"
actual=json.loads(subprocess.check_output(['docker','run','--rm','--read-only','--network','none','--entrypoint','python',tag,'-c',code]));assert actual['files']==expected and not actual['pytest_present']
(L/'runtime-source.json').write_text(json.dumps({'source':source,**actual,'added_files':[],'changed_existing_files':changed,'other_77_files_unchanged':True},indent=2))
inspect=json.loads(subprocess.check_output(['docker','image','inspect',tag]))[0];assert inspect['Architecture']=='arm64' and inspect['Config']['Labels']['vv.source']==source
out=R/'tmp/releases/video-viewer-server-0.2.0-preview.8-linux-arm64.tar.gz';assert not out.exists()
with gzip.open(out,'wb',compresslevel=6) as target:
    p=subprocess.Popen(['docker','save',tag],stdout=subprocess.PIPE,stderr=subprocess.PIPE);shutil.copyfileobj(p.stdout,target,1024*1024);p.stdout.close();error=p.stderr.read();assert p.wait()==0,error
with tarfile.open(out,'r:gz') as archive:
    manifest=json.load(archive.extractfile('manifest.json'))[0];raw=archive.extractfile(manifest['Config']).read();config=json.loads(raw)
assert config['rootfs']['diff_ids']==inspect['RootFS']['Layers'] and config['config']['Labels']['vv.source']==source
result={'source':source,'platform':'linux/arm64','runtime_files_matched':len(names),'changed_existing_files':changed,'added_files':[],'other_77_files_unchanged':True,'pytest_present':False,'local_image_index_id':inspect['Id'],'archive_config_sha256':hashlib.sha256(raw).hexdigest(),'archive_rootfs_matches_local_image':True,'rootfs_diff_ids':config['rootfs']['diff_ids'],'healthcheck':inspect['Config']['Healthcheck'],'archive':{'name':out.name,'bytes':out.stat().st_size,'sha256':hashlib.sha256(out.read_bytes()).hexdigest()},'nas_deployed':False}
(L/'build-result.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
