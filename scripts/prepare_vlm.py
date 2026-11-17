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
REPO = 'HuggingFaceTB/SmolVLM-256M-Instruct'
FILES = {
    'smolvlm_vision_int8.onnx': 'onnx/vision_encoder_quantized.onnx',
    'smolvlm_embed_int8.onnx': 'onnx/embed_tokens_quantized.onnx',
    'smolvlm_decoder_int8.onnx': 'onnx/decoder_model_merged_quantized.onnx',
    'smolvlm_tokenizer.json': 'tokenizer.json',
    'smolvlm_config.json': 'config.json',
}
QUESTIONS = [
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
    for x in range(90, 430, 40):
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


def sessions():
    so = ort.SessionOptions()
    so.intra_op_num_threads = 4
    mk = lambda f: ort.InferenceSession(f'{OUT}/{f}', so, providers=['CPUExecutionProvider'])
    return mk('smolvlm_vision_int8.onnx'), mk('smolvlm_embed_int8.onnx'), mk('smolvlm_decoder_int8.onnx')


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


def main():
    from huggingface_hub import hf_hub_download
    import onnx
    os.makedirs(OUT, exist_ok=True)
    for dst, src in FILES.items():
        p = hf_hub_download(REPO, src)
        shutil.copy(p, f'{OUT}/{dst}')
        if dst.endswith('.onnx'):
            m = onnx.load(f'{OUT}/{dst}')
            print(dst, 'IR', m.ir_version, 'opsets', [(o.domain, o.version) for o in m.opset_import])
            if m.ir_version > 8:
                m.ir_version = 8
                onnx.save(m, f'{OUT}/{dst}')
                print('  -> IR 8')
    cfg = json.load(open(f'{OUT}/smolvlm_config.json'))
    img = sketch()
    img.save(f'{OUT}/smolvlm_test_sketch.png')

    # referencia del prompt con el procesador oficial (sin dividir la imagen)
    from transformers import AutoProcessor
    proc = AutoProcessor.from_pretrained(REPO)
    proc.image_processor.do_image_splitting = False
    vis, emb, dec = sessions()
    for s, name in ((vis, 'vision'), (emb, 'embed'), (dec, 'decoder')):
        print(name, 'in', [(i.name, i.shape, i.type) for i in s.get_inputs()][:5])
        print(name, 'out', [(o.name, o.shape) for o in s.get_outputs()][:3])
    tests = []
    from tokenizers import Tokenizer
    tok = Tokenizer.from_file(f'{OUT}/smolvlm_tokenizer.json')
    for q in QUESTIONS:
        msgs = [{'role': 'user', 'content': [{'type': 'image'}, {'type': 'text', 'text': q}]}]
        prompt = proc.apply_chat_template(msgs, add_generation_prompt=True)
        inp = proc(text=prompt, images=[img], return_tensors='np')
        ids = inp['input_ids'][0].tolist()
        expanded = proc.tokenizer.decode(ids)
        pv = pixels(img)
        hf_pv = inp['pixel_values'].astype(np.float32)
        print('prompt', repr(prompt))
        print('pixel_values HF', hf_pv.shape, 'dif. con el nuestro', float(np.abs(hf_pv - pv).max()) if hf_pv.shape == pv.shape else 'forma distinta')
        t0 = time.time()
        a = generate(vis, emb, dec, cfg, ids, pv, dummy_past=True)
        dt = time.time() - t0
        b = generate(vis, emb, dec, cfg, ids, pv, dummy_past=False)
        text = tok.decode(a, skip_special_tokens=True)
        print(f'respuesta ({len(a)} tokens, {dt:.1f} s):', repr(text))
        print('igual al bucle estándar:', a == b, '| primeros', a[:12], b[:12])
        assert len(a) > 3 and a[:8] == b[:8], 'el pasado enmascarado no coincide'
        tests.append({'question': q, 'prompt': prompt, 'expanded': expanded, 'prompt_ids': ids,
                      'output_ids': a, 'output_text': text})
    # vectores del tokenizador
    tok_tests = []
    for s in ['Marquesina de 5,50 x 5 m y 2,40 m de alto', 'IPE 300 L=6000 mm', 'hello world  123\nnew line',
              'Ñandú pérgola acero S275JR ½" Ø16', '<|im_start|>User:<image>Hi<end_of_utterance>\nAssistant:']:
        tok_tests.append({'text': s, 'ids': tok.encode(s).ids})
    files = {}
    for n in sorted(os.listdir(OUT)):
        if n == 'manifest.json':
            continue
        p = os.path.join(OUT, n)
        files[n] = {'size': os.path.getsize(p), 'sha256': hashlib.sha256(open(p, 'rb').read()).hexdigest()}
    t = cfg['text_config']
    json.dump({'model': f'{REPO} (Apache-2.0), ONNX int8 de transformers.js', 'files': files,
               'vlm': {'image_token_id': cfg['image_token_id'], 'image_size': 512, 'image_seq_len': 64,
                       'hidden': t['hidden_size'], 'layers': t['num_hidden_layers'],
                       'kv_heads': t['num_key_value_heads'], 'head_dim': t.get('head_dim', 64),
                       'eos': [t['eos_token_id'], 49279], 'mean': 0.5, 'std': 0.5},
               'tests': tests, 'tokenizer_tests': tok_tests},
              open(f'{OUT}/manifest.json', 'w'), indent=1, ensure_ascii=False)
    print(json.dumps(files, indent=1))


def verify():
    man = json.load(open(f'{OUT}/manifest.json'))
    cfg = json.load(open(f'{OUT}/smolvlm_config.json'))
    vis, emb, dec = sessions()
    pv = pixels(Image.open(f'{OUT}/smolvlm_test_sketch.png'))
    print('ORT', ort.__version__)
    for t in man['tests']:
        t0 = time.time()
        a = generate(vis, emb, dec, cfg, t['prompt_ids'], pv)
        print(f'{len(a)} tokens en {time.time() - t0:.1f} s; coincide: {a == t["output_ids"]}')
        assert a[:8] == t['output_ids'][:8], (a, t['output_ids'])


if __name__ == '__main__':
    verify() if '--verify' in sys.argv else main()
