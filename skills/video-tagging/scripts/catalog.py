"""严格事实映射、来源记录与仅限自有标签的差量计划；不联网。"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath, PureWindowsPath
import sys


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def unique(rows, key):
    values = [r[key] for r in rows]
    if len(values) != len(set(values)):
        raise ValueError('Duplicate identity')


def file_hash(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def write_new(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('x', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write('\n')


def snapshot(manifest_path):
    files = []
    manifest_path = manifest_path.resolve()
    for name in read(manifest_path):
        path = Path(name)
        path = (manifest_path.parent / path).resolve()
        if not path.is_file():
            raise ValueError('Protected file missing')
        files.append({'path': str(path), 'sha256': file_hash(path)})
    if not files:
        raise ValueError('Empty protection set')
    unique(files, 'path')
    return {'files': files}


def verify_protected(data, base):
    for row in data['files']:
        path = (base / row['path']).resolve()
        if not path.is_file() or file_hash(path) != row['sha256']:
            raise ValueError('Protected original changed')


def verify_sources(rows, base):
    """Verify exact raw text against JSON pointers; never promote an adapter guess."""
    cache = {}
    for row in rows:
        for fact in row['facts']:
            if fact.get('status') != 'affirmed':
                continue
            path = (base / fact['source_ref']).resolve()
            if path not in cache:
                cache[path] = read(path)
            pointer = fact.get('pointer')
            if not isinstance(pointer, str) or not pointer.startswith('/'):
                raise ValueError('Source JSON pointer required')
            value = cache[path]
            for part in pointer[1:].split('/'):
                part = part.replace('~1', '/').replace('~0', '~')
                value = value[int(part)] if isinstance(value, list) else value[part]
            if value != fact['raw']:
                raise ValueError('Fact differs from original source')
    return {str(path): file_hash(path) for path in cache}


def relative_key(row):
    text = row['relative_path'].replace('\\', '/')
    path = PurePosixPath(text)
    if not text or path.is_absolute() or '..' in path.parts or PureWindowsPath(text).drive:
        raise ValueError('Expected root-relative path')
    return row['root_id'], str(path)


def match(targets, inventory):
    """Match a verified stable-ID/path ledger to a complete post-scan inventory."""
    if not inventory.get('scan_complete') or not inventory.get('inventory_complete'):
        raise ValueError('Inventory not complete')
    if not inventory.get('server_instance') or not inventory.get('root_paths') or not inventory.get('snapshot_id'):
        raise ValueError('Library context required')
    rows = inventory['records']
    unique(rows, 'server_id')
    unique(targets, 'video_id')
    candidates = {}
    for row in rows:
        if row.get('status') == 'available':
            candidates.setdefault(relative_key(row), []).append(row)
    result, blocked, used = [], [], set()
    for target in targets:
        key = relative_key(target)
        found = candidates.get(key, [])
        if key[0] not in inventory['root_paths'] or not target.get('mapping_ref') or len(found) != 1:
            blocked.append({'video_id': target['video_id'], 'reason': 'unproven_or_ambiguous_path'})
            continue
        row = found[0]
        if row['size'] != target['size'] or row['server_id'] in used:
            blocked.append({'video_id': target['video_id'], 'reason': 'size_or_identity_conflict'})
            continue
        if target.get('sha256') and target['sha256'] != row.get('sha256'):
            blocked.append({'video_id': target['video_id'], 'reason': 'digest_unverified'})
            continue
        used.add(row['server_id'])
        identity = {'root_id': key[0], 'relative_path': key[1], 'size': target['size']}
        result.append({'video_id': target['video_id'], 'server_id': row['server_id'],
                       'previous_server_id': target.get('previous_server_id'),
                       'identity': identity, 'observed': {**identity, 'server_id': row['server_id'], 'status': row['status']},
                       'mapping_ref': target['mapping_ref'], 'current': row['tags'],
                       'managed_previous': target.get('managed_previous', [])})
    return {k: inventory[k] for k in ('server_instance', 'root_paths', 'snapshot_id', 'scan_complete', 'inventory_complete')} | {
        'records': result, 'blocked': blocked,
        'unmapped_available_count': sum(r.get('status') == 'available' and r['server_id'] not in used for r in rows)}


def normalize(rows, rules):
    unique(rows, 'video_id')
    lookup = {}
    for rule in rules['rules']:
        key = tuple(rule[k] for k in ('source_kind', 'field', 'raw'))
        if key in lookup:
            raise ValueError('Ambiguous rule')
        for item in rule['outputs']:
            if not item['group'] or not item['tag']:
                raise ValueError('Empty label')
            if item['group'] != '作者' and any(c.isascii() and c.isalpha() for c in item['tag']):
                raise ValueError('Standard label requires Chinese mapping')
        lookup[key] = rule['outputs']
    out = []
    for row in rows:
        groups, evidence, pending = {}, {}, []
        for fact in row['facts']:
            key = tuple(fact.get(k) for k in ('source_kind', 'field', 'raw'))
            if (fact.get('status') != 'affirmed' or not fact.get('source_ref')
                    or key[0] not in ('directory', 'raw_tag', 'manual') or key not in lookup):
                pending.append(fact)
                continue
            for item in lookup[key]:
                group, tag = item['group'], item['tag']
                groups.setdefault(group, set()).add(tag)
                evidence.setdefault(group, {}).setdefault(tag, []).append(fact)
        groups = {k: sorted(v) for k, v in groups.items()}
        out.append({'video_id': row['video_id'], 'groups': groups,
                    'tags': sorted({t for ts in groups.values() for t in ts}),
                    'evidence': evidence, 'pending': pending})
    return {'records': out}


def plan(standard, state):
    rows = standard['records']
    if (not isinstance(state, dict) or not state.get('scan_complete') or not state.get('inventory_complete')
            or not state.get('server_instance') or not state.get('root_paths') or not state.get('snapshot_id')
            or state.get('blocked')):
        raise ValueError('Verified current library mapping required')
    context = {k: state[k] for k in ('server_instance', 'root_paths', 'snapshot_id')}
    state = state['records']
    unique(rows, 'video_id')
    unique(state, 'video_id')
    unique(state, 'server_id')
    if any(not row['server_id'] for row in state):
        raise ValueError('Unmatched server identity')
    previous = {r['video_id']: r for r in state}
    if set(previous) != {r['video_id'] for r in rows}:
        raise ValueError('Unmatched videos')
    output = []
    for row in rows:
        old = previous[row['video_id']]
        observed = old.get('observed', {})
        if (not old.get('mapping_ref') or observed.get('server_id') != old['server_id']
                or observed.get('status') != 'available' or not old.get('identity')
                or any(observed.get(k) != old['identity'].get(k) for k in ('root_id', 'relative_path', 'size'))
                or old['identity']['root_id'] not in context['root_paths']):
            raise ValueError('Stale video mapping')
        desired, current = set(row['tags']), set(old['current'])
        owned = set(old.get('managed_previous', []))
        output.append({'video_id': row['video_id'], 'server_id': old['server_id'],
                       'add': sorted(desired - current), 'remove': sorted((owned - desired) & current),
                       'desired': sorted(desired), 'preserved': sorted(current - owned - desired)})
    return {'library_context': context, 'records': output}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('mode', choices=['normalize', 'plan', 'match', 'protect', 'verify'])
    for name in ('facts', 'rules', 'standard', 'state', 'targets', 'inventory', 'files', 'protected'):
        p.add_argument('--' + name, type=Path)
    p.add_argument('--output', type=Path)
    a = p.parse_args()
    if a.mode == 'verify':
        verify_protected(read(a.protected), a.protected.resolve().parent)
        print(json.dumps({'status': 'verified'}))
        return
    if a.output is None:
        raise ValueError('Output path required')
    if a.output.exists() or (a.mode == 'normalize' and a.output.with_suffix('.md').exists()):
        raise ValueError('Output exists; use a new version')
    if a.mode == 'protect':
        result = snapshot(a.files)
        # Store paths relative to the protection file for whole-workspace relocation.
        import os
        for item in result['files']:
            item['path'] = os.path.relpath(item['path'], a.output.resolve().parent).replace(os.sep, '/')
        write_new(a.output, result)
        print(json.dumps({'files': len(result['files']), 'status': 'protected'}))
        return
    if a.protected is None:
        raise ValueError('Original protection snapshot required')
    protected = read(a.protected)
    verify_protected(protected, a.protected.resolve().parent)
    source_hashes = {}
    if a.mode == 'normalize':
        facts = read(a.facts)
        source_hashes = verify_sources(facts, a.facts.resolve().parent)
        guarded = {(a.protected.resolve().parent / r['path']).resolve() for r in protected['files']}
        if not {Path(p) for p in source_hashes}.issubset(guarded):
            raise ValueError('Source missing from protection snapshot')
        result = normalize(facts, read(a.rules))
    elif a.mode == 'match':
        result = match(read(a.targets), read(a.inventory))
    else:
        standard, state = read(a.standard), read(a.state)
        snapshot_hash = file_hash(a.protected)
        if (standard.get('protected_snapshot_sha256') != snapshot_hash
                or state.get('protected_snapshot_sha256') != snapshot_hash):
            raise ValueError('Standard and mapping must use the same protected originals')
        for row in standard['records']:
            grouped = {tag for tags in row['groups'].values() for tag in tags}
            if set(row['tags']) != grouped:
                raise ValueError('Flat labels differ from grouped evidence')
            for group, tags in row['groups'].items():
                if any(not row.get('evidence', {}).get(group, {}).get(tag) for tag in tags):
                    raise ValueError('Standard label lacks original evidence')
        result = plan(standard, state)
    verify_protected(protected, a.protected.resolve().parent)
    if any(file_hash(path) != value for path, value in source_hashes.items()):
        raise ValueError('Source changed during normalization')
    result['protected_snapshot_sha256'] = file_hash(a.protected)
    write_new(a.output, result)
    if a.mode == 'normalize':
        def cell(s):
            return str(s).replace('|', '\\|').replace('\n', ' ').replace('\r', ' ')
        lines = ['# 标准视频标签', '', '| 编号 | 标准标签 | 待核条目数 |', '| --- | --- | ---: |']
        lines += [f"| {cell(r['video_id'])} | {cell('、'.join(r['tags']))} | {len(r['pending'])} |" for r in result['records']]
        a.output.with_suffix('.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print(json.dumps({'records': len(result['records']), 'status': 'done'}))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(json.dumps({'status': 'error', 'error_type': type(error).__name__}))
        sys.exit(1)
