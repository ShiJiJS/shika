from pathlib import Path
import subprocess, time, json, hashlib, shutil
root=Path(subprocess.check_output(['git','rev-parse','--show-toplevel'], text=True).strip())
base=root/'.dev/lf6-native-tag-menu'
paths=subprocess.check_output(['git','ls-files','apps/mobile/lib','apps/mobile/integration_test','services/server'],cwd=root,text=True).splitlines()
source={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in paths if (root/name).is_file()}
head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
phases=['pack-names-card','pack-names-retry','pack-names-saved','pack-names-renamed']
for name,width,scale in [('01-large','360','2'),('02-normal','390','1'),('03-normal','390','1')]:
    destination=base/name;destination.mkdir(exist_ok=True)
    started=time.time()
    print('Starting native tag-menu regression '+name,flush=True)
    with (destination/'runner.log').open('w') as log:
        result=subprocess.run(['bash','scripts/dev.sh','python3','scripts/run-client-connection-test.py','--pack-names','--workspace-viewport',width,'--workspace-text-scale',scale],cwd=root,stdout=log,stderr=subprocess.STDOUT)
    candidates=list((root/'tmp/client-e2e').glob('lf4-pack-names-*'))
    for artifact in candidates:
        if artifact.is_file() and artifact.stat().st_mtime>=started:
            shutil.copyfile(artifact,destination/artifact.name)
    if result.returncode:
        print('Native regression failed: '+name,flush=True)
        raise SystemExit(result.returncode)
    events=json.loads((destination/'lf4-pack-names-host-events.json').read_text())
    assert not events['errors'],events
    for phase in phases:
        assert sum(row.get('phase')==phase for row in events['events'])==1,(name,phase,events)
        assert (destination/('lf4-pack-names-'+phase+'.png')).is_file(),phase
        assert (destination/('lf4-pack-names-'+phase+'-requests.json')).is_file(),phase
    assert 'All tests passed!' in (destination/'lf4-pack-names-android-test.log').read_text()
    assert all(hashlib.sha256((root/p).read_bytes()).hexdigest()==h for p,h in source.items()),'Source changed during native test'
    apk=root/'apps/mobile/build/app/outputs/flutter-apk/app-debug.apk'
    proof={'commit':head,'started_at':started,'finished_at':time.time(),'viewport_width_dp':int(width),'text_scale':int(scale),'source_sha256':source,
        'apk_sha256':hashlib.sha256(apk.read_bytes()).hexdigest(),
        'artifact_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in destination.iterdir() if p.is_file()}}
    (destination/'proof.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2)+'\n')
    print('Completed native tag-menu regression '+name,flush=True)
