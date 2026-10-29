import json,shutil
from pathlib import Path
R=Path(__file__).resolve().parents[2];L=R/'.dev/lf8-checkbox-package';D=R/'docs/plans/library-first/evidence/lf8-checkbox-package';assert not D.exists();D.mkdir()
for p in sorted(L.iterdir()):
 if p.is_file() and p.suffix in ['.json','.py','.log'] and p.name!='live-owned-resources.json':shutil.copy2(p,D/p.name)
(D/'build-1').mkdir()
for p in (L/'build-1').iterdir():
 if p.is_file():shutil.copy2(p,D/'build-1'/p.name)
for kind in ['normal','legacy']:
 (D/kind).mkdir()
 for p in (L/kind).iterdir():
  if p.is_file() and p.suffix in ['.json','.py','.jsonl','.txt']:shutil.copy2(p,D/kind/p.name)
 shutil.copytree(L/kind/'trace',D/kind/'trace')
S=D/'normal/screens';S.mkdir();selected={}
for p in json.loads((L/'confirmation-state-proof.json').read_text()):
 n=Path(p['xml']).name;selected[n.replace('.xml','.png')]=True
extra=['baseline16','forward17','rollback17','trash-box-selected-after','trash-row-text-deselected-after','pack-trash-box-after','picker-downloads-after','picker-v2-document-after','legacy-pick-document-after','final-library-return-after','legacy-connect-save-after','ordinary-trash-open-after','legacy-home-before-settings']
for p in sorted((L/'normal/screens').iterdir()):
 if p.suffix=='.xml' or (p.suffix=='.png' and (p.name in selected or any(x in p.name for x in extra))):shutil.copy2(p,S/p.name)
for p in list(S.glob('*.png')):
 window=L/'normal/screens'/(p.stem+'-window.txt')
 if window.exists():shutil.copy2(window,S/window.name)
info={'xml_states':len(list(S.glob('*.xml'))),'png_frames':len(list(S.glob('*.png'))),'critical_confirm_states':25,'other_full_pngs_retained_privately':True,'bytes':sum(p.stat().st_size for p in D.rglob('*') if p.is_file())};(D/'retention.json').write_text(json.dumps(info,indent=2)+'\n');print(json.dumps(info))
