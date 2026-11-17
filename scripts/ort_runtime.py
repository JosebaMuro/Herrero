"""Sustituye el ONNX Runtime 1.15 que trae el paquete `onnxruntime` de pub por
la versión 1.20 (misma API C, compatible hacia atrás), necesaria para los
operadores del VLM (GroupQueryAttention, MultiHeadAttention…).

Uso (después de `flutter pub get`):
    python scripts/ort_runtime.py android|windows|linux
"""
import io, json, os, shutil, sys, tarfile, urllib.request, zipfile

ANDROID = 'https://repo1.maven.org/maven2/com/microsoft/onnxruntime/onnxruntime-android/1.20.0/onnxruntime-android-1.20.0.aar'
WINDOWS = 'https://github.com/microsoft/onnxruntime/releases/download/v1.20.1/onnxruntime-win-x64-1.20.1.zip'
LINUX = 'https://github.com/microsoft/onnxruntime/releases/download/v1.20.1/onnxruntime-linux-x64-1.20.1.tgz'


def package_dir():
    cfg = json.load(open('.dart_tool/package_config.json', encoding='utf-8'))
    for p in cfg['packages']:
        if p['name'] == 'onnxruntime':
            uri = p['rootUri']
            if uri.startswith('file://'):
                uri = uri[len('file://'):]
                if os.name == 'nt' and uri.startswith('/'):
                    uri = uri[1:]
            return urllib.request.url2pathname(uri) if os.name == 'nt' else uri
    raise SystemExit('paquete onnxruntime no encontrado')


def get(url):
    print('descargando', url)
    with urllib.request.urlopen(url) as r:
        return r.read()


def main(platform):
    pkg = package_dir()
    print('paquete:', pkg)
    if platform == 'android':
        z = zipfile.ZipFile(io.BytesIO(get(ANDROID)))
        for abi in ('arm64-v8a', 'armeabi-v7a'):
            dst = os.path.join(pkg, 'android', 'src', 'main', 'jniLibs', abi, 'libonnxruntime.so')
            with z.open(f'jni/{abi}/libonnxruntime.so') as src, open(dst, 'wb') as out:
                shutil.copyfileobj(src, out)
            print('  ->', dst, os.path.getsize(dst))
    elif platform == 'windows':
        z = zipfile.ZipFile(io.BytesIO(get(WINDOWS)))
        name = next(n for n in z.namelist() if n.endswith('lib/onnxruntime.dll'))
        dst = os.path.join(pkg, 'windows', 'onnxruntime.dll')
        with z.open(name) as src, open(dst, 'wb') as out:
            shutil.copyfileobj(src, out)
        print('  ->', dst, os.path.getsize(dst))
    elif platform == 'linux':
        t = tarfile.open(fileobj=io.BytesIO(get(LINUX)))
        m = next(m for m in t.getmembers() if m.name.endswith('lib/libonnxruntime.so.1.20.1'))
        dst = os.path.join(pkg, 'linux', 'libonnxruntime.so.1.15.1')  # nombre que carga el paquete
        with t.extractfile(m) as src, open(dst, 'wb') as out:
            shutil.copyfileobj(src, out)
        print('  ->', dst, os.path.getsize(dst))
    else:
        raise SystemExit(__doc__)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '')
