"""Sustituye el ONNX Runtime 1.15 que trae el paquete `onnxruntime` de pub por
la versión 1.20 (misma API C, compatible hacia atrás), necesaria para los
operadores del VLM (GroupQueryAttention, MultiHeadAttention…).

En Windows se usa la compilación con DirectML (GPU de cualquier marca: NVIDIA,
AMD e Intel, por DirectX 12) más DirectML.dll; en CPU funciona igual que la normal.
Los paquetes CUDA y OpenVINO no van en el instalador: la app los descarga aparte.

Uso (después de `flutter pub get`):
    python scripts/ort_runtime.py android|windows|linux|ios

En Linux se toma la biblioteca de la arquitectura que compila (x64 o arm64).

En iOS no hay biblioteca que copiar: el paquete enlaza el pod
`onnxruntime-objc` (estático) y aquí se cambia su versión en el podspec.
"""
import hashlib, io, json, os, platform as platform_mod, shutil, sys, tarfile, time, urllib.error, urllib.request, zipfile

ANDROID = 'https://repo1.maven.org/maven2/com/microsoft/onnxruntime/onnxruntime-android/1.20.0/onnxruntime-android-1.20.0.aar'
# ONNX Runtime 1.20.1 con DirectML y DirectML 1.15.2 (la versión que pide su nuspec)
WINDOWS = ('https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime.directml/1.20.1/'
           'microsoft.ml.onnxruntime.directml.1.20.1.nupkg',
           '6763468507b7cfc777b1334b3e174c11a540ddacb7bd4354bc2e0ec89e56eec2')
DIRECTML = ('https://api.nuget.org/v3-flatcontainer/microsoft.ai.directml/1.15.2/'
            'microsoft.ai.directml.1.15.2.nupkg',
            '9f07482559087088a4dba4ae76eeeee1fad3f7077a92ccfbdb439c6bc2964c09')
# la release de GitHub v1.20.1 ya no tiene los binarios (404): NuGet oficial
LINUX = 'https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/1.20.1/microsoft.ml.onnxruntime.1.20.1.nupkg'


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


def get(url, sha256=None):
    # Maven Central y NuGet devuelven a veces 429/5xx a los runners de CI: se reintenta
    for attempt in range(1, 7):
        print('descargando', url, '(intento %d)' % attempt if attempt > 1 else '')
        try:
            with urllib.request.urlopen(url, timeout=120) as r:
                data = r.read()
            break
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as e:
            code = getattr(e, 'code', None)
            if attempt == 6 or (code is not None and code not in (408, 429, 500, 502, 503, 504)):
                raise
            wait = 10 * attempt
            if code == 429:
                try:
                    wait = max(wait, int(e.headers.get('Retry-After', wait)))
                except (TypeError, ValueError):
                    pass
            print('  error', code or e, '- reintento en', wait, 's')
            time.sleep(min(wait, 120))
    if sha256 and hashlib.sha256(data).hexdigest() != sha256:
        raise SystemExit('SHA-256 incorrecto: ' + url)
    return data


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
DLL_LOADER = 'herreroOpenOrt()'


SO_BY_NAME = "DynamicLibrary.open('libonnxruntime.so.1.15.1')"


def patch_dll_loader(pkg):
    """Windows trae su propio onnxruntime.dll (antiguo) en System32 y algunos componentes
    del sistema lo cargan en el proceso. Abrirlo solo por nombre devuelve ese módulo ya
    cargado en vez del 1.20 que va junto a herrero.exe, y Qwen3 falla con «Unrecognized
    attribute: softcap for operator GroupQueryAttention». Se abre siempre por ruta completa
    con scripts/ort_loader.dart, que además elige el paquete de aceleración (CUDA u
    OpenVINO) si el usuario lo ha instalado y seleccionado. En Linux hace lo mismo con el
    paquete CUDA (y precarga sus bibliotecas de NVIDIA)."""
    here = os.path.dirname(os.path.abspath(__file__))
    bdir = os.path.join(pkg, 'lib', 'src', 'bindings')
    shutil.copyfile(os.path.join(here, 'ort_loader.dart'), os.path.join(bdir, 'herrero_loader.dart'))
    src = os.path.join(bdir, 'bindings.dart')
    text = open(src, encoding='utf-8').read()
    for old in (DLL_BY_NAME, DLL_BY_PATH, SO_BY_NAME):
        text = text.replace(old, DLL_LOADER)
    if 'herrero_loader.dart' not in text:
        text = text.replace("import 'dart:io';", "import 'dart:io';\nimport 'herrero_loader.dart';", 1)
    open(src, 'w', encoding='utf-8').write(text)
    if text.count(DLL_LOADER) < 2:
        raise SystemExit('bindings.dart: no se pudo poner el cargador en Windows y Linux: ' + src)
    print('  ->', src, 'ONNX Runtime por ruta completa en Windows y Linux (herrero_loader.dart)')


def patch_bundle_directml(pkg):
    """El plugin solo empaqueta onnxruntime.dll: se añade DirectML.dll junto a herrero.exe."""
    src = os.path.join(pkg, 'windows', 'CMakeLists.txt')
    text = open(src, encoding='utf-8').read()
    one = '"${CMAKE_CURRENT_SOURCE_DIR}/onnxruntime.dll"'
    both = one + '\n  "${CMAKE_CURRENT_SOURCE_DIR}/DirectML.dll"'
    if 'DirectML.dll' not in text:
        if one not in text:
            raise SystemExit('CMakeLists.txt del plugin inesperado: ' + src)
        text = text.replace(one, both, 1)
        open(src, 'w', encoding='utf-8').write(text)
    print('  ->', src, 'empaqueta DirectML.dll')


def linux_arch():
    """x64 o arm64 (Raspberry Pi 4/5 con sistema de 64 bits): la de la máquina que compila,
    o la de HERRERO_ARCH si se fija a mano. El paquete NuGet trae las dos."""
    arch = os.environ.get('HERRERO_ARCH') or platform_mod.machine()
    arch = {'x86_64': 'x64', 'amd64': 'x64', 'aarch64': 'arm64'}.get(arch.lower(), arch.lower())
    if arch not in ('x64', 'arm64'):
        raise SystemExit('arquitectura de Linux no admitida: ' + arch)
    return arch


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
        ort = zipfile.ZipFile(io.BytesIO(get(*WINDOWS)))
        dml = zipfile.ZipFile(io.BytesIO(get(*DIRECTML)))
        for z, name, out in ((ort, 'runtimes/win-x64/native/onnxruntime.dll', 'onnxruntime.dll'),
                             (dml, 'bin/x64-win/DirectML.dll', 'DirectML.dll')):
            dst = os.path.join(pkg, 'windows', out)
            with z.open(name) as src, open(dst, 'wb') as f:
                shutil.copyfileobj(src, f)
            print('  ->', dst, os.path.getsize(dst))
        patch_wide_path(pkg)
        patch_dll_loader(pkg)
        patch_bundle_directml(pkg)
    elif platform == 'linux':
        z = zipfile.ZipFile(io.BytesIO(get(LINUX)))
        arch = linux_arch()
        dst = os.path.join(pkg, 'linux', 'libonnxruntime.so.1.15.1')  # nombre que carga el paquete
        print('  arquitectura:', arch)
        with z.open(f'runtimes/linux-{arch}/native/libonnxruntime.so') as src, open(dst, 'wb') as out:
            shutil.copyfileobj(src, out)
        print('  ->', dst, os.path.getsize(dst))
        patch_dll_loader(pkg)
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
