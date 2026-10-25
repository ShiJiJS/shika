from pathlib import Path
import json,hashlib,subprocess
root=Path.cwd();ev=root/'docs/plans/library-first/evidence/lf7-restore-client'
rounds=json.loads((ev/'verification.json').read_text());assert len(rounds)==3 and all(r['exit_code']==0 for r in rounds)
proof=[]
for r in rounds:
 d=ev/f"round-{r['round']}";events=json.loads((d/'lf7-restore-host-events.json').read_text());assert not events['errors']
 by={e['phase']:e for e in events['events']}
 assert by['restore-app-force-stopped']['pid_absent'] and by['restore-completed-without-app']['pid_absent']
 assert by['restore-expected-test-interruption']['runner_exit_code']!=0
 assert by['restore-app-reopened']['old_pid']!=by['restore-app-reopened']['new_pid']
 assert by['restore-app-force-stopped']['time'] < by['restore-completed-without-app']['time'] < by['restore-app-reopened']['time']
 phases=['selected','unknown','reopened','paged','stop-unknown','stopped'];hashes=[]
 for phase in phases:
  hashes.append(json.loads((d/f'lf7-restore-restore-{phase}-files.json').read_text())['hashes']);assert (d/f'lf7-restore-restore-{phase}.png').is_file()
 assert len(hashes[0])==81 and all(h==hashes[0] for h in hashes)
 unknown=json.loads((d/'lf7-restore-restore-unknown-plan.json').read_text())
 absent=json.loads((d/'lf7-restore-without-app-plan.json').read_text())
 final=json.loads((d/'lf7-restore-restore-stopped-plan.json').read_text())
 assert unknown['plan']['id']==absent['plan']['id'] and absent['member_counts']=={'succeeded':27}
 assert len(absent['batches'])==len(set(absent['batches']))==14
 ids={p['id'] for p in unknown['packs']};assert len(ids)==27 and {p['id'] for p in absent['packs']}==ids=={p['id'] for p in final['packs']}
 assert {p['generation'] for p in unknown['packs']}=={2} and {p['generation'] for p in absent['packs']}=={3}
 assert final['member_counts']=={'succeeded':2,'stopped':25} and len(final['batches'])==1
 assert {p['generation'] for p in final['packs']}=={4,5}
 trace=json.loads((d/'lf7-restore-restore-stopped-requests.json').read_text())['items']
 posts=[x for x in trace if x['method']=='POST'];assert len(posts)==4
 assert sum(x['path']=='/api/v1/pack-restore-plans' for x in posts)==2
 stop=[x for x in posts if x['path'].endswith('/stop')];assert len(stop)==1 and stop[0]['status']==503
 assert all(x['authenticated'] for x in trace)
 receipts=[x for x in trace if '/pack-restore-requests/' in x['path']];assert len(receipts)==1 and receipts[0]['path'].endswith('/'+absent['plan']['request_id'])
 assert len([x for x in trace if '/pack-restore-stop-requests/' in x['path']])==1
 log=(d/'lf7-restore-android-test.log').read_text();assert 'VV_E2E_RESTORE_FORCE_STOP' in log and 'VV_E2E_RESTORE_REOPENED' in log and 'All tests passed!' in log
 proof.append({'round':r['round'],'interrupted_pid':by['restore-app-force-stopped']['pid'],'reopened_pid':by['restore-app-reopened']['new_pid'],'restored_without_app':27,'unique_batches':14,'original_restore_gets':1,'stop_posts':1,'original_stop_gets':1,'stopped_unstarted':25,'current_batch_succeeded':2,'images_unchanged':81,'original_pack_ids_unchanged':27})
s=json.loads((ev/'source-sha256.json').read_text());assert all(hashlib.sha256((root/p).read_bytes()).hexdigest()==h for p,h in s['files'].items())
(ev/'proof.json').write_text(json.dumps(proof,indent=2)+'\n')
print('PASS three real secure-storage force-stop/reopen rounds; original requests, unique batches, IDs and image hashes verified')
