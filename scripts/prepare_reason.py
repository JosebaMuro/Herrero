"""Prepara los modelos de comprensión y razonamiento locales de Herrero.

- e5s: multilingual-e5-small (MIT), embeddings de frases (384) para reconocer
  la estructura pedida aunque se describa con otras palabras.
- qwen3: Qwen3-0.6B (Apache-2.0), LLM pequeño que convierte la petición en una
  ficha estructurada (móviles y PC).
- qwen3big: Qwen3-1.7B (Apache-2.0), la misma tarea con más calidad (PC).

Descarga de Hugging Face los ONNX cuantizados (uint8) de transformers.js, el
tokenizador y la configuración; comprueba que cargan y responden con
ONNX Runtime 1.20 (el de la app) y escribe out_reason/manifest.json con
tamaño y SHA-256 de cada fichero y vectores de prueba del tokenizador.

Uso: python scripts/prepare_reason.py
"""
import hashlib, json, os, shutil, time

import numpy as np
import onnxruntime as ort

OUT = 'out_reason'
MODELS = [
    # (prefijo, repositorio, fichero ONNX en el repositorio)
    ('e5s', 'Xenova/multilingual-e5-small', 'onnx/model_quantized.onnx'),
    ('qwen3', 'onnx-community/Qwen3-0.6B-ONNX', 'onnx/model_quantized.onnx'),
    ('qwen3big', 'onnx-community/Qwen3-1.7B-ONNX', 'onnx/model_quantized.onnx'),
]
TOKENIZER_TESTS = [
    'Marquesina para 2 coches de 5,5 x 5 m y 2,4 m de alto, panel sándwich, galvanizada',
    'nave a dos aguas de 30 x 15 m, 6 m al alero, en Vitoria',
    'IPE 300 L=6000 mm  HEB-200\nS275JR ½" Ø16 – pérgola',
    'Tejavana pa\' guardar el tractor, unos 8 metros de largo',
    '<|im_start|>user\nHola<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n{"tipo": "marquesina"}',
    'query: escalera metálica de caracol',
]


def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def fetch(prefix, repo, onnx_path):
    from huggingface_hub import hf_hub_download
    import onnx
    dst = f'{OUT}/{prefix}_model_int8.onnx'
    shutil.copy(hf_hub_download(repo, onnx_path), dst)
    for f in ('tokenizer.json', 'config.json'):
        shutil.copy(hf_hub_download(repo, f), f'{OUT}/{prefix}_{f}')
    m = onnx.load(dst, load_external_data=False)
    ops = sorted({(n.domain or 'ai.onnx', n.op_type) for n in m.graph.node})
    print(prefix, 'IR', m.ir_version, 'opsets', [(o.domain, o.version) for o in m.opset_import])
    print('  operadores:', ops)
    print('  entradas:', [(i.name, [d.dim_param or d.dim_value for d in i.type.tensor_type.shape.dim]) for i in m.graph.input][:6])
    print('  salidas:', [o.name for o in m.graph.output][:4])
    if m.ir_version > 10:  # ORT 1.20 lee hasta IR 10
        m = onnx.load(dst)
        m.ir_version = 10
        onnx.save(m, dst)
        print('  -> IR 10')
    del m


def check_e5(prefix):
    from tokenizers import Tokenizer
    tok = Tokenizer.from_file(f'{OUT}/{prefix}_tokenizer.json')
    s = ort.InferenceSession(f'{OUT}/{prefix}_model_int8.onnx', providers=['CPUExecutionProvider'])
    names = [i.name for i in s.get_inputs()]

    def emb(t):
        ids = tok.encode(t).ids
        feed = {'input_ids': np.asarray([ids], np.int64), 'attention_mask': np.ones((1, len(ids)), np.int64)}
        if 'token_type_ids' in names:
            feed['token_type_ids'] = np.zeros((1, len(ids)), np.int64)
        h = s.run(None, feed)[0][0]
        v = h.mean(0)
        return v / np.linalg.norm(v)

    q = emb('query: tejadillo para aparcar dos coches')
    docs = ['passage: Marquesina: cubierta ligera sobre pilares para aparcamiento de vehículos (carport).',
            'passage: Escalera metálica: zancas, peldaños y barandilla.',
            'passage: Nave industrial de pórticos a dos aguas.']
    sims = [float(q @ emb(d)) for d in docs]
    print(prefix, 'similitudes', [round(x, 3) for x in sims])
    assert int(np.argmax(sims)) == 0, sims
    return {'dim': int(q.shape[0]), 'reference': {'text': 'query: tejadillo para aparcar dos coches',
                                                   'ids': tok.encode('query: tejadillo para aparcar dos coches').ids,
                                                   'head': [round(float(x), 5) for x in q[:8]]}}


def check_llm(prefix):
    from tokenizers import Tokenizer
    cfg = json.load(open(f'{OUT}/{prefix}_config.json'))
    tok = Tokenizer.from_file(f'{OUT}/{prefix}_tokenizer.json')
    so = ort.SessionOptions()
    so.intra_op_num_threads = 4
    s = ort.InferenceSession(f'{OUT}/{prefix}_model_int8.onnx', so, providers=['CPUExecutionProvider'])
    L, H = cfg['num_hidden_layers'], cfg['num_key_value_heads']
    D = cfg.get('head_dim') or cfg['hidden_size'] // cfg['num_attention_heads']
    names = [i.name for i in s.get_inputs()]
    prompt = ('<|im_start|>user\nResponde solo con JSON {"tipo": ...}. ¿Qué estructura es '
              '"marquesina para dos coches"?<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n')
    ids = tok.encode(prompt).ids
    past = {f'past_key_values.{i}.{kv}': np.zeros((1, H, 0, D), np.float32) for i in range(L) for kv in ('key', 'value')}
    mask = [1] * len(ids)
    pos = list(range(len(ids)))
    out = []
    t0 = time.time()
    cur = ids
    for _ in range(24):
        feed = {'input_ids': np.asarray([cur], np.int64), 'attention_mask': np.asarray([mask], np.int64), **past}
        if 'position_ids' in names:
            feed['position_ids'] = np.asarray([pos[-len(cur):]], np.int64)
        res = s.run(None, feed)
        onames = [o.name for o in s.get_outputs()]
        nxt = int(np.argmax(res[onames.index('logits')][0, -1]))
        out.append(nxt)
        if nxt in (cfg.get('eos_token_id'), 151645, 151643):
            break
        for n, v in zip(onames, res):
            if n.startswith('present'):
                past[n.replace('present', 'past_key_values')] = v
        cur = [nxt]
        mask.append(1)
        pos.append(pos[-1] + 1)
    text = tok.decode(out)
    print(f'{prefix}: {len(out)} tokens en {time.time() - t0:.1f} s: {text!r}')
    assert len(out) > 2, 'respuesta vacía'
    if 'marquesina' not in text.lower():
        print('  AVISO: la respuesta de prueba no nombra la marquesina')
    return {'layers': L, 'kv_heads': H, 'head_dim': D, 'inputs': names[:3],
            'reference': {'prompt_ids': ids, 'output_ids': out, 'output_text': text}}


def main():
    os.makedirs(OUT, exist_ok=True)
    info = {}
    for prefix, repo, path in MODELS:
        fetch(prefix, repo, path)
        info[prefix] = check_e5(prefix) if prefix.startswith('e5') else check_llm(prefix)
        from tokenizers import Tokenizer
        tok = Tokenizer.from_file(f'{OUT}/{prefix}_tokenizer.json')
        info[prefix]['repo'] = repo
        info[prefix]['tokenizer_tests'] = [{'text': t, 'ids': tok.encode(t).ids} for t in TOKENIZER_TESTS]
    files = {n: {'size': os.path.getsize(f'{OUT}/{n}'), 'sha256': sha(f'{OUT}/{n}')}
             for n in sorted(os.listdir(OUT)) if n != 'manifest.json'}
    json.dump({'model': 'Comprensión y razonamiento locales de Herrero: multilingual-e5-small (MIT) y '
                        'Qwen3 0.6B / 1.7B (Apache-2.0), ONNX uint8 de transformers.js (ONNX Runtime 1.20)',
               'files': files, 'models': info},
              open(f'{OUT}/manifest.json', 'w'), indent=1, ensure_ascii=False)
    print(json.dumps(files, indent=1))


if __name__ == '__main__':
    main()
