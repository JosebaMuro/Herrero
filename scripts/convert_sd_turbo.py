"""Convierte stabilityai/sd-turbo a ONNX cuantizado (int8) para la app Herrero.

Genera en ./out:
  - sdturbo_text_encoder_int8.onnx
  - sdturbo_unet_int8.onnx        (MatMul + Conv cuantizados: equilibrado, móvil)
  - sdturbo_unet_int8mm.onnx      (solo MatMul cuantizado: más calidad, PC)  [si cabe < 2 GB]
  - sdturbo_vae_encoder.onnx / sdturbo_vae_decoder.onnx (fp32)
  - vocab.json, merges.txt, manifest.json
  - muestras de prueba generadas con el mismo algoritmo que usa la app
"""
import hashlib
import json
import math
import os
import shutil
import sys
import time

import numpy as np
import onnx
import torch
from diffusers import AutoencoderKL, UNet2DConditionModel
from onnxruntime.quantization import QuantType, quantize_dynamic
from PIL import Image
from transformers import CLIPTextModel, CLIPTokenizer

import onnxruntime as ort

MODEL = "stabilityai/sd-turbo"
RAW = "raw"
OUT = "out"
os.makedirs(RAW, exist_ok=True)
os.makedirs(OUT, exist_ok=True)
OPSET = 17
torch.set_grad_enabled(False)


def log(*a):
    print(*a, flush=True)


def size_mb(p):
    total = os.path.getsize(p)
    d = os.path.dirname(p)
    for f in os.listdir(d):
        if f.endswith(".data") or f.endswith(".pb") or f.endswith(".onnx_data"):
            total += os.path.getsize(os.path.join(d, f))
    return total / 1e6


def export(module, args, path, in_names, out_names, dyn):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    torch.onnx.export(
        module,
        args,
        path,
        input_names=in_names,
        output_names=out_names,
        dynamic_axes=dyn,
        opset_version=OPSET,
        do_constant_folding=True,
        dynamo=False,
    )
    m = onnx.load(path, load_external_data=True)
    # guarda todos los pesos en un único fichero externo
    for f in os.listdir(os.path.dirname(path)):
        fp = os.path.join(os.path.dirname(path), f)
        if fp != path:
            os.remove(fp)
    onnx.save_model(m, path, save_as_external_data=True, all_tensors_to_one_file=True,
                    location=os.path.basename(path) + ".data", size_threshold=1024)
    log(f"exportado {path}: {size_mb(path):.0f} MB")


VERIFY = '--verify' in sys.argv
SCALE = 0.18215

if not VERIFY:
    exec(compile('# ---------------------------------------------------------------- exportación\nlog("Descargando y exportando componentes…")\ntok = CLIPTokenizer.from_pretrained(MODEL, subfolder="tokenizer")\nte = CLIPTextModel.from_pretrained(MODEL, subfolder="text_encoder").eval()\n\n\nclass TE(torch.nn.Module):\n    def __init__(self, m):\n        super().__init__()\n        self.m = m\n\n    def forward(self, input_ids):\n        return self.m(input_ids=input_ids)[0]\n\n\nexport(TE(te), (torch.zeros(1, 77, dtype=torch.int64),), f"{RAW}/te/model.onnx",\n       ["input_ids"], ["last_hidden_state"], None)\ndel te\n\nunet = UNet2DConditionModel.from_pretrained(MODEL, subfolder="unet").eval()\n\n\nclass U(torch.nn.Module):\n    def __init__(self, m):\n        super().__init__()\n        self.m = m\n\n    def forward(self, sample, timestep, encoder_hidden_states):\n        return self.m(sample, timestep, encoder_hidden_states, return_dict=False)[0]\n\n\nexport(U(unet), (torch.randn(1, 4, 64, 64), torch.tensor([999.0]), torch.randn(1, 77, 1024)),\n       f"{RAW}/unet/model.onnx", ["sample", "timestep", "encoder_hidden_states"], ["out_sample"],\n       {"sample": {2: "h", 3: "w"}, "out_sample": {2: "h", 3: "w"}})\ndel unet\n\nvae = AutoencoderKL.from_pretrained(MODEL, subfolder="vae").eval()\nSCALE = float(vae.config.scaling_factor)\n\n\nclass Enc(torch.nn.Module):\n    def __init__(self, m):\n        super().__init__()\n        self.m = m\n\n    def forward(self, sample):\n        return self.m.encode(sample).latent_dist.mean\n\n\nclass Dec(torch.nn.Module):\n    def __init__(self, m):\n        super().__init__()\n        self.m = m\n\n    def forward(self, latent_sample):\n        return self.m.decode(latent_sample).sample\n\n\nexport(Enc(vae), (torch.randn(1, 3, 512, 512),), f"{RAW}/vae_encoder/model.onnx", ["sample"],\n       ["latent_sample"], {"sample": {2: "H", 3: "W"}, "latent_sample": {2: "h", 3: "w"}})\nexport(Dec(vae), (torch.randn(1, 4, 64, 64),), f"{RAW}/vae_decoder/model.onnx", ["latent_sample"],\n       ["sample"], {"latent_sample": {2: "h", 3: "w"}, "sample": {2: "H", 3: "W"}})\ndel vae\n\n# ---------------------------------------------------------------- cuantización\n\n\ndef single_file(src, dst):\n    m = onnx.load(src, load_external_data=True)\n    # La app usa ONNX Runtime 1.15 (IR <= 9): fijamos IR 8\n    m.ir_version = min(m.ir_version, 8)\n    onnx.save_model(m, dst)\n    log(f"{dst}: {os.path.getsize(dst)/1e6:.0f} MB")\n\n\ndef quant(src, dst, ops):\n    tmp = dst + ".tmp.onnx"\n    quantize_dynamic(src, tmp, weight_type=QuantType.QUInt8, op_types_to_quantize=ops,\n                     use_external_data_format=True, extra_options={"MatMulConstBOnly": True})\n    total = size_mb(tmp)\n    log(f"cuantizado {dst} ({ops}): {total:.0f} MB")\n    if total < 2000:\n        single_file(tmp, dst)\n        ok = True\n    else:\n        log(f"{dst} supera 2 GB, se descarta")\n        ok = False\n    for f in os.listdir(os.path.dirname(tmp) or "."):\n        if f.startswith(os.path.basename(tmp)):\n            os.remove(os.path.join(os.path.dirname(tmp) or ".", f))\n    return ok\n\n\nlog("Cuantizando…")\nquant(f"{RAW}/te/model.onnx", f"{OUT}/sdturbo_text_encoder_int8.onnx", ["MatMul", "Gemm"])\nquant(f"{RAW}/unet/model.onnx", f"{OUT}/sdturbo_unet_int8.onnx", ["MatMul", "Gemm", "Conv"])\nhas_mm = quant(f"{RAW}/unet/model.onnx", f"{OUT}/sdturbo_unet_int8mm.onnx", ["MatMul", "Gemm"])\nsingle_file(f"{RAW}/vae_encoder/model.onnx", f"{OUT}/sdturbo_vae_encoder.onnx")\nsingle_file(f"{RAW}/vae_decoder/model.onnx", f"{OUT}/sdturbo_vae_decoder.onnx")\ntok.save_pretrained(f"{RAW}/tok")\nshutil.copy(f"{RAW}/tok/vocab.json", f"{OUT}/vocab.json")\nshutil.copy(f"{RAW}/tok/merges.txt", f"{OUT}/merges.txt")\nshutil.rmtree(RAW)\n\n', 'export', 'exec'))
else:
    tok = CLIPTokenizer.from_pretrained(MODEL, subfolder='tokenizer')
    log('Verificación con onnxruntime', ort.__version__)

# ---------------------------------------------------------------- pipeline de prueba
# (idéntico al implementado en Dart: EulerDiscrete, trailing, sin CFG)
betas = np.linspace(0.00085 ** 0.5, 0.012 ** 0.5, 1000, dtype=np.float64) ** 2
acp = np.cumprod(1.0 - betas)
SIGMAS = np.sqrt((1 - acp) / acp)


def timesteps(n):
    return [int(round(1000 - i * 1000 / n)) - 1 for i in range(n)]


def sess(name):
    so = ort.SessionOptions()
    so.intra_op_num_threads = os.cpu_count()
    return ort.InferenceSession(f"{OUT}/{name}", so, providers=["CPUExecutionProvider"])


def io(name):
    s = sess(name)
    return {
        "inputs": [{"name": i.name, "type": i.type, "shape": [str(d) for d in i.shape]} for i in s.get_inputs()],
        "outputs": [{"name": o.name, "type": o.type, "shape": [str(d) for d in o.shape]} for o in s.get_outputs()],
    }


def encode_prompt(prompt):
    ids = tok(prompt, padding="max_length", max_length=77, truncation=True).input_ids
    s = sess("sdturbo_text_encoder_int8.onnx")
    return ids, s.run(None, {"input_ids": np.array([ids], dtype=np.int64)})[0]


def run(prompt, unet_file, size=512, steps=1, init=None, strength=0.5, seed=0):
    t0 = time.time()
    ids, emb = encode_prompt(prompt)
    rng = np.random.default_rng(seed)
    h = w = size // 8
    ts = timesteps(steps)
    if init is not None:
        k = min(int(steps * strength), steps)
        ts = ts[steps - k:]
        enc = sess("sdturbo_vae_encoder.onnx")
        img = np.asarray(init.convert("RGB").resize((size, size)), dtype=np.float32) / 127.5 - 1
        lat = enc.run(None, {"sample": img.transpose(2, 0, 1)[None]})[0] * SCALE
        lat = lat + rng.standard_normal(lat.shape).astype(np.float32) * SIGMAS[ts[0]]
    else:
        lat = rng.standard_normal((1, 4, h, w)).astype(np.float32) * math.sqrt(SIGMAS[ts[0]] ** 2 + 1)
    u = sess(unet_file)
    for i, t in enumerate(ts):
        sig = SIGMAS[t]
        nxt = SIGMAS[ts[i + 1]] if i + 1 < len(ts) else 0.0
        x = (lat / math.sqrt(sig ** 2 + 1)).astype(np.float32)
        eps = u.run(None, {"sample": x, "timestep": np.array([t], dtype=np.float32),
                           "encoder_hidden_states": emb.astype(np.float32)})[0]
        lat = (lat + eps * (nxt - sig)).astype(np.float32)
    dec = sess("sdturbo_vae_decoder.onnx")
    out = dec.run(None, {"latent_sample": (lat / SCALE).astype(np.float32)})[0][0]
    img = np.clip((out.transpose(1, 2, 0) + 1) * 127.5, 0, 255).astype(np.uint8)
    log(f"generada ({unet_file}, {size}px, {len(ts)} pasos) en {time.time()-t0:.1f} s")
    return ids, Image.fromarray(img)


PROMPT = ("professional architectural photograph of a galvanized steel portal frame warehouse "
          "structure under construction, steel I-beams, purlins, cross bracing, concrete slab, "
          "daylight, blue sky, realistic, sharp focus, 35mm")
SUF = '_ort' + ort.__version__.replace('.', '') if VERIFY else ''
ids, im = run(PROMPT, "sdturbo_unet_int8.onnx")
im.save(f"{OUT}/sample_txt2img_int8{SUF}.png")
init = Image.open("scripts/sample_render.png")
_, im = run(PROMPT, "sdturbo_unet_int8.onnx", steps=2, init=init, strength=0.5)
im.save(f"{OUT}/sample_img2img_int8{SUF}.png")
_, im = run(PROMPT, "sdturbo_unet_int8.onnx", size=384, steps=2, init=init, strength=0.5)
im.save(f"{OUT}/sample_img2img_int8_384{SUF}.png")
if os.path.exists(f"{OUT}/sdturbo_unet_int8mm.onnx"):
    _, im = run(PROMPT, "sdturbo_unet_int8mm.onnx", steps=2, init=init, strength=0.5)
    im.save(f"{OUT}/sample_img2img_int8mm{SUF}.png")

# ---------------------------------------------------------------- manifiesto
if VERIFY:
    sys.exit(0)


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


files = {f: {"size": os.path.getsize(f"{OUT}/{f}"), "sha256": sha(f"{OUT}/{f}")}
         for f in sorted(os.listdir(OUT)) if not f.startswith("sample")}
manifest = {
    "model": MODEL,
    "vae_scaling_factor": SCALE,
    "files": files,
    "io": {f: io(f) for f in files if f.endswith(".onnx")},
    "tokenizer_test": {"prompt": PROMPT, "ids": ids},
}
with open(f"{OUT}/manifest.json", "w") as f:
    json.dump(manifest, f, indent=1)
log(json.dumps(manifest["io"], indent=1))
log(json.dumps(manifest["files"], indent=1))
