// Aceleración de la IA local: elección del proveedor de ONNX Runtime (CPU, GPU, NPU)
// con vuelta a CPU, y paquetes opcionales de Windows (NVIDIA CUDA, Intel OpenVINO).
//
// Qué hay en cada plataforma (ONNX Runtime 1.20):
// * Windows: DirectML va de serie (DirectX 12: GPU NVIDIA, AMD e Intel). CUDA y
//   OpenVINO son descargas opcionales porque pesan mucho. ROCm/MIGraphX de AMD solo
//   existen en Linux y ONNX Runtime no tiene proveedor Vulkan: en Windows las gráficas
//   AMD (y cualquier otra) van por DirectML.
// * Android: NNAPI (GPU, DSP o NPU del fabricante) y XNNPACK (CPU ARM optimizada).
//   Vulkan tampoco es un proveedor de ONNX Runtime en Android.
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:onnxruntime/onnxruntime.dart';
// ignore: implementation_imports
import 'package:onnxruntime/src/bindings/bindings.dart' show onnxRuntimeBinding;
// ignore: implementation_imports
import 'package:onnxruntime/src/bindings/onnxruntime_bindings_generated.dart' as bg;

import 'model_manager.dart';

/// Motor de ejecución preferido (el índice se guarda en ajustes: no cambiar el orden).
enum AiEngine { auto, cpu, nnapi, directml, cuda, openvino, xnnpack }

/// Motores que tienen sentido en esta plataforma, en el orden en que se muestran.
List<AiEngine> enginesForPlatform() {
  if (Platform.isWindows) {
    return const [AiEngine.auto, AiEngine.directml, AiEngine.cuda, AiEngine.openvino, AiEngine.cpu];
  }
  if (Platform.isAndroid) return const [AiEngine.auto, AiEngine.nnapi, AiEngine.xnnpack, AiEngine.cpu];
  return const [AiEngine.auto, AiEngine.cpu];
}

extension AiEngineLabel on AiEngine {
  String get label {
    switch (this) {
      case AiEngine.auto:
        return 'Automático';
      case AiEngine.cpu:
        return 'Solo CPU';
      case AiEngine.nnapi:
        return 'NPU / GPU (NNAPI)';
      case AiEngine.directml:
        return 'GPU · DirectML';
      case AiEngine.cuda:
        return 'NVIDIA CUDA';
      case AiEngine.openvino:
        return 'Intel OpenVINO';
      case AiEngine.xnnpack:
        return 'CPU optimizada (XNNPACK)';
    }
  }

  String get help {
    switch (this) {
      case AiEngine.auto:
        if (Platform.isWindows) {
          return 'Usa la mejor aceleración disponible: CUDA (NVIDIA) u OpenVINO (Intel) si has descargado su '
              'paquete y tienes esa gráfica; si no, DirectML con cualquier gráfica. Si algo falla, sigue en CPU.';
        }
        if (Platform.isAndroid) return 'Usa la NPU/GPU del móvil donde es fiable y la CPU para el resto.';
        return 'Usa la CPU.';
      case AiEngine.cpu:
        return 'Solo procesador. El más compatible y el que da resultados de referencia.';
      case AiEngine.nnapi:
        return 'Fuerza la aceleración Android NNAPI (GPU, DSP o NPU del fabricante) en todos los modelos; '
            'lo que no admite va a la CPU y, si falla, vuelve a CPU.';
      case AiEngine.directml:
        return 'GPU por DirectX 12: vale para gráficas NVIDIA, AMD e Intel (también integradas). '
            'Viene de serie, sin descargas.';
      case AiEngine.cuda:
        return 'Gráficas NVIDIA (GeForce, RTX, Quadro) con CUDA 12 y cuDNN 9. Lo más rápido en NVIDIA. '
            'Necesita descargar el paquete CUDA.';
      case AiEngine.openvino:
        return 'Gráficas y NPU de Intel (Iris Xe, Arc, Core Ultra). Necesita descargar el paquete OpenVINO.';
      case AiEngine.xnnpack:
        return 'Núcleos de cálculo optimizados para procesadores ARM. Útil si NNAPI va mal en tu móvil.';
    }
  }
}

// ---------------------------------------------------------------------------
// Apertura de sesiones con aceleración y vuelta a CPU
// ---------------------------------------------------------------------------

/// Proveedor concreto de ONNX Runtime.
enum OrtEp { cpu, nnapi, xnnpack, directml, cuda, openvino }

extension OrtEpLabel on OrtEp {
  String get label => const {
        OrtEp.cpu: 'CPU',
        OrtEp.nnapi: 'NNAPI',
        OrtEp.xnnpack: 'XNNPACK',
        OrtEp.directml: 'DirectML',
        OrtEp.cuda: 'CUDA',
        OrtEp.openvino: 'OpenVINO',
      }[this]!;

  /// Nombre que da ONNX Runtime en GetAvailableProviders.
  String get ortName => const {
        OrtEp.cpu: 'CPUExecutionProvider',
        OrtEp.nnapi: 'NnapiExecutionProvider',
        OrtEp.xnnpack: 'XnnpackExecutionProvider',
        OrtEp.directml: 'DmlExecutionProvider',
        OrtEp.cuda: 'CUDAExecutionProvider',
        OrtEp.openvino: 'OpenVINOExecutionProvider',
      }[this]!;
}

/// En este isolate, abrir todo en CPU (se activa al reintentar tras un fallo de la GPU).
bool ortForceCpu = false;

/// Ejecuta [body] con la aceleración pedida y, si falla, lo repite entero en CPU.
Future<T> ortWithCpuFallback<T>(AiEngine engine, Future<T> Function() body) async {
  if (engine == AiEngine.cpu || ortForceCpu) return body();
  try {
    return await body();
  } catch (e) {
    final s = '$e';
    // los ficheros que faltan o la memoria no se arreglan cambiando de proveedor
    if (s.contains('NO_SUCHFILE') || s.contains('PathNotFoundException') || s.contains('Cancelado')) rethrow;
    ortForceCpu = true;
    try {
      return await body();
    } finally {
      ortForceCpu = false;
    }
  }
}

/// Proveedores que trae el ONNX Runtime cargado (p. ej. DmlExecutionProvider).
List<String> ortProviders() {
  final api = OrtEnv.instance.ortApiPtr.ref;
  final pp = calloc<ffi.Pointer<ffi.Pointer<ffi.Char>>>();
  final len = calloc<ffi.Int>();
  try {
    OrtStatus.checkOrtStatus(api.GetAvailableProviders.asFunction<
        bg.OrtStatusPtr Function(ffi.Pointer<ffi.Pointer<ffi.Pointer<ffi.Char>>>, ffi.Pointer<ffi.Int>)>()(pp, len));
    final out = [for (var i = 0; i < len.value; i++) pp.value[i].cast<Utf8>().toDartString()];
    api.ReleaseAvailableProviders.asFunction<bg.OrtStatusPtr Function(ffi.Pointer<ffi.Pointer<ffi.Char>>, int)>()(
        pp.value, len.value);
    return out;
  } finally {
    calloc.free(pp);
    calloc.free(len);
  }
}

/// Proveedores a probar, en orden, antes de la CPU. [quantized]: modelo int8 dinámico
/// (MatMulInteger…), que NNAPI no admite.
List<OrtEp> accelChain(AiEngine engine, {required bool quantized, List<String>? available}) {
  if (engine == AiEngine.cpu || ortForceCpu) return const [];
  List<String> av() => available ?? ortProviders();
  bool has(OrtEp e) => av().contains(e.ortName);
  if (Platform.isAndroid) {
    switch (engine) {
      case AiEngine.auto:
        return quantized ? const [] : const [OrtEp.nnapi];
      case AiEngine.nnapi:
        return const [OrtEp.nnapi];
      case AiEngine.xnnpack:
        return const [OrtEp.xnnpack];
      default:
        return const [];
    }
  }
  if (Platform.isWindows) {
    switch (engine) {
      case AiEngine.auto:
        // el runtime cargado ya refleja el paquete elegido (CUDA / OpenVINO / DirectML de serie)
        for (final e in const [OrtEp.cuda, OrtEp.openvino, OrtEp.directml]) {
          if (has(e)) return [e];
        }
        return const [];
      case AiEngine.directml:
        return has(OrtEp.directml) ? const [OrtEp.directml] : const [];
      case AiEngine.cuda:
        return has(OrtEp.cuda) ? const [OrtEp.cuda] : const [];
      case AiEngine.openvino:
        return has(OrtEp.openvino) ? const [OrtEp.openvino] : const [];
      default:
        return const [];
    }
  }
  return const [];
}

/// Sesión abierta y el proveedor con el que se abrió.
class OrtOpened {
  final OrtSession session;
  final OrtEp ep;
  const OrtOpened(this.session, this.ep);
}

/// Abre [path] con la aceleración de [engine]; si el proveedor no está o no admite el
/// modelo, prueba el siguiente y al final la CPU.
OrtOpened ortOpenAccel(String path, int threads, AiEngine engine, {bool quantized = true}) {
  final chain = accelChain(engine, quantized: quantized);
  Object? lastError;
  for (final ep in chain) {
    try {
      return OrtOpened(_create(path, threads, ep), ep);
    } catch (e) {
      lastError = e;
      debugPrint('Herrero IA: $ep no disponible para ${path.split(Platform.pathSeparator).last}: $e');
    }
  }
  try {
    return OrtOpened(_create(path, threads, OrtEp.cpu), OrtEp.cpu);
  } catch (e) {
    if (lastError != null) debugPrint('Herrero IA: también falló la aceleración: $lastError');
    rethrow;
  }
}

typedef _AppendDmlC = bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtSessionOptions>, ffi.Int);
typedef _AppendDmlD = bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtSessionOptions>, int);

ffi.DynamicLibrary? _ortLib;

/// La DLL de ONNX Runtime realmente cargada (Windows), para buscar funciones exportadas
/// que el paquete no envuelve (OrtSessionOptionsAppendExecutionProvider_DML).
ffi.DynamicLibrary _loadedOrtLibrary() {
  if (_ortLib != null) return _ortLib!;
  final k32 = ffi.DynamicLibrary.open('kernel32.dll');
  final fromAddr = k32.lookupFunction<
      ffi.Int32 Function(ffi.Uint32, ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Pointer<ffi.Void>>),
      int Function(int, ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Pointer<ffi.Void>>)>('GetModuleHandleExW');
  final fileName = k32.lookupFunction<ffi.Uint32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<Utf16>, ffi.Uint32),
      int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<Utf16>, int)>('GetModuleFileNameW');
  final h = calloc<ffi.Pointer<ffi.Void>>();
  final buf = calloc<ffi.Uint16>(32768).cast<Utf16>();
  try {
    // FROM_ADDRESS | UNCHANGED_REFCOUNT: el módulo que contiene la tabla OrtApi
    if (fromAddr(0x4 | 0x2, OrtEnv.instance.ortApiPtr.cast(), h) == 0) {
      throw StateError('No se encuentra el módulo de ONNX Runtime');
    }
    final n = fileName(h.value, buf, 32768);
    return _ortLib = ffi.DynamicLibrary.open(buf.toDartString(length: n));
  } finally {
    calloc.free(h);
    calloc.free(buf);
  }
}

OrtSession _create(String path, int threads, OrtEp ep) {
  final api = OrtEnv.instance.ortApiPtr.ref;
  final pp = calloc<ffi.Pointer<bg.OrtSessionOptions>>();
  OrtStatus.checkOrtStatus(
      api.CreateSessionOptions.asFunction<bg.OrtStatusPtr Function(ffi.Pointer<ffi.Pointer<bg.OrtSessionOptions>>)>()(pp));
  final so = pp.value;
  calloc.free(pp);
  final toFree = <ffi.Pointer>[];
  ffi.Pointer<ffi.Char> c(String s) {
    final p = s.toNativeUtf8().cast<ffi.Char>();
    toFree.add(p);
    return p;
  }

  void check(bg.OrtStatusPtr st) => OrtStatus.checkOrtStatus(st);
  void generic(String name, Map<String, String> opts) {
    final keys = calloc<ffi.Pointer<ffi.Char>>(opts.length + 1);
    final vals = calloc<ffi.Pointer<ffi.Char>>(opts.length + 1);
    toFree..add(keys)..add(vals);
    var i = 0;
    for (final e in opts.entries) {
      keys[i] = c(e.key);
      vals[i] = c(e.value);
      i++;
    }
    check(api.SessionOptionsAppendExecutionProvider.asFunction<
        bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtSessionOptions>, ffi.Pointer<ffi.Char>,
            ffi.Pointer<ffi.Pointer<ffi.Char>>, ffi.Pointer<ffi.Pointer<ffi.Char>>, int)>()(so, c(name), keys, vals, opts.length));
  }

  try {
    check(api.SetIntraOpNumThreads.asFunction<bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtSessionOptions>, int)>()(
        so, threads));
    check(api.SetInterOpNumThreads.asFunction<bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtSessionOptions>, int)>()(so, 1));
    check(api.SetSessionGraphOptimizationLevel.asFunction<
        bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtSessionOptions>, int)>()(so, GraphOptimizationLevel.ortEnableAll.value));
    switch (ep) {
      case OrtEp.cpu:
        break;
      case OrtEp.nnapi:
        check(onnxRuntimeBinding.OrtSessionOptionsAppendExecutionProvider_Nnapi(so, NnapiFlags.cpuDisabled.value));
      case OrtEp.xnnpack:
        check(api.AddSessionConfigEntry.asFunction<
            bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtSessionOptions>, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>)>()(
            so, c('session.intra_op.allow_spinning'), c('0')));
        generic('XNNPACK', {'intra_op_num_threads': '$threads'});
      case OrtEp.directml:
        // DirectML exige ejecución secuencial y sin patrón de memoria
        check(api.DisableMemPattern.asFunction<bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtSessionOptions>)>()(so));
        check(api.SetSessionExecutionMode.asFunction<bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtSessionOptions>, int)>()(
            so, 0));
        final dml = _loadedOrtLibrary()
            .lookupFunction<_AppendDmlC, _AppendDmlD>('OrtSessionOptionsAppendExecutionProvider_DML');
        check(dml(so, 0));
      case OrtEp.cuda:
        check(onnxRuntimeBinding.OrtSessionOptionsAppendExecutionProvider_CUDA(so, 0));
      case OrtEp.openvino:
        generic('OpenVINO', {
          'device_type': 'GPU',
          // la primera compilación del modelo para la GPU tarda: se guarda en caché
          if (GpuPacks.cacheDirFor('openvino') != null) 'cache_dir': GpuPacks.cacheDirFor('openvino')!,
        });
    }
    check(onnxRuntimeBinding.OrtSessionOptionsAppendExecutionProvider_CPU(so, CPUFlags.useArena.value));
    final sp = calloc<ffi.Pointer<bg.OrtSession>>();
    toFree.add(sp);
    // Windows recibe la ruta en UTF-16 (wchar_t), el resto en UTF-8
    final p = Platform.isWindows ? path.toNativeUtf16().cast<ffi.Char>() : path.toNativeUtf8().cast<ffi.Char>();
    toFree.add(p);
    check(api.CreateSession.asFunction<
        bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtEnv>, ffi.Pointer<ffi.Char>, ffi.Pointer<bg.OrtSessionOptions>,
            ffi.Pointer<ffi.Pointer<bg.OrtSession>>)>()(OrtEnv.instance.ptr, p, so, sp));
    return OrtSession.fromAddress(sp.value.address);
  } finally {
    api.ReleaseSessionOptions.asFunction<void Function(ffi.Pointer<bg.OrtSessionOptions>)>()(so);
    for (final p in toFree) {
      calloc.free(p);
    }
  }
}

// ---------------------------------------------------------------------------
// Gráficas del equipo
// ---------------------------------------------------------------------------

/// Nombres de las gráficas (Windows). Vacío si no se pueden leer.
Future<List<String>> detectGpus() async {
  if (!Platform.isWindows) return const [];
  try {
    final r = await Process.run(
        'powershell', ['-NoProfile', '-Command', '(Get-CimInstance Win32_VideoController).Name']);
    return (r.stdout as String)
        .split(RegExp(r'\r?\n'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && !s.contains('Basic Display') && !s.contains('Remote Display'))
        .toList();
  } catch (_) {
    return const [];
  }
}

bool hasNvidia(List<String> gpus) => gpus.any((g) => g.toUpperCase().contains('NVIDIA'));
bool hasIntelGpu(List<String> gpus) => gpus.any((g) => g.toLowerCase().contains('intel'));

// ---------------------------------------------------------------------------
// Paquetes de aceleración descargables (Windows)
// ---------------------------------------------------------------------------

/// Fichero de un paquete (zip, nupkg o wheel; se extraen sus DLL).
class PackFile {
  final String name;
  final String url;
  final int size;
  final String sha256;
  const PackFile(this.name, this.url, this.size, this.sha256);
}

class GpuPack {
  final String id;
  final String name;
  final String summary;
  final AiEngine engine;
  final List<PackFile> files;

  /// Librerías del fabricante: solo se descargan si no están ya instaladas en el equipo.
  final List<PackFile> vendorFiles;
  final List<String> vendorDlls;
  const GpuPack({
    required this.id,
    required this.name,
    required this.summary,
    required this.engine,
    required this.files,
    this.vendorFiles = const [],
    this.vendorDlls = const [],
  });
}

const _pypi = 'https://files.pythonhosted.org/packages';

const gpuPacks = <GpuPack>[
  GpuPack(
    id: 'cuda',
    name: 'NVIDIA CUDA',
    engine: AiEngine.cuda,
    summary: 'ONNX Runtime 1.20.1 para CUDA 12 (paquete oficial de Microsoft). Si no tienes CUDA 12 y cuDNN 9 instalados, '
        'se descargan también sus librerías oficiales de NVIDIA (cuBLAS, cuFFT, cuDNN). Necesita un '
        'controlador NVIDIA reciente (525 o superior).',
    files: [
      // NuGet oficial de Microsoft (la release de GitHub v1.20.1 ya no tiene los zip: 404)
      PackFile(
        'microsoft.ml.onnxruntime.gpu.windows.1.20.1.nupkg',
        'https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime.gpu.windows/1.20.1/microsoft.ml.onnxruntime.gpu.windows.1.20.1.nupkg',
        245964862,
        '00aecf15af66520f3dc60cb3dca2dd79a512b91206c712cf8adeff8b81dff3b3',
      ),
    ],
    vendorDlls: ['cudart64_12.dll', 'cublas64_12.dll', 'cublasLt64_12.dll', 'cufft64_11.dll', 'cudnn64_9.dll'],
    vendorFiles: [
      PackFile(
        'nvidia_cuda_runtime_cu12-12.6.77-py3-none-win_amd64.whl',
        '$_pypi/fa/76/4c80fa138333cc975743fd0687a745fccb30d167f906f13c1c7f9a85e5ea/nvidia_cuda_runtime_cu12-12.6.77-py3-none-win_amd64.whl',
        891773,
        '86c58044c824bf3c173c49a2dbc7a6c8b53cb4e4dca50068be0bf64e9dab3f7f',
      ),
      PackFile(
        'nvidia_cublas_cu12-12.6.4.1-py3-none-win_amd64.whl',
        '$_pypi/84/f7/985e9bdbe3e0ac9298fcc8cfa51a392862a46a0ffaccbbd56939b62a9c83/nvidia_cublas_cu12-12.6.4.1-py3-none-win_amd64.whl',
        434535301,
        '9e4fa264f4d8a4eb0cdbd34beadc029f453b3bafae02401e999cf3d5a5af75f8',
      ),
      PackFile(
        'nvidia_cufft_cu12-11.3.0.4-py3-none-win_amd64.whl',
        '$_pypi/b4/38/36fd800cec8f6e89b7c1576edaaf8076e69ec631644cdbc1b5f2e2b5a9df/nvidia_cufft_cu12-11.3.0.4-py3-none-win_amd64.whl',
        199356881,
        '6048ebddfb90d09d2707efb1fd78d4e3a77cb3ae4dc60e19aab6be0ece2ae464',
      ),
      PackFile(
        'nvidia_cudnn_cu12-9.5.1.17-py3-none-win_amd64.whl',
        '$_pypi/b6/b2/3f60d15f037fa5419d9d7f788b100ef33ea913ae5315c87ca6d6fa606c35/nvidia_cudnn_cu12-9.5.1.17-py3-none-win_amd64.whl',
        565440743,
        'd7af0f8a4f3b4b9dbb3122f2ef553b45694ed9c384d5a75bab197b8eefb79ab8',
      ),
    ],
  ),
  GpuPack(
    id: 'openvino',
    name: 'Intel OpenVINO',
    engine: AiEngine.openvino,
    summary: 'ONNX Runtime 1.20 con OpenVINO 2024 (paquete oficial de Intel, incluye el runtime de OpenVINO). '
        'Para gráficas Intel integradas (Iris Xe, Arc) y NPU de Core Ultra.',
    files: [
      PackFile(
        'intel.ml.onnxruntime.openvino.1.20.0.nupkg',
        'https://api.nuget.org/v3-flatcontainer/intel.ml.onnxruntime.openvino/1.20.0/intel.ml.onnxruntime.openvino.1.20.0.nupkg',
        36331369,
        '1da73044da6f0033c88e2bcd6eb5870cdbfd966e98c2b5495ca2a7666b0fcc04',
      ),
    ],
  ),
];

/// Estado de instalación y descarga de los paquetes de aceleración.
class GpuPacks extends ChangeNotifier {
  GpuPacks._();
  static final GpuPacks instance = GpuPacks._();

  final Map<String, ModelStatus> status = {};
  final Map<String, bool> _cancel = {};
  List<String> gpus = const [];
  bool _loaded = false;

  static String? get _base {
    final la = Platform.environment['LOCALAPPDATA'];
    return la == null || la.isEmpty ? null : '$la\\Herrero\\gpu';
  }

  static String? dirFor(String id) => _base == null ? null : '${_base!}\\$id';

  /// Caché de modelos compilados (OpenVINO).
  static String? cacheDirFor(String id) {
    final d = dirFor(id);
    if (d == null) return null;
    final c = Directory('$d\\cache');
    try {
      if (!c.existsSync()) c.createSync(recursive: true);
    } catch (_) {
      return null;
    }
    return c.path;
  }

  bool installed(String id) {
    final d = dirFor(id);
    return d != null && File('$d\\installed.json').existsSync() && File('$d\\onnxruntime.dll').existsSync();
  }

  Future<void> load() async {
    if (_loaded || !Platform.isWindows) return;
    _loaded = true;
    gpus = await detectGpus();
    for (final p in gpuPacks) {
      status[p.id] ??= ModelStatus(installed(p.id) ? DlState.installed : DlState.notInstalled);
    }
    notifyListeners();
  }

  /// DLL del fabricante que ya están en el PATH (CUDA Toolkit / cuDNN instalados).
  static bool _onPath(List<String> dlls) {
    final dirs = (Platform.environment['PATH'] ?? '').split(';').where((d) => d.trim().isNotEmpty);
    return dlls.every((f) => dirs.any((d) => File('${d.trim()}\\$f').existsSync()));
  }

  /// Ficheros que hay que descargar para [p] en este equipo.
  List<PackFile> filesFor(GpuPack p) =>
      [...p.files, if (p.vendorFiles.isNotEmpty && !_onPath(p.vendorDlls)) ...p.vendorFiles];

  int sizeOf(GpuPack p) => filesFor(p).fold(0, (a, f) => a + f.size);

  void cancel(String id) => _cancel[id] = true;

  Future<void> install(GpuPack p) async {
    final dir = dirFor(p.id);
    if (dir == null) return;
    final st = status[p.id] = ModelStatus(DlState.downloading);
    _cancel[p.id] = false;
    notifyListeners();
    final dl = Directory('${_base!}\\_descargas')..createSync(recursive: true);
    final files = filesFor(p);
    st.bytesTotal = files.fold(0, (a, f) => a + f.size);
    try {
      Directory(dir).createSync(recursive: true);
      var before = 0;
      for (final f in files) {
        final archive = File('${dl.path}\\${f.name}');
        if (!(archive.existsSync() && archive.lengthSync() == f.size)) {
          await ModelManager.instance.fetchVerified(f.url, archive, f.size, f.sha256, (got) {
            st.bytesDone = before + got;
            st.progress = st.bytesTotal == 0 ? 0 : st.bytesDone / st.bytesTotal;
            notifyListeners();
          }, () => _cancel[p.id] == true);
        }
        st.state = DlState.verifying;
        notifyListeners();
        await _extractDlls(archive, dir);
        archive.deleteSync();
        st.state = DlState.downloading;
        before += f.size;
      }
      if (!File('$dir\\onnxruntime.dll').existsSync()) {
        throw Exception('El paquete descargado no trae onnxruntime.dll.');
      }
      File('$dir\\installed.json').writeAsStringSync(jsonEncode({
        'pack': p.id,
        'files': [for (final f in files) f.name],
        'date': DateTime.now().toIso8601String(),
      }));
      status[p.id] = ModelStatus(DlState.installed, progress: 1);
    } catch (e) {
      status[p.id] = _cancel[p.id] == true
          ? ModelStatus(DlState.notInstalled)
          : ModelStatus(DlState.error, error: ModelManager.friendlyDownloadError(e));
    }
    notifyListeners();
  }

  /// Extrae las DLL de un zip / nupkg / wheel en [dir] (planas, sin subcarpetas).
  static Future<void> _extractDlls(File archive, String dir) async {
    final tmp = Directory('${archive.path}.x');
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    tmp.createSync(recursive: true);
    try {
      // tar.exe (bsdtar) viene con Windows 10 1803 o posterior y abre zip
      final r = await Process.run('tar', ['-xf', archive.path, '-C', tmp.path]);
      if (r.exitCode != 0) throw Exception('No se pudo descomprimir ${archive.uri.pathSegments.last}: ${r.stderr}');
      await for (final e in tmp.list(recursive: true)) {
        if (e is File && e.path.toLowerCase().endsWith('.dll') && !e.path.toLowerCase().endsWith('_debug.dll')) {
          final name = e.uri.pathSegments.last;
          final dst = File('$dir\\$name');
          if (dst.existsSync()) dst.deleteSync();
          e.renameSync(dst.path);
        }
      }
    } finally {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  /// Borra el paquete. No se puede mientras sus DLL estén cargadas (las bloquea Windows).
  Future<String?> remove(GpuPack p) async {
    final dir = dirFor(p.id);
    if (dir == null) return null;
    if (loadedRuntimeId() == p.id) {
      return 'Herrero está usando este paquete. Elige otro motor, reinicia la app y bórralo después.';
    }
    try {
      Directory(dir).deleteSync(recursive: true);
    } catch (e) {
      return 'No se pudo borrar: $e';
    }
    status[p.id] = ModelStatus(DlState.notInstalled);
    notifyListeners();
    return null;
  }

  /// Runtime que debe cargarse con [engine]: id del paquete o '' para el de serie (DirectML).
  String desiredRuntime(AiEngine engine) {
    switch (engine) {
      case AiEngine.cuda:
        return installed('cuda') ? 'cuda' : '';
      case AiEngine.openvino:
        return installed('openvino') ? 'openvino' : '';
      case AiEngine.auto:
        if (installed('cuda') && hasNvidia(gpus)) return 'cuda';
        if (installed('openvino') && hasIntelGpu(gpus)) return 'openvino';
        return '';
      default:
        return '';
    }
  }

  /// Guarda qué runtime cargar al arrancar (lo lee scripts/ort_loader.dart).
  void syncRuntime(AiEngine engine) {
    if (!Platform.isWindows || _base == null) return;
    try {
      Directory(_base!).createSync(recursive: true);
      File('${_base!}\\runtime.txt').writeAsStringSync(desiredRuntime(engine));
    } catch (_) {}
    notifyListeners();
  }

  /// Hay que reiniciar la app para cambiar de runtime (ya hay uno cargado y es otro).
  bool needsRestart(AiEngine engine) {
    final loaded = loadedRuntimeId();
    return loaded != null && loaded != desiredRuntime(engine);
  }
}

/// Runtime ya cargado en este proceso: id del paquete, '' el de serie o null si todavía
/// no se ha usado la IA (lo marca el cargador en la variable HERRERO_ORT_DIR).
String? loadedRuntimeId() {
  if (!Platform.isWindows) return null;
  final k32 = ffi.DynamicLibrary.open('kernel32.dll');
  final f = k32.lookupFunction<ffi.Uint32 Function(ffi.Pointer<Utf16>, ffi.Pointer<Utf16>, ffi.Uint32),
      int Function(ffi.Pointer<Utf16>, ffi.Pointer<Utf16>, int)>('GetEnvironmentVariableW');
  final n = 'HERRERO_ORT_DIR'.toNativeUtf16();
  final buf = calloc<ffi.Uint16>(32768).cast<Utf16>();
  try {
    final len = f(n, buf, 32768);
    if (len == 0) return null;
    final dir = buf.toDartString(length: len);
    for (final p in gpuPacks) {
      if (dir.toLowerCase() == (GpuPacks.dirFor(p.id) ?? '').toLowerCase()) return p.id;
    }
    return '';
  } finally {
    calloc.free(n);
    calloc.free(buf);
  }
}
