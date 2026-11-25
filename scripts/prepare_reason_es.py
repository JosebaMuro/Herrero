"""Prepara la alternativa en castellano de la comprensión y el razonamiento.

- jinaes: jina-embeddings-v2-base-es (Jina AI, Apache-2.0). Embeddings
  bilingües castellano-inglés entrenados sobre todo con texto en español, en
  lugar del multilingual-e5-small (100 idiomas). int8, 162 MB.
- smollm3: SmolLM3-3B (Hugging Face, Apache-2.0). LLM de 3B con modo de
  razonamiento (<think>) y el castellano entre sus seis idiomas principales.
  Pesos a 4 bits (MatMulNBits), ~2,9 GB, para PC.

Descarga de Hugging Face los ONNX de transformers.js, los comprueba con
ONNX Runtime 1.20 (el de la app), compara los embeddings con e5-small sobre
peticiones coloquiales y prueba el razonamiento con descripciones complejas.
Escribe out_reason_es/ con manifest.json (tamaño y SHA-256, vectores de prueba
del tokenizador y salidas de referencia).

Los datos externos de más de 2 GB se reparten en trozos de menos de 1,9 GB
(límite de 2 GB por fichero de las releases de GitHub).

Uso: python scripts/prepare_reason_es.py            (prepara y publica)
     python scripts/prepare_reason_es.py --eval REPO  (solo prueba un LLM candidato)
"""
import hashlib, json, os, re, shutil, sys, time

import numpy as np
import onnxruntime as ort

OUT = 'out_reason_es'
CHUNK = 1_900_000_000

EMBED = ('jinaes', 'jinaai/jina-embeddings-v2-base-es', 'onnx/model_quantized.onnx')
E5 = ('e5s', 'Xenova/multilingual-e5-small', 'onnx/model_quantized.onnx')
LLM = ('smollm3', 'HuggingFaceTB/SmolLM3-3B-ONNX', 'onnx/model_q4.onnx')

TOKENIZER_TESTS = [
    'Marquesina para 2 coches de 5,5 x 5 m y 2,4 m de alto, panel sándwich, galvanizada',
    'nave a dos aguas de 30 x 15 m, 6 m al alero, en Vitoria',
    'IPE 300 L=6000 mm  HEB-200\nS275JR ½" Ø16 – pérgola',
    'Tejavana pa\' guardar el tractor, unos 8 metros de largo',
    '<|im_start|>user\nHola<|im_end|>\n<|im_start|>assistant\n<think>\nVale.\n</think>\n{"tipo": "marquesina"}',
    'escalera metálica de caracol con 1234567 peldaños',
    "It's CAN'T  dos  espacios\t\ttabulador ñandú ÁÉÍÓÚ ü",
]

# Descripciones complejas para el razonamiento (la tipología ya decidida).
LLM_CASES = [
    ('nave', 'Necesito una nave de 24 m de luz por 40 de fondo, con pórticos cada 5 metros, 7 m al alero y '
             'la cumbrera a 8,5, cubierta de panel sándwich de 30 mm, en un polígono de Burgos'),
    ('marquesina', 'Quiero cubrir el patio de 6 por 4 para dejar dos coches y la moto, con policarbonato; '
                   'la parte baja que quede a 2,20 y la alta a 2,60, todo pintado en negro'),
    ('entreplanta', 'Altillo dentro del almacén de 12 metros por 6, a 3 metros del suelo, para poner '
                    'estanterías con 500 kg por metro cuadrado, suelo de tramex y acabado galvanizado'),
]


def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def hf(repo, f):
    from huggingface_hub import hf_hub_download
    return hf_hub_download(repo, f)


def fetch(prefix, repo, onnx_path, out=OUT, extra=('tokenizer.json', 'config.json')):
    """Copia el ONNX (con sus datos externos, en trozos < 2 GB) y el tokenizador."""
    import onnx
    from onnx.external_data_helper import set_external_data
    src = hf(repo, onnx_path)
    base = os.path.basename(onnx_path)
    m = onnx.load(src, load_external_data=False)
    locs = sorted({e.value for t in m.graph.initializer for e in t.external_data if e.key == 'location'})
    for loc in locs:  # bajar los ficheros de datos externos junto al grafo
        hf(repo, f'{os.path.dirname(onnx_path)}/{loc}')
    name = f'{prefix}_model_{"q4" if "q4" in base else "int8"}.onnx'
    dst = f'{out}/{name}'
    if locs:
        m = onnx.load(src)  # con los pesos
        part, off, fh, parts = 0, 0, None, []

        def open_part(i):
            fn = f'{name}_data' + (f'_{i}' if i else '')
            parts.append(fn)
            return open(f'{out}/{fn}', 'wb'), fn

        fh, fn = open_part(0)
        for t in m.graph.initializer:
            raw = t.raw_data
            if len(raw) < 1024:
                continue
            if off and off + len(raw) > CHUNK:
                fh.close()
                part += 1
                off = 0
                fh, fn = open_part(part)
            fh.write(raw)
            set_external_data(t, location=fn, offset=off, length=len(raw))
            t.data_location = onnx.TensorProto.EXTERNAL
            t.ClearField('raw_data')
            off += len(raw)
            pad = (-off) % 4096  # alineado para mmap
            fh.write(b'\0' * pad)
            off += pad
        fh.close()
        if m.ir_version > 10:
            m.ir_version = 10
        onnx.save(m, dst)
        print(prefix, 'datos externos:', [(p, os.path.getsize(f'{out}/{p}')) for p in parts])
    else:
        shutil.copy(src, dst)
        if m.ir_version > 10:  # ORT 1.20 lee hasta IR 10
            m = onnx.load(dst)
            m.ir_version = 10
            onnx.save(m, dst)
    for f in extra:
        shutil.copy(hf(repo, f), f'{out}/{prefix}_{f}')
    g = onnx.load(dst, load_external_data=False)
    ops = sorted({(n.domain or 'ai.onnx', n.op_type) for n in g.graph.node})
    print(prefix, 'IR', g.ir_version, 'opsets', [(o.domain, o.version) for o in g.opset_import])
    print('  operadores:', ops)
    print('  entradas:', [(i.name, [d.dim_param or d.dim_value for d in i.type.tensor_type.shape.dim]) for i in g.graph.input][:6])
    print('  salidas:', [o.name for o in g.graph.output][:4])
    return dst


# ---------------------------------------------------------------------------
# Embeddings: jina-es frente a e5-small con las peticiones de las pruebas
# ---------------------------------------------------------------------------

def dart_strings(block):
    return [s.replace("\\'", "'") for s in re.findall(r"'((?:[^'\\]|\\.)*)'", block)]


def intents():
    """Frases de ejemplo de cada tipología (lib/engine/intents.dart)."""
    src = open('lib/engine/intents.dart', encoding='utf-8').read()
    out = []
    for m in re.finditer(r'StructureType\.(\w+):\s*\[(.*?)\]', src, re.S):
        for s in dart_strings(m.group(2)):
            out.append((m.group(1), s))
    return out


def labels():
    src = open('lib/engine/model.dart', encoding='utf-8').read()
    src = src[src.index('String get label'):]
    return dict(re.findall(r"case StructureType\.(\w+):\s*return '([^']+)'", src[:src.index('\n  }\n')]))


def test_requests():
    """Peticiones coloquiales y sin palabras del catálogo (test/reason_test.dart)."""
    src = open('test/reason_test.dart', encoding='utf-8').read()
    return [(t, s) for t, s in re.findall(r"\(StructureType\.(\w+),\s*'((?:[^'\\]|\\.)*)'\)", src)]


class Embedder:
    def __init__(self, prefix, query='', passage=''):
        from tokenizers import Tokenizer
        self.tok = Tokenizer.from_file(f'{OUT}/{prefix}_tokenizer.json')
        name = [f for f in os.listdir(OUT) if f.startswith(prefix + '_model') and f.endswith('.onnx')][0]
        self.s = ort.InferenceSession(f'{OUT}/{name}', providers=['CPUExecutionProvider'])
        self.names = [i.name for i in self.s.get_inputs()]
        self.query, self.passage = query, passage

    def __call__(self, t):
        ids = self.tok.encode(t).ids[:512]
        feed = {'input_ids': np.asarray([ids], np.int64), 'attention_mask': np.ones((1, len(ids)), np.int64)}
        if 'token_type_ids' in self.names:
            feed['token_type_ids'] = np.zeros((1, len(ids)), np.int64)
        v = self.s.run(None, feed)[0][0].mean(0)
        return v / np.linalg.norm(v)


def eval_embed(e):
    lab = labels()
    passages = [(t, e.passage + s) for t, s in intents()] + [(t, e.passage + l) for t, l in lab.items()]
    pv = np.stack([e(p) for _, p in passages])
    ok, rows = 0, []
    reqs = test_requests()
    t0 = time.time()
    for exp, q in reqs:
        sims = pv @ e(e.query + q)
        per = {}
        for (t, _), s in zip(passages, sims):
            per.setdefault(t, []).append(float(s))
        rank = sorted(((sum(sorted(v)[-2:]) / len(sorted(v)[-2:]), t) for t, v in per.items()), reverse=True)
        hit = rank[0][1] == exp
        ok += hit
        rows.append(f'  {"OK" if hit else "XX"} {rank[0][1]:<12} {rank[0][0]:.3f} / {rank[1][1]} {rank[1][0]:.3f}  {q}')
    print('\n'.join(rows))
    print(f'  acierto: {ok}/{len(reqs)} ({(time.time() - t0) / len(reqs) * 1000:.0f} ms por petición)')
    return ok, len(reqs)


def check_embed(prefix):
    from tokenizers import Tokenizer
    tok = Tokenizer.from_file(f'{OUT}/{prefix}_tokenizer.json')
    e = Embedder(prefix)
    q = e('tejadillo para aparcar dos coches')
    ok, n = eval_embed(e)
    return {'dim': int(q.shape[0]), 'query_prefix': '', 'passage_prefix': '', 'accuracy': [ok, n],
            'reference': {'text': 'tejadillo para aparcar dos coches',
                          'ids': tok.encode('tejadillo para aparcar dos coches').ids,
                          'head': [round(float(x), 5) for x in q[:8]]}}


# ---------------------------------------------------------------------------
# LLM con razonamiento
# ---------------------------------------------------------------------------

SYSTEM = ('Eres el asistente de una oficina técnica de estructuras metálicas. Lee la petición del '
          'cliente y completa la ficha JSON con lo que diga el texto. Omite lo que no diga.\n'
          'Campos: largo_m, ancho_m, alto_m (metros); cubierta (panel sándwich, chapa grecada, policarbonato, teja, '
          'vidrio, tramex o sin cubierta); acero (S235JR, S275JR, S355JR, corten, inoxidable o aluminio); acabado '
          '(galvanizado, pintado o lacado); ubicacion (ciudad o provincia); uso (para qué es); carga_kg_m2; niveles.\n'
          'Antes de responder, razona en castellano y en pocas líneas: qué medida es cada número (largo, ancho, '
          'alto, luz, separación), las unidades y qué dato no aparece. Luego escribe solo la ficha JSON.')


def think_chat(prompt, tipo):
    """Formato de SmolLM3 / Qwen3 con razonamiento: el modelo piensa y luego se fuerza la ficha."""
    return (f'<|im_start|>system\n## Metadata\n\nReasoning Mode: /think\n\n## Custom Instructions\n\n{SYSTEM}\n\n'
            f'<|im_end|>\n<|im_start|>user\nPetición: {prompt}<|im_end|>\n<|im_start|>assistant\n<think>\n')


class Llm:
    def __init__(self, prefix, out=OUT):
        from tokenizers import Tokenizer
        self.cfg = json.load(open(f'{out}/{prefix}_config.json'))
        self.tok = Tokenizer.from_file(f'{out}/{prefix}_tokenizer.json')
        so = ort.SessionOptions()
        so.intra_op_num_threads = 4
        name = [f for f in os.listdir(out) if f.startswith(prefix + '_model') and f.endswith('.onnx')][0]
        self.s = ort.InferenceSession(f'{out}/{name}', so, providers=['CPUExecutionProvider'])
        c = self.cfg
        self.L, self.H = c['num_hidden_layers'], c['num_key_value_heads']
        self.D = c.get('head_dim') or c['hidden_size'] // c['num_attention_heads']
        self.names = [i.name for i in self.s.get_inputs()]
        self.onames = [o.name for o in self.s.get_outputs()]
        v = self.tok.get_vocab()
        self.eos = {v[k] for k in ('<|im_end|>', '<|endoftext|>', '<|end_of_text|>') if k in v}
        eos = c.get('eos_token_id')
        self.eos |= set(eos if isinstance(eos, list) else [eos] if eos is not None else [])
        self.think_end = v.get('</think>')

    def generate(self, text, think_budget=384, after_think='', max_answer=120):
        ids = self.tok.encode(text).ids
        past = {f'past_key_values.{i}.{kv}': np.zeros((1, self.H, 0, self.D), np.float32)
                for i in range(self.L) for kv in ('key', 'value')}
        done = 0

        def step(chunk):
            nonlocal past, done
            n = len(chunk)
            feed = {'input_ids': np.asarray([chunk], np.int64),
                    'attention_mask': np.ones((1, done + n), np.int64), **past}
            if 'position_ids' in self.names:
                feed['position_ids'] = np.asarray([list(range(done, done + n))], np.int64)
            res = self.s.run(None, feed)
            for nm, val in zip(self.onames, res):
                if nm.startswith('present'):
                    past[nm.replace('present', 'past_key_values')] = val
            done += n
            return res[self.onames.index('logits')][0, -1]

        t0 = time.time()
        for i in range(0, len(ids), 64):
            logits = step(ids[i:i + 64])
        prefill = time.time() - t0
        thought, answer, thinking = [], [], True
        while True:
            nxt = int(np.argmax(logits))
            if thinking:
                if nxt == self.think_end or len(thought) >= think_budget or nxt in self.eos:
                    thinking = False
                    forced = self.tok.encode('\n</think>\n' + after_think, add_special_tokens=False).ids
                    logits = step(forced)
                    continue
                thought.append(nxt)
            else:
                if nxt in self.eos or len(answer) >= max_answer:
                    break
                answer.append(nxt)
                if '}' in self.tok.decode([nxt]):
                    break
            logits = step([nxt])
        dt = time.time() - t0
        return {'prompt_ids': ids, 'thought_ids': thought, 'answer_ids': answer,
                'thought': self.tok.decode(thought), 'answer': after_think + self.tok.decode(answer),
                'prefill_s': round(prefill, 1), 'total_s': round(dt, 1),
                'tok_s': round((len(thought) + len(answer)) / max(dt - prefill, 1e-3), 1)}


def check_llm(prefix, out=OUT):
    llm = Llm(prefix, out)
    print(prefix, 'capas', llm.L, 'kv', llm.H, 'head_dim', llm.D, 'eos', llm.eos, '</think>', llm.think_end)
    refs = []
    for tipo, p in LLM_CASES:
        seed = '{"tipo": "%s", "' % tipo
        r = llm.generate(think_chat(p, tipo), after_think=seed)
        print(f'\n=== {p}\n--- razonamiento ({len(r["thought_ids"])} tokens):\n{r["thought"]}\n--- ficha: {r["answer"]}')
        print(f'    prompt {len(r["prompt_ids"])} tokens en {r["prefill_s"]} s; total {r["total_s"]} s; {r["tok_s"]} tokens/s')
        try:
            j = json.loads(r['answer'].replace(',}', '}'))
            print('    JSON válido:', j)
        except Exception as e:
            print('    AVISO: JSON no válido:', e)
        refs.append({'tipo': tipo, 'prompt': p, **{k: r[k] for k in ('prompt_ids', 'thought_ids', 'answer_ids', 'answer', 'total_s', 'tok_s')}})
    assert any(len(x['answer_ids']) > 3 for x in refs), 'respuestas vacías'
    return {'layers': llm.L, 'kv_heads': llm.H, 'head_dim': llm.D, 'inputs': llm.names[:3],
            'think_end': llm.think_end, 'eos': sorted(llm.eos), 'reference': refs}


def eval_candidate(repo, onnx_path='onnx/model_q4.onnx'):
    out = 'out_eval'
    os.makedirs(out, exist_ok=True)
    fetch('cand', repo, onnx_path, out=out)
    check_llm('cand', out)


def main():
    if len(sys.argv) > 2 and sys.argv[1] == '--eval':
        eval_candidate(sys.argv[2])
        return
    os.makedirs(OUT, exist_ok=True)
    info = {}
    from tokenizers import Tokenizer
    # e5-small solo para comparar (no se publica aquí: ya está en models-reason-v1)
    fetch(*E5)
    print('\n### e5-small (multilingüe, referencia)')
    e5 = eval_embed(Embedder('e5s', 'query: ', 'passage: '))
    for f in os.listdir(OUT):
        if f.startswith('e5s_'):
            os.remove(f'{OUT}/{f}')
    for prefix, repo, path in (EMBED, LLM):
        print(f'\n### {prefix} ({repo})')
        fetch(prefix, repo, path)
        info[prefix] = check_embed(prefix) if prefix == 'jinaes' else check_llm(prefix)
        tok = Tokenizer.from_file(f'{OUT}/{prefix}_tokenizer.json')
        info[prefix]['repo'] = repo
        info[prefix]['tokenizer_tests'] = [{'text': t, 'ids': tok.encode(t).ids} for t in TOKENIZER_TESTS]
    info['jinaes']['e5_accuracy'] = list(e5)
    files = {n: {'size': os.path.getsize(f'{OUT}/{n}'), 'sha256': sha(f'{OUT}/{n}')}
             for n in sorted(os.listdir(OUT)) if n != 'manifest.json'}
    json.dump({'model': 'Comprensión y razonamiento en castellano de Herrero: jina-embeddings-v2-base-es '
                        '(Apache-2.0) y SmolLM3-3B con razonamiento (Apache-2.0), ONNX de transformers.js '
                        '(ONNX Runtime 1.20)',
               'files': files, 'models': info},
              open(f'{OUT}/manifest.json', 'w'), indent=1, ensure_ascii=False)
    print(json.dumps(files, indent=1))


if __name__ == '__main__':
    main()
