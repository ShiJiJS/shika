"""Private pause after real restore commit; no extra HTTP endpoints."""
import hashlib,json,os,time
from dataclasses import replace
from pathlib import Path
from video_viewer.app import create_app
from video_viewer.authority import Authority
from video_viewer.config import Settings
from video_viewer.models import Setting,Task

CONTROL=Path('/control')
def read_control():return json.loads((CONTROL/'executor.json').read_text())
def checkpoint(phase,identity):
    if phase!='restore_committed' or not read_control().get('hold_after_commit'):return
    owner=app.state.backups
    with app.state.db.read() as session:
        value={'phase':phase,'task_id':identity,'time':time.time(),'task_status':session.get(Task,identity).status,'maintenance_task':owner.db.maintenance_task,'maintenance_owner_cleared':owner.db.maintenance_owner is None,'durable_reservation_empty':not session.get(Setting,'maintenance_restore').value,'management_epoch_sha256':hashlib.sha256(Authority.current(session).encode()).hexdigest()}
    incoming=CONTROL/'committed.incoming'
    with incoming.open('w') as f:
        json.dump(value,f);f.flush();os.fsync(f.fileno())
    incoming.replace(CONTROL/'committed.json')
    while read_control().get('hold_after_commit') and not owner.stop.is_set():time.sleep(.025)

def create_fixture_app():
    global app
    app=create_app(replace(Settings.from_env(),startup_scan=False,scan_interval=0),backup_fault_hook=checkpoint)
    return app
