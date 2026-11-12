"""按配置分版本保存识别任务；stdout 仅输出匿名编号和技术状态。"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path, PureWindowsPath, PurePosixPath
import subprocess
import sys
import urllib.request
from urllib.parse import urlparse

VERSION = '2'
ASSETS = Path(__file__).resolve().parents[1] / 'assets'


def read(p):
    return json.loads(Path(p).read_text(encoding='utf-8'))


def save(p, data, *, replace=False):
    p = Path(p)
    p.parent.mkdir(parents=True, exist_ok=True)
    if not replace:
        if p.exists():
            if read(p) != data:
                raise ValueError('Immutable result already exists')
            return
        with p.open('x', encoding='utf-8') as f:
            f.write(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    else:
        temporary = p.with_suffix(p.suffix + '.tmp')
        temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        temporary.replace(p)


def resolve_path(value, base):
    value = os.path.expandvars(str(value))
    if not value or '${' in value:
        raise ValueError('Local path binding required')
    if os.name != 'nt' and PureWindowsPath(value).is_absolute():
        raise ValueError('Bind foreign device path on this device')
    path = Path(value).expanduser()
    return (path if path.is_absolute() else base / path).resolve()


def load_config(path):
    path = path.resolve()
    cfg = read(path)
    # The distributed skill is self-contained; an explicit extractor remains
    # supported for existing workspaces with their own sampling policy.
    if not cfg.get('extractor'):
        cfg['extractor'] = str(Path(__file__).with_name('extract_keyframes.py'))
    for key in ('extractor', 'model_root'):
        if cfg.get(key):
            cfg[key] = str(resolve_path(cfg[key], path.parent))
    cfg['media_roots'] = {k: str(resolve_path(v, path.parent)) for k, v in cfg.get('media_roots', {}).items()}
    return cfg


def bind_video(video, cfg, manifest_dir):
    video = dict(video)
    if 'relative_path' in video:
        rel = PurePosixPath(video['relative_path'].replace('\\', '/'))
        if rel.is_absolute() or '..' in rel.parts or PureWindowsPath(str(rel)).drive:
            raise ValueError('Media path must remain relative to its root')
        root = Path(cfg['media_roots'][video['root_id']]).resolve()
        source = (root / str(rel)).resolve()
        if not source.is_relative_to(root):
            raise ValueError('Media path escapes root')
    else:
        source = resolve_path(video['source_path'], manifest_dir)
    video['source_path'] = str(source)
    return video


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def prediction_valid(p):
    if not isinstance(p, dict):
        raise ValueError('Prediction must be object')
    for key in ('content_tags', 'appearance_tags', 'characters', 'uncertainties'):
        if key not in p or not isinstance(p[key], list):
            raise ValueError('Prediction array required')
    for key in ('content_tags', 'appearance_tags'):
        if any(not isinstance(x, dict) or not isinstance(x.get('tag'), str) for x in p[key]):
            raise ValueError('Tag object required')
    if p.get('pool') not in ('真人', '动画', '混合', '不确定'):
        raise ValueError('Pool required')


def task_for(video, cfg, prompt, output, mode):
    vid = video['video_id']
    if not isinstance(vid, str) or not vid.isascii() or not vid.replace('_', '').replace('-', '').isalnum():
        raise ValueError('Unsafe anonymous ID')
    source = Path(video['source_path']).resolve()
    st = source.stat()
    signature = {'path': str(source), 'size': st.st_size, 'mtime_ns': st.st_mtime_ns}
    if video.get('sha256'):
        h = hashlib.sha256()
        with source.open('rb') as f:
            for block in iter(lambda: f.read(1024 * 1024), b''):
                h.update(block)
        if h.hexdigest() != video['sha256']:
            raise ValueError('Source digest mismatch')
        signature['sha256'] = h.hexdigest()
    extractor = Path(cfg['extractor']).resolve()
    cfg = {**cfg, 'extractor_sha256': hashlib.sha256(extractor.read_bytes()).hexdigest()}
    scripts = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
               for p in Path(__file__).parent.glob('*.py')}
    fingerprint = digest({'config': cfg, 'prompt': prompt, 'version': VERSION,
                          'scripts': scripts, 'mode': mode, 'pool_hint': video.get('pool_hint', '不确定')})
    folder = output / fingerprint / vid / digest(signature)
    task_path = folder / 'task.json'
    if task_path.exists():
        task = read(task_path)
        if all(Path(p).is_file() for p in task['overviews']):
            return folder, task
    cache = folder / 'frames'
    cache.mkdir(parents=True, exist_ok=True)
    # Keep stdout/stderr local: ffmpeg errors can contain private filenames.
    with (folder / 'extract.log').open('wb') as log:
        subprocess.run([sys.executable, str(extractor), str(source), '-o', str(cache),
                        '--cols', '3', '--sheet-max-cells', '12', '--sheet-width', '1600',
                        '-q', '--json'], stdout=log, stderr=log, check=True)
    meta = read(cache / 'keyframes.json')
    if not meta.get('overviews'):
        raise ValueError('No overview')
    task = {'video_id': vid, 'source_signature': signature, 'config': cfg,
            'fingerprint': fingerprint, 'mode': mode, 'prompt': prompt,
            'pool_hint': video.get('pool_hint', '不确定'),
            'frames': meta.get('frames', meta.get('keyframes', [])),
            'overviews': meta['overviews'], 'keyframes_path': str(cache / 'keyframes.json')}
    save(task_path, task)
    return folder, task


def local(folder, task):
    from image_tagger import Tagger
    cfg = task['config']
    address = urlparse(cfg['ollama_url'])
    if address.scheme not in ('http', 'https') or address.hostname not in ('localhost', '127.0.0.1', '::1'):
        raise ValueError('Local mode requires loopback Ollama')
    name = cfg['image_models'].get(task['pool_hint'], 'wd-swinv2-v3')
    image_path = folder / 'image.json'
    if image_path.exists():
        image = read(image_path)
    else:
        image = Tagger(name, cfg).run(task, folder / 'image_scores')
        save(image_path, image)
    raw_path = folder / 'vlm.json'
    if raw_path.exists():
        raw = read(raw_path)
    else:
        payload = {'model': cfg['local_model'], 'stream': False, 'think': False, 'format': 'json',
                   'messages': [{'role': 'user', 'content': task['prompt'],
                                 'images': [base64.b64encode(Path(p).read_bytes()).decode() for p in task['overviews']]}],
                   'options': {'temperature': 0, 'num_ctx': cfg['num_ctx'], 'num_predict': cfg['num_predict']}}
        req = urllib.request.Request(cfg['ollama_url'].rstrip('/') + '/api/chat',
                                     data=json.dumps(payload).encode(), headers={'Content-Type': 'application/json'})
        with urllib.request.urlopen(req, timeout=600) as response:
            raw = json.load(response)
        save(raw_path, raw)
    prediction = json.loads(raw['message']['content'])
    prediction_valid(prediction)
    save(folder / 'result.json', {'video_id': task['video_id'], 'model': name + ' + ' + cfg['local_model'],
                                 'prediction': prediction, 'image_candidates': image,
                                 'task_path': str(folder / 'task.json')})


def ingest(answer, output, cfg):
    output = output.resolve()
    path = Path(answer['task_path']).resolve()
    if not path.is_relative_to(output) or path.name != 'task.json':
        raise ValueError('Task outside output')
    task = read(path)
    if task['mode'] != 'prepare' or any(task['config'].get(k) != v for k, v in cfg.items()):
        raise ValueError('Task configuration mismatch')
    if not cfg.get('allow_online_images') or answer.get('model') != cfg.get('online_model'):
        raise ValueError('Online model or permission mismatch')
    folder = path.parent
    raw_path = folder / ('answer-' + digest(answer) + '.json')
    if not raw_path.exists():
        save(raw_path, answer)
    prediction_valid(answer['prediction'])
    result_path = folder / 'result.json'
    result = {'video_id': task['video_id'], 'model': answer['model'], 'prediction': answer['prediction'],
              'usage': answer.get('usage'), 'raw_path': str(raw_path), 'task_path': str(path)}
    if result_path.exists() and read(result_path) != result:
        raise ValueError('Existing result differs; retain alternate raw answer for review')
    save(result_path, result)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('mode', choices=['prepare', 'local', 'import'])
    p.add_argument('--manifest', type=Path)
    p.add_argument('--answers', type=Path)
    p.add_argument('--config', type=Path, required=True)
    p.add_argument('--prompt', type=Path, default=ASSETS / 'prompt.txt')
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    cfg = load_config(a.config)
    output = a.output.resolve()
    if a.mode in ('prepare', 'import') and (not cfg.get('allow_online_images') or not cfg.get('online_model')):
        raise ValueError('Online selection and actual model required')
    if a.mode == 'local' and (not cfg.get('local_model') or not cfg.get('model_revision')):
        raise ValueError('Choose a local model and record its installed revisions before execution')
    data = read(a.answers if a.mode == 'import' else a.manifest)
    if not isinstance(data, list):
        raise ValueError('Input must be array')
    if a.mode != 'import':
        ids = [v['video_id'] for v in data]
        if len(ids) != len(set(ids)):
            raise ValueError('Duplicate video ID')
    failures = 0
    progress = []
    for index, item in enumerate(data):
        try:
            if a.mode == 'import':
                item = dict(item)
                item['task_path'] = str(resolve_path(item['task_path'], a.answers.resolve().parent))
                ingest(item, output, cfg)
            else:
                bound = bind_video(item, cfg, a.manifest.resolve().parent)
                folder, task = task_for(bound, cfg, a.prompt.read_text(encoding='utf-8'), output, a.mode)
                if a.mode == 'local' and not (folder / 'result.json').exists():
                    local(folder, task)
            status = {'item': index + 1, 'status': 'ready' if a.mode == 'prepare' else 'done'}
        except Exception as error:
            failures += 1
            # Do not serialize exception text: it may contain media paths or tag text.
            status = {'item': index + 1, 'status': 'error', 'error_type': type(error).__name__}
        progress.append(status)
        save(output / ('progress-' + digest({'mode': a.mode, 'input': data, 'config': cfg}) + '.json'), progress, replace=True)
        print(json.dumps(status), flush=True)
    return bool(failures)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        print(json.dumps({'status': 'error', 'error_type': type(error).__name__}))
        sys.exit(1)
