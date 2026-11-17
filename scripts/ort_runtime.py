"""Sustituye el ONNX Runtime 1.15 que trae el paquete `onnxruntime` de pub por
la versión 1.20 (misma API C, compatible hacia atrás), necesaria para los
operadores del VLM (GroupQueryAttention, MultiHeadAttention…).

Uso (después de `flutter pub get`):
    python scripts/ort_runtime.py android|windows|linux|ios

En iOS no hay biblioteca que copiar: el paquete enlaza el pod
`onnxruntime-objc` (estático) y aquí se cambia su versión en el podspec.
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


UTF8_PATH = 'modelFile.path.toNativeUtf8().cast<ffi.Char>()'
WIDE_PATH = ('(Platform.isWindows'
             ' ? modelFile.path.toNativeUtf16().cast<ffi.Char>()'
             ' : modelFile.path.toNativeUtf8().cast<ffi.Char>())')


def patch_wide_path(pkg):
    """En Windows, CreateSession recibe la ruta como wchar_t* (UTF-16). El paquete
    la pasa en UTF-8 y ONNX Runtime la lee como texto chino: «Load model from 摥…
    failed. File doesn't exist». Se corrige OrtSession.fromFile para pasar UTF-16."""
    src = os.path.join(pkg, 'lib', 'src', 'ort_session.dart')
    text = open(src, encoding='utf-8').read()
    if WIDE_PATH not in text:
        if UTF8_PATH not in text:
            raise SystemExit('ort_session.dart inesperado: ' + src)
        text = text.replace(UTF8_PATH, WIDE_PATH)
        open(src, 'w', encoding='utf-8').write(text)
    print('  ->', src, 'ruta del modelo en UTF-16')


DLL_BY_NAME = "DynamicLibrary.open('onnxruntime.dll')"
DLL_BY_PATH = ("DynamicLibrary.open(File(Platform.resolvedExecutable).parent.path"
               " + r'\\onnxruntime.dll')")


def patch_dll_path(pkg):
    """Windows trae su propio onnxruntime.dll (antiguo) en System32 y algunos componentes
    del sistema lo cargan en el proceso. Abrirlo solo por nombre devuelve ese módulo ya
    cargado en vez del 1.20 que va junto a herrero.exe, y Qwen3 falla con «Unrecognized
    attribute: softcap for operator GroupQueryAttention». Se abre por ruta completa."""
    src = os.path.join(pkg, 'lib', 'src', 'bindings', 'bindings.dart')
    text = open(src, encoding='utf-8').read()
    if DLL_BY_PATH not in text:
        if DLL_BY_NAME not in text:
            raise SystemExit('bindings.dart inesperado: ' + src)
        text = text.replace(DLL_BY_NAME, DLL_BY_PATH)
        open(src, 'w', encoding='utf-8').write(text)
    print('  ->', src, 'onnxruntime.dll por ruta completa')


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
        patch_wide_path(pkg)
        patch_dll_path(pkg)
    elif platform == 'linux':
        t = tarfile.open(fileobj=io.BytesIO(get(LINUX)))
        m = next(m for m in t.getmembers() if m.name.endswith('lib/libonnxruntime.so.1.20.1'))
        dst = os.path.join(pkg, 'linux', 'libonnxruntime.so.1.15.1')  # nombre que carga el paquete
        with t.extractfile(m) as src, open(dst, 'wb') as out:
            shutil.copyfileobj(src, out)
        print('  ->', dst, os.path.getsize(dst))
    elif platform == 'ios':
        spec = os.path.join(pkg, 'ios', 'onnxruntime.podspec')
        text = open(spec, encoding='utf-8').read()
        new = text.replace("'onnxruntime-objc', '1.15.1'", "'onnxruntime-objc', '1.20.0'")
        new = new.replace("s.platform = :ios, '11.0'", "s.platform = :ios, '15.0'")
        if "'onnxruntime-objc', '1.20.0'" not in new:
            raise SystemExit('podspec de onnxruntime inesperado: ' + spec)
        open(spec, 'w', encoding='utf-8').write(new)
        print('  ->', spec, 'onnxruntime-objc 1.20.0')
    else:
        raise SystemExit(__doc__)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '')
