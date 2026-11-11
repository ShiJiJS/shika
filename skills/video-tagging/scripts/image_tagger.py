"""JoyTag / WD SwinV2本地前向及候选分数保存。"""
from pathlib import Path
import csv
import json
import numpy as np
from PIL import Image
import onnxruntime as ort




class Tagger:
    def __init__(self, name, config):
        self.name, self.config = name, config
        root = Path(config['model_root'])
        folder = root / name
        if name == 'joytag':
            self.labels = (folder / 'top_tags.txt').read_text(encoding='utf-8').splitlines()
            roles = set()
            for csv_path in root.glob('wd-*/selected_tags.csv'):
                with csv_path.open(encoding='utf-8') as handle:
                    roles.update(r['name'] for r in csv.DictReader(handle) if r['category'] == '4')
            if not roles:
                raise ValueError('WD character vocabulary required for JoyTag')
            self.categories = ['character' if tag in roles else 'general' for tag in self.labels]
        else:
            with (folder / 'selected_tags.csv').open(encoding='utf-8') as handle:
                rows = list(csv.DictReader(handle))
            self.labels = [r['name'] for r in rows]
            self.categories = [{'0': 'general', '4': 'character', '9': 'rating'}.get(r['category'], 'other') for r in rows]
        options = ort.SessionOptions()
        options.intra_op_num_threads, options.inter_op_num_threads = 4, 1
        self.session = ort.InferenceSession(str(folder / 'model.onnx'), sess_options=options, providers=['CPUExecutionProvider'])

    def prepare(self, path):
        with Image.open(path) as source:
            image = source.convert('RGB')
        side = max(image.size)
        square = Image.new('RGB', (side, side), 'white')
        square.paste(image, ((side - image.width) // 2, (side - image.height) // 2))
        array = np.asarray(square.resize((448, 448), Image.Resampling.BICUBIC), dtype=np.float32)
        if self.name != 'joytag':
            return array[:, :, ::-1][None].copy()
        array = (array / 255 - np.array([.48145466, .4578275, .40821073], np.float32)) / np.array([.26862954, .26130258, .27577711], np.float32)
        return array.transpose(2, 0, 1)[None].copy()

    def run(self, case, folder):
        folder = Path(folder)
        folder.mkdir(parents=True, exist_ok=True)
        matrix, frames, candidates = [], [], {}
        for frame in case['frames']:
            output = self.session.run(None, {self.session.get_inputs()[0].name: self.prepare(frame['path'])})[0][0]
            scores = 1 / (1 + np.exp(-np.clip(output, -80, 80))) if self.name == 'joytag' else output
            matrix.append(scores.astype(np.float32))
            selected = []
            for index in np.argsort(scores)[::-1]:
                category, tag, score = self.categories[index], self.labels[index], float(scores[index])
                cutoff = self.config['image_thresholds']['character' if category == 'character' else self.name]
                if category not in {'general', 'character'} or score < cutoff:
                    continue
                item = {'tag': tag, 'category': category, 'score': score}
                selected.append(item)
                value = candidates.setdefault((category, tag), {'tag': tag, 'category': category, 'frames': [], 'max_score': score})
                value['frames'].append(frame['n'])
                value['max_score'] = max(value['max_score'], score)
                if len(selected) >= self.config['image_max_candidates_per_frame']:
                    break
            frames.append({'frame': frame['n'], 'candidates': selected})
        np.savez_compressed(folder / 'scores.npz', scores=np.stack(matrix))
        (folder / 'labels.json').write_text(json.dumps({'labels': self.labels, 'categories': self.categories}, ensure_ascii=False), encoding='utf-8')
        return {'video_id': case['video_id'], 'model': self.name, 'frames': frames, 'candidates': list(candidates.values())}
