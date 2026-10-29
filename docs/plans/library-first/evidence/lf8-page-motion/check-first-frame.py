import json
from pathlib import Path
lab=Path(__file__).resolve().parent
report=json.loads((lab/'native-4-layout/profile-result.json').read_text())['page_motion']
checks=[]
for case in report['cases']:
    if case['reduced'] and not case['closing']:
        first=case['frames'][0]
        assert first['offstage'] is False and first['value']==1 and first['display_value']==1
        assert first['native_flag'] is True and first['media_query_flag_at_action'] is True
        checks.append({'name':case['name'],'first_observed_frame':first,'passed':True})
assert len(checks)==12
(lab/'reduced-first-frame-check.json').write_text(json.dumps({'cases':checks,'all_12_reduced_entries_first_frame_not_offstage':True,'physical_presentation_latency_accepted':False},indent=2)+'\n')
print('All 12 reduced entries: first observed frame is not offstage and both progress values are 1')
