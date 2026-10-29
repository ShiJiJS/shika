"""Read test catalog inside its owning container; never open live SQLite on macOS."""

import json
import subprocess
import sys
from pathlib import Path

OUT = Path(__file__).resolve().parent
TABLES = [
    "videos", "tags", "video_tags", "directories", "roots", "packs", "pack_pages",
    "pack_tag_definitions", "pack_tag_links", "pack_progress", "pack_preferences",
    "tasks", "file_operations", "file_steps", "request_records", "trash_items",
    "pack_sessions", "pack_session_entries", "playback_rounds", "round_entries", "recent_entries",
]
CODE = """import hashlib,json,sqlite3,time
c=sqlite3.connect('file:/data/library.sqlite3?mode=ro',uri=True,timeout=5)
c.row_factory=sqlite3.Row
c.execute('BEGIN')
tables=TABLES
result={}
for name in tables:
 q='"'+name.replace('"','""')+'"'
 rows=[dict(r) for r in c.execute('SELECT * FROM '+q)]
 result[name]=sorted(rows,key=lambda r:json.dumps(r,sort_keys=True))
opaque={}
for name in ['settings','access_tokens']:
 rows=[dict(r) for r in c.execute('SELECT * FROM '+name)]
 canonical=json.dumps(sorted(rows,key=lambda r:json.dumps(r,sort_keys=True)),sort_keys=True)
 opaque[name]={'rows':len(rows),'sha256':hashlib.sha256(canonical.encode()).hexdigest()}
token_expiry=[r[0] for r in c.execute('SELECT expires_at FROM access_tokens')]
c.rollback();c.close()
print(json.dumps({'tables':result,'opaque_table_digests':opaque,'token_expiry':token_expiry,'observed_at':time.time()},indent=2))
""".replace("tables=TABLES", "tables=" + repr(TABLES))


def snapshot(name):
    raw = subprocess.check_output(
        ["docker", "exec", "video-viewer-settings-normal", "python", "-c", CODE], timeout=20
    )
    (OUT / (name + "-catalog.json")).write_bytes(raw)
    value = json.loads(raw)
    print(json.dumps({"snapshot": name, "counts": {k: len(v) for k, v in value["tables"].items()}}))
    return value


if __name__ == "__main__":
    snapshot(sys.argv[1])
