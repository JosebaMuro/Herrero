"""Prepara los modelos OCR (PP-OCRv4 de PaddleOCR, Apache-2.0) para Herrero.

Toma los ONNX publicados en el paquete rapidocr_onnxruntime (PyPI), extrae el
diccionario de caracteres, prueba la lectura sobre una imagen sintética y
escribe out_ocr/ con los ficheros y manifest.json (tamaño + SHA-256).
"""
import hashlib, json, os, shutil, sys, zipfile, glob

import numpy as np
import onnxruntime as ort
from PIL import Image, ImageDraw, ImageFont

OUT = 'out_ocr'


def main(wheel_dir):
    os.makedirs(OUT, exist_ok=True)
    whl = glob.glob(os.path.join(wheel_dir, 'rapidocr_onnxruntime-*.whl'))[0]
    with zipfile.ZipFile(whl) as z:
        for n in z.namelist():
            if n.endswith('ch_PP-OCRv4_det_infer.onnx'):
                with z.open(n) as src, open(f'{OUT}/ppocrv4_det.onnx', 'wb') as dst:
                    shutil.copyfileobj(src, dst)
            if n.endswith('ch_PP-OCRv4_rec_infer.onnx'):
                with z.open(n) as src, open(f'{OUT}/ppocrv4_rec.onnx', 'wb') as dst:
                    shutil.copyfileobj(src, dst)
    rec = ort.InferenceSession(f'{OUT}/ppocrv4_rec.onnx', providers=['CPUExecutionProvider'])
    keys = rec.get_modelmeta().custom_metadata_map['character'].split('\n')
    with open(f'{OUT}/ppocr_keys.txt', 'w', encoding='utf-8') as f:
        f.write('\n'.join(keys))
    print('caracteres', len(keys))
    test()
    files = {}
    for n in sorted(os.listdir(OUT)):
        if n == 'manifest.json':
            continue
        p = os.path.join(OUT, n)
        files[n] = {'size': os.path.getsize(p), 'sha256': hashlib.sha256(open(p, 'rb').read()).hexdigest()}
    json.dump({'model': 'PP-OCRv4 (PaddleOCR, Apache-2.0) vía RapidOCR', 'files': files,
               'det': {'input': 'x', 'output': 'sigmoid_0.tmp_0', 'mean': 0.5, 'std': 0.5, 'bgr': True},
               'rec': {'input': 'x', 'output': 'softmax_11.tmp_0', 'height': 48, 'blank': 0}},
              open(f'{OUT}/manifest.json', 'w'), indent=1)
    print(json.dumps(files, indent=1))


def test():
    """Lectura de una cota sintética para comprobar det + rec."""
    img = Image.new('RGB', (640, 224), 'white')  # múltiplos de 32
    d = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype('DejaVuSans.ttf', 36)
    except OSError:
        font = ImageFont.load_default(size=36)
    d.text((40, 70), 'IPE 300  L=6,00', fill='black', font=font)
    det = ort.InferenceSession(f'{OUT}/ppocrv4_det.onnx', providers=['CPUExecutionProvider'])
    x = np.asarray(img, dtype=np.float32)[:, :, ::-1]
    x = ((x / 255 - 0.5) / 0.5).transpose(2, 0, 1)[None]
    p = det.run(None, {'x': np.ascontiguousarray(x)})[0][0, 0]
    ys, xs = np.where(p > 0.3)
    assert len(ys) > 50, 'el detector no encuentra texto'
    crop = img.crop((max(0, xs.min() - 8), max(0, ys.min() - 8), xs.max() + 8, ys.max() + 8))
    rec = ort.InferenceSession(f'{OUT}/ppocrv4_rec.onnx', providers=['CPUExecutionProvider'])
    keys = open(f'{OUT}/ppocr_keys.txt', encoding='utf-8').read().split('\n') + [' ']
    w, h = crop.size
    nw = int(np.ceil(48 * w / h))
    im = np.asarray(crop.resize((nw, 48)), dtype=np.float32)[:, :, ::-1]
    t = np.zeros((1, 3, 48, max(320, nw)), np.float32)
    t[0, :, :, :nw] = ((im / 255 - 0.5) / 0.5).transpose(2, 0, 1)
    o = rec.run(None, {'x': t})[0][0]
    idx = o.argmax(1)
    s, last = '', -1
    for k in idx:
        if k != 0 and k != last:
            s += keys[k - 1]
        last = k
    print('lectura de prueba:', repr(s))
    assert '300' in s and '6' in s, s


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--verify':
        test()
    else:
        main(sys.argv[1] if len(sys.argv) > 1 else '.')
