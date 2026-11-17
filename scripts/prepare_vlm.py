"""Prepara el VLM local (SmolVLM-256M-Instruct, Apache-2.0) para leer croquis en Herrero.

- Descarga de Hugging Face los ONNX int8 (codificador de imagen, embeddings y
  decodificador con caché KV) y el tokenizador.
- Si el IR es más nuevo que el que admite ONNX Runtime 1.15 (el de la app), lo
  rebaja a IR 8.
- Dibuja un croquis de prueba (512 x 512, sin reescalado) y genera la
  respuesta de referencia con el mismo bucle que usa la app (pasado ficticio de
  longitud 1 enmascarado), comprobando que coincide con el bucle estándar.
- Escribe out_vlm/ con los ficheros, el croquis de prueba y manifest.json
  (tamaño + SHA-256, configuración y vectores de prueba para la app).

Uso: python scripts/prepare_vlm.py           (descarga + referencia)
     python scripts/prepare_vlm.py --verify  (repite con ORT 1.15 y compara)
"""
import hashlib, json, os, shutil, sys, time

import numpy as np
import onnxruntime as ort
from PIL import Image, ImageDraw, ImageFont

OUT = 'out_vlm'
# (prefijo de ficheros, repositorio). 256M: móviles; 500M: PC y móviles potentes.
MODELS = [
    ('smolvlm', 'HuggingFaceTB/SmolVLM-256M-Instruct'),
    ('smolvlm500', 'HuggingFaceTB/SmolVLM-500M-Instruct'),
]
PARTS = {
    'vision_int8.onnx': 'onnx/vision_encoder_quantized.onnx',
    'embed_int8.onnx': 'onnx/embed_tokens_quantized.onnx',
    'decoder_int8.onnx': 'onnx/decoder_model_merged_quantized.onnx',
    'tokenizer.json': 'tokenizer.json',
    'config.json': 'config.json',
}
QUESTIONS = [
    'Which steel structure is drawn: a carport, warehouse, staircase, railing, gate, mezzanine, '
    'footbridge, tower, truss, shelving, fence, pole or portal frame? Name it, say how many columns '
    'it has, what the roof is made of and which dimensions are written.',
    'Describe this sketch of a steel structure: what type of structure is it, '
    'how many columns and beams does it have, and which dimensions are written on it?',
    'What is drawn in this technical sketch? Answer briefly.',
]
MAX_NEW = 96


def font(size):
    for f in ('DejaVuSans.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'):
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            pass
    return ImageFont.load_default(size=size)


def sketch():
    """Croquis a mano alzada de una marquesina con cotas."""
    img = Image.new('RGB', (512, 512), 'white')
    d = ImageDraw.Draw(img)
    k = (30, 30, 30)
    # pilares y viga
    d.line([(110, 400), (112, 170)], fill=k, width=5)
    d.line([(400, 400), (398, 160)], fill=k, width=5)
    d.line([(80, 172), (430, 156)], fill=k, width=5)
    # cubierta
    d.line([(70, 150), (440, 134)], fill=k, width=3)
    for x in range(90, 430, 40):  # correas
        d.line([(x, 150 - (x - 70) * 16 / 370), (x + 6, 170 - (x - 70) * 16 / 370)], fill=k, width=2)
    # suelo
    d.line([(60, 402), (450, 402)], fill=k, width=2)
    for x in range(60, 450, 18):
        d.line([(x, 402), (x - 10, 414)], fill=k, width=1)
    # cotas
    d.line([(110, 450), (400, 450)], fill=k, width=1)
    d.line([(110, 440), (110, 460)], fill=k, width=1)
    d.line([(400, 440), (400, 460)], fill=k, width=1)
    d.text((215, 458), '5,50 m', fill=k, font=font(26))
    d.line([(470, 160), (470, 400)], fill=k, width=1)
    d.text((440, 265), '2,40', fill=k, font=font(24))
    d.text((150, 40), 'MARQUESINA 2 COCHES', fill=k, font=font(24))
    d.text((170, 80), 'panel sandwich', fill=k, font=font(22))
    return img


def sessions(prefix):
    so = ort.SessionOptions()
    so.intra_op_num_threads = 4
    mk = lambda f: ort.InferenceSession(f'{OUT}/{prefix}_{f}', so, providers=['CPUExecutionProvider'])
    return mk('vision_int8.onnx'), mk('embed_int8.onnx'), mk('decoder_int8.onnx')


def pixels(img):
    x = np.asarray(img.convert('RGB'), dtype=np.float32) / 255.0
    x = (x - 0.5) / 0.5
    return x.transpose(2, 0, 1)[None, None].astype(np.float32)  # [1,1,3,512,512]


def generate(vis, emb, dec, cfg, ids, pv, dummy_past=True):
    """Decodificación voraz con caché KV. dummy_past: la app no puede crear
    tensores vacíos, así que empieza con un pasado de longitud 1 enmascarado."""
    t = cfg['text_config']
    L, H, D = t['num_hidden_layers'], t['num_key_value_heads'], t.get('head_dim', t['hidden_size'] // t['num_attention_heads'])
    vin = {i.name: i for i in vis.get_inputs()}
    feed = {'pixel_values': pv}
    if 'pixel_attention_mask' in vin:
        feed['pixel_attention_mask'] = np.ones((1, 1, 512, 512), dtype=bool)
    feats = vis.run(None, feed)[0].reshape(-1, t['hidden_size'])
    ids = np.asarray(ids, dtype=np.int64)[None]
    e = emb.run(None, {'input_ids': ids})[0]
    pos_img = np.where(ids[0] == cfg['image_token_id'])[0]
    assert len(pos_img) == feats.shape[0], (len(pos_img), feats.shape)
    e[0, pos_img] = feats
    p0 = 1 if dummy_past else 0
    past = {}
    for i in range(L):
        for kv in ('key', 'value'):
            past[f'past_key_values.{i}.{kv}'] = np.zeros((1, H, p0, D), np.float32)
    mask = [0] * p0 + [1] * ids.shape[1]
    pos = np.arange(ids.shape[1], dtype=np.int64)[None]
    out_ids = []
    eos = {t['eos_token_id'], 49279}
    for step in range(MAX_NEW):
        feed = {'inputs_embeds': e, 'attention_mask': np.asarray([mask], np.int64), 'position_ids': pos, **past}
        outs = dec.run(None, feed)
        names = [o.name for o in dec.get_outputs()]
        logits = outs[names.index('logits')][0, -1]
        nxt = int(np.argmax(logits))
        out_ids.append(nxt)
        if nxt in eos:
            break
        for n, v in zip(names, outs):
            if n.startswith('present'):
                past[n.replace('present', 'past_key_values')] = v
        e = emb.run(None, {'input_ids': np.asarray([[nxt]], np.int64)})[0]
        mask.append(1)
        pos = np.asarray([[pos[0, -1] + 1]], np.int64)
    return out_ids


def _rank_of(model, name):
    import onnx
    for vi in list(model.graph.value_info) + list(model.graph.input) + list(model.graph.output):
        if vi.name == name and vi.type.tensor_type.HasField('shape'):
            return len(vi.type.tensor_type.shape.dim)
    return None


def decompose_contrib(path):
    """ONNX Runtime 1.15 (el de la app) no tiene com.microsoft:RotaryEmbedding.
    Se sustituye por operadores estándar (no intercalado):
    out = [x1*cos - x2*sin, x2*cos + x1*sin] con cos/sin = cache[position_ids]."""
    import onnx
    from onnx import helper, TensorProto, numpy_helper
    m = onnx.load(path)
    try:
        inf = onnx.shape_inference.infer_shapes(m)
    except Exception as e:  # noqa: BLE001
        print('  sin inferencia de formas:', e)
        inf = m
    g = m.graph
    producers = {o: n for n in g.node for o in n.output}
    new_nodes = []
    consts = {}

    def const(name, arr):
        if name not in consts:
            consts[name] = numpy_helper.from_array(np.asarray(arr), name)
        return name

    n_rot = 0
    for node in g.node:
        if not (node.domain == 'com.microsoft' and node.op_type == 'RotaryEmbedding'):
            new_nodes.append(node)
            continue
        attrs = {a.name: helper.get_attribute_value(a) for a in node.attribute}
        assert int(attrs.get('interleaved', 0)) == 0, attrs
        x, pos, cos_c, sin_c = node.input[:4]
        y = node.output[0]
        rank = _rank_of(inf, x)
        prod = producers.get(x)
        if rank is None:
            rank = 4 if (prod is not None and prod.op_type == 'Transpose') else 3
        if n_rot == 0:
            print('  RotaryEmbedding', attrs, 'rango', rank, 'productor', prod.op_type if prod else None)
        k = f'{node.name or y}_rot'
        nn = lambda op, ins, outs, **kw: new_nodes.append(helper.make_node(op, ins, outs, name=f'{k}_{op}_{len(new_nodes)}', **kw))
        nn('Gather', [cos_c, pos], [f'{k}_cos'], axis=0)  # (b, s, d/2)
        nn('Gather', [sin_c, pos], [f'{k}_sin'], axis=0)
        if rank == 4:  # (b, h, s, d)
            ax = const('rot_ax1', np.array([1], np.int64))
            nn('Unsqueeze', [f'{k}_cos', ax], [f'{k}_c'])
            nn('Unsqueeze', [f'{k}_sin', ax], [f'{k}_s'])
            xin = x
        else:  # (b, s, h*d) -> (b, s, h, d)
            ax = const('rot_ax2', np.array([2], np.int64))
            nn('Unsqueeze', [f'{k}_cos', ax], [f'{k}_c'])
            nn('Unsqueeze', [f'{k}_sin', ax], [f'{k}_s'])
            nn('Shape', [cos_c], [f'{k}_cshape'])
            nn('Slice', [f'{k}_cshape', const('rot_i1', np.array([1], np.int64)), const('rot_i2', np.array([2], np.int64))], [f'{k}_half'])
            nn('Mul', [f'{k}_half', const('rot_two', np.array([2], np.int64))], [f'{k}_dim'])
            nn('Concat', [const('rot_00', np.array([0, 0, -1], np.int64)), f'{k}_dim'], [f'{k}_r4'], axis=0)
            nn('Reshape', [x, f'{k}_r4'], [f'{k}_x4'])
            nn('Shape', [x], [f'{k}_xshape'])
            xin = f'{k}_x4'
        # mitades del último eje
        nn('Shape', [f'{k}_c'], [f'{k}_cs'])
        nn('Slice', [f'{k}_cs', const('rot_m1', np.array([-1], np.int64)), const('rot_big', np.array([2**62], np.int64))], [f'{k}_h'])
        nn('Slice', [xin, const('rot_z', np.array([0], np.int64)), f'{k}_h', const('rot_m1', np.array([-1], np.int64))], [f'{k}_x1'])
        nn('Mul', [f'{k}_h', const('rot_two', np.array([2], np.int64))], [f'{k}_d'])
        nn('Slice', [xin, f'{k}_h', f'{k}_d', const('rot_m1', np.array([-1], np.int64))], [f'{k}_x2'])
        nn('Mul', [f'{k}_x1', f'{k}_c'], [f'{k}_a1'])
        nn('Mul', [f'{k}_x2', f'{k}_s'], [f'{k}_a2'])
        nn('Sub', [f'{k}_a1', f'{k}_a2'], [f'{k}_o1'])
        nn('Mul', [f'{k}_x2', f'{k}_c'], [f'{k}_b1'])
        nn('Mul', [f'{k}_x1', f'{k}_s'], [f'{k}_b2'])
        nn('Add', [f'{k}_b1', f'{k}_b2'], [f'{k}_o2'])
        # parte no rotada (si rotary_embedding_dim < head_size)
        nn('Slice', [xin, f'{k}_d', const('rot_big', np.array([2**62], np.int64)), const('rot_m1', np.array([-1], np.int64))], [f'{k}_rest'])
        if rank == 4:
            nn('Concat', [f'{k}_o1', f'{k}_o2', f'{k}_rest'], [y], axis=-1)
        else:
            nn('Concat', [f'{k}_o1', f'{k}_o2', f'{k}_rest'], [f'{k}_y4'], axis=-1)
            nn('Reshape', [f'{k}_y4', f'{k}_xshape'], [y])
        n_rot += 1
    del g.node[:]
    g.node.extend(new_nodes)
    g.initializer.extend(consts.values())
    left = sorted({(n.domain, n.op_type) for n in g.node if n.domain not in ('', 'ai.onnx')})
    print(f'  {n_rot} RotaryEmbedding sustituidos; operadores no estándar restantes: {left}')
    onnx.save(m, path)


def prepare(prefix, repo, img, tests_out):
    from huggingface_hub import hf_hub_download
    import onnx
    for dst, src in PARTS.items():
        dst = f'{prefix}_{dst}'
        p = hf_hub_download(repo, src)
        shutil.copy(p, f'{OUT}/{dst}')
        if dst.endswith('.onnx'):
            m = onnx.load(f'{OUT}/{dst}')
            ops = sorted({(n.domain, n.op_type) for n in m.graph.node if n.domain not in ('', 'ai.onnx')})
            print(dst, 'IR', m.ir_version, 'opsets', [(o.domain, o.version) for o in m.opset_import], 'no estándar', ops)
            if m.ir_version > 8:
                m.ir_version = 8
                onnx.save(m, f'{OUT}/{dst}')
                print('  -> IR 8')
            if any(o == ('com.microsoft', 'RotaryEmbedding') for o in ops):
                ref = ort.InferenceSession(f'{OUT}/{dst}', providers=['CPUExecutionProvider'])
                decompose_contrib(f'{OUT}/{dst}')
                check_same(ref, f'{OUT}/{dst}')
    cfg = json.load(open(f'{OUT}/{prefix}_config.json'))
    from transformers import AutoProcessor
    proc = AutoProcessor.from_pretrained(repo)
    proc.image_processor.do_image_splitting = False
    vis, emb, dec = sessions(prefix)
    for s_, name in ((vis, 'vision'), (emb, 'embed'), (dec, 'decoder')):
        print(name, 'in', [(i.name, i.shape, i.type) for i in s_.get_inputs()][:4])
    from tokenizers import Tokenizer
    tok = Tokenizer.from_file(f'{OUT}/{prefix}_tokenizer.json')
    pv = pixels(img)
    for q in QUESTIONS:
        msgs = [{'role': 'user', 'content': [{'type': 'image'}, {'type': 'text', 'text': q}]}]
        prompt = proc.apply_chat_template(msgs, add_generation_prompt=True)
        inp = proc(text=prompt, images=[img], return_tensors='np')
        ids = inp['input_ids'][0].tolist()
        expanded = proc.tokenizer.decode(ids)
        t0 = time.time()
        a = generate(vis, emb, dec, cfg, ids, pv, dummy_past=True)
        dt = time.time() - t0
        b = generate(vis, emb, dec, cfg, ids, pv, dummy_past=False)
        text = tok.decode(a, skip_special_tokens=True)
        print(f'[{prefix}] P: {q[:60]}…\n  R ({len(a)} tokens, {dt:.1f} s): {text!r}')
        print('  igual al bucle estándar:', a == b)
        assert len(a) > 3 and a[:8] == b[:8], 'el pasado enmascarado no coincide'
        tests_out.append({'model': prefix, 'question': q, 'prompt': prompt, 'expanded': expanded,
                          'prompt_ids': ids, 'output_ids': a, 'output_text': text})
    tok_tests = []
    for s_ in ['Marquesina de 5,50 x 5 m y 2,40 m de alto', 'IPE 300 L=6000 mm', 'hello world  123\nnew line',
               'Ñandú pérgola acero S275JR ½" Ø16', '<|im_start|>User:<image>Hi<end_of_utterance>\nAssistant:']:
        tok_tests.append({'text': s_, 'ids': tok.encode(s_).ids})
    t = cfg['text_config']
    return {'image_token_id': cfg['image_token_id'], 'hidden': t['hidden_size'], 'layers': t['num_hidden_layers'],
            'kv_heads': t['num_key_value_heads'], 'tokenizer_tests': tok_tests}


def main():
    os.makedirs(OUT, exist_ok=True)
    img = sketch()
    img.save(f'{OUT}/vlm_test_sketch.png')
    tests, info = [], {}
    for prefix, repo in MODELS:
        info[prefix] = prepare(prefix, repo, img, tests)
    files = {}
    for n in sorted(os.listdir(OUT)):
        if n == 'manifest.json':
            continue
        p = os.path.join(OUT, n)
        files[n] = {'size': os.path.getsize(p), 'sha256': hashlib.sha256(open(p, 'rb').read()).hexdigest()}
    json.dump({'model': 'SmolVLM 256M / 500M Instruct (Hugging Face, Apache-2.0), ONNX uint8 de transformers.js; '
                        'RotaryEmbedding sustituido por operadores estándar para ONNX Runtime 1.15',
               'files': files, 'models': info, 'tests': tests},
              open(f'{OUT}/manifest.json', 'w'), indent=1, ensure_ascii=False)
    print(json.dumps(files, indent=1))


def check_same(ref, path):
    """Compara el decodificador original y el reescrito con datos aleatorios."""
    new = ort.InferenceSession(path, providers=['CPUExecutionProvider'])
    rng = np.random.default_rng(0)
    feed = {}
    for i in ref.get_inputs():
        shp = [d if isinstance(d, int) else 1 for d in i.shape]
        if i.name == 'inputs_embeds':
            shp[1] = 5
            feed[i.name] = rng.standard_normal(shp).astype(np.float32) * 0.1
        elif i.name == 'attention_mask':
            feed[i.name] = np.array([[0, 1, 1, 1, 1, 1]], np.int64)
        elif i.name == 'position_ids':
            feed[i.name] = np.array([[0, 1, 2, 3, 4]], np.int64)
        else:
            feed[i.name] = rng.standard_normal(shp).astype(np.float32) * 0.1
    a = ref.run(None, feed)
    b = new.run(None, feed)
    d = max(float(np.abs(x - y).max()) for x, y in zip(a, b))
    print('  diferencia máxima original/reescrito:', d)
    assert d < 1e-3, d


def verify():
    man = json.load(open(f'{OUT}/manifest.json'))
    print('ORT', ort.__version__)
    pv = pixels(Image.open(f'{OUT}/vlm_test_sketch.png'))
    for prefix, _ in MODELS:
        cfg = json.load(open(f'{OUT}/{prefix}_config.json'))
        vis, emb, dec = sessions(prefix)
        for t in man['tests']:
            if t['model'] != prefix:
                continue
            t0 = time.time()
            a = generate(vis, emb, dec, cfg, t['prompt_ids'], pv)
            print(f'[{prefix}] {len(a)} tokens en {time.time() - t0:.1f} s; coincide: {a == t["output_ids"]}')
            assert a[:8] == t['output_ids'][:8], (a, t['output_ids'])


if __name__ == '__main__':
    verify() if '--verify' in sys.argv else main()
