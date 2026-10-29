"""Offline, read-only verification of the retained code16 evidence."""
import hashlib,json
from pathlib import Path
E=Path(__file__).resolve().parent
read=lambda p:json.loads((E/p).read_text())
m=read('manifest.json')['inputs']
for name,v in m.items():
 p=E/name;assert p.stat().st_size==v['bytes'] and hashlib.sha256(p.read_bytes()).hexdigest()==v['sha256'],name
assert read('package-audit.json')['complete'] and read('cleanup.json')['complete']
base=read('normal/before16-catalog.json');prefs=read('normal/before16-preferences.json')
for step in ['forward16','rollback16','forward16-return']:
 a=read('normal/after-'+step+'-catalog.json');assert a['tables']==base['tables'] and a['opaque_table_digests']==base['opaque_table_digests'];assert read('normal/after-'+step+'-preferences.json')==prefs
base=read('normal/before-business-catalog.json')
for label in ['after-workspace-more','after-video-menus-filters','after-root-kind-cancel','after-task-family','after-default-draft-cancel']:
 a=read('normal/'+label+'-catalog.json');assert a['tables']==base['tables'] and a['opaque_table_digests']==base['opaque_table_digests']
a=read('normal/before-reader-actual-catalog.json');b=read('normal/after-reader-actual-catalog.json');assert {k for k in a['tables'] if a['tables'][k]!=b['tables'][k]}==set(read('business-audit.json')['reader_changed_tables']);assert a['opaque_table_digests']['access_tokens']==b['opaque_table_digests']['access_tokens']
a=read('normal/video-paused-before-speed-catalog.json');b=read('normal/after-video-speed-catalog.json')
for k in ['playback_rounds','round_entries']:assert a['tables'][k]==b['tables'][k]
for left,right in [('normal/before-legacy-shell-menu','normal/after-legacy-shell-menu'),('normal/before-rollback-business','normal/after-rollback-business'),('history-normal/before-history-browse','history-normal/after-history-browse')]:
 a=read(left+'-catalog.json');b=read(right+'-catalog.json');assert a['tables']==b['tables'] and a['opaque_table_digests']==b['opaque_table_digests']
assert read('normal/before-rollback-business-preferences.json')==read('normal/after-rollback-business-preferences.json')
assert '+766: All tests passed!' in (E/'client-tests.log').read_text();assert 'No issues found!' in (E/'analyze-final.log').read_text()
print(f'{len(m)} immutable inputs verified; upgrades, scoped business deltas, history and cleanup passed')
