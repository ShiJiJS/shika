from pathlib import Path
import hashlib,json,shutil,subprocess,time
root=Path('/Users/jiangxinyi/Documents/Project/video-viewer')
evidence=root/'docs/plans/library-first/evidence/lf7-roots-missing'
evidence.mkdir(parents=True,exist_ok=True)
files=[p for p in subprocess.check_output(['git','ls-files'],cwd=root,text=True).splitlines() if p.startswith(('apps/mobile/lib/','services/server/video_viewer/','services/server/migrations/')) or p in ['apps/mobile/integration_test/server_roots_missing_test.dart','services/server/tests/e2e_server.py','services/server/tests/pack_missing_fixture.py','scripts/run-client-connection-test.py','apps/mobile/test/pack_missing_test.dart','apps/mobile/test/media_root_sheet_test.dart','services/server/tests/test_pack_missing.py']]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
source={p:sha(root/p) for p in files}
commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
(evidence/'source-sha256.json').write_text(json.dumps({'source_commit':commit,'files':source},indent=2)+'\n')
results=[]
for i,(viewport,scale) in enumerate([('360','2'),('390','1'),('390','1')],1):
 folder=evidence/f'round-{i}'; folder.mkdir(exist_ok=True)
 command=['bash','scripts/dev.sh','python3','scripts/run-client-connection-test.py','--roots-missing','--workspace-viewport',viewport,'--workspace-text-scale',scale]
 for old in (root/'tmp/client-e2e').glob('lf7-roots-missing-*'):
  old.unlink()
 start=time.monotonic()
 with (folder/'driver.log').open('w') as out:
  result=subprocess.run(command,cwd=root,stdout=out,stderr=subprocess.STDOUT)
 for p in (root/'tmp/client-e2e').glob('lf7-roots-missing-*'):
  shutil.copy2(p,folder/p.name)
 row={'round':i,'source_commit':commit,'viewport':viewport,'text_scale':scale,'command':command,'exit_code':result.returncode,'elapsed_seconds':round(time.monotonic()-start,2),'apk_sha256':sha(root/'apps/mobile/build/app/outputs/flutter-apk/app-debug.apk')}
 results.append(row)
 (evidence/'verification.json').write_text(json.dumps(results,indent=2)+'\n')
 print(json.dumps(row),flush=True)
 assert all(sha(root/p)==h for p,h in source.items()),'source changed during rounds'
 if result.returncode: raise SystemExit(result.returncode)
