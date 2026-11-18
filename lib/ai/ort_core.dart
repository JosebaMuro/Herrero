// Aceleración de la IA local: elección del proveedor de ONNX Runtime (CPU, GPU, NPU)
// con vuelta a CPU, paquetes opcionales (NVIDIA CUDA, Intel OpenVINO) y arranque de la
// gráfica NVIDIA en Linux.
//
// Dart puro (sin Flutter): lo usan la app (a través de accel.dart) y la TUI de terminal.
//
// Qué hay en cada plataforma (ONNX Runtime 1.20):
// * Windows: DirectML va de serie (DirectX 12: GPU NVIDIA, AMD e Intel). CUDA y
//   OpenVINO son descargas opcionales porque pesan mucho. ONNX Runtime no tiene
//   proveedor Vulkan: en Windows las gráficas AMD van por DirectML.
// * Linux: la CPU de serie y el paquete NVIDIA CUDA descargable (con cuDNN, cuBLAS…).
//   Funciona igual sin escritorio (modo texto), y la app despierta la gráfica al arrancar.
// * Android: NNAPI (GPU, DSP o NPU del fabricante) y XNNPACK (CPU ARM optimizada).
import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:onnxruntime/onnxruntime.dart';
// ignore: implementation_imports
import 'package:onnxruntime/src/bindings/bindings.dart' show onnxRuntimeBinding;
// ignore: implementation_imports
import 'package:onnxruntime/src/bindings/onnxruntime_bindings_generated.dart' as bg;

import 'download.dart';

/// Mensajes de diagnóstico (solo en depuración, como debugPrint; la TUI los redirige).
void Function(String) ortLog = (m) {
  assert(() {
    // ignore: avoid_print
    print(m);
    return true;
  }());
};

/// Motor de ejecución preferido (el índice se guarda en ajustes: no cambiar el orden).
enum AiEngine { auto, cpu, nnapi, directml, cuda, openvino, xnnpack }

/// Motores que tienen sentido en esta plataforma, en el orden en que se muestran.
List<AiEngine> enginesForPlatform() {
  if (Platform.isWindows) {
    return const [AiEngine.auto, AiEngine.directml, AiEngine.cuda, AiEngine.openvino, AiEngine.cpu];
  }
  if (Platform.isLinux) return const [AiEngine.auto, AiEngine.cuda, AiEngine.cpu];
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
              'paquete y tienes esa gráfica; si no, DirectML con la gráfica más potente. Si algo falla, sigue en CPU.';
        }
        if (Platform.isLinux) {
          return 'Usa CUDA si has descargado su paquete y hay una gráfica NVIDIA; si no, la CPU. '
              'Si algo falla, sigue en CPU.';
        }
        if (Platform.isAndroid) return 'Usa la NPU/GPU del móvil donde es fiable y la CPU para el resto.';
        return 'Usa la CPU.';
      case AiEngine.cpu:
        return 'Solo procesador. El más compatible y el que da resultados de referencia.';
      case AiEngine.nnapi:
        return 'Fuerza la aceleración Android NNAPI (GPU, DSP o NPU del fabricante) en todos los modelos; '
            'lo que no admite va a la CPU y, si falla, vuelve a CPU.';
      case AiEngine.directml:
        return 'GPU por DirectX 12: vale para gráficas NVIDIA, AMD e Intel (también integradas). En portátiles '
            'con dos gráficas elige la de alto rendimiento. Viene de serie, sin descargas.';
      case AiEngine.cuda:
        return 'Gráficas NVIDIA (GeForce, RTX, Quadro; también portátiles como la RTX 4050 de 6 GB) con CUDA 12 '
            'y cuDNN 9. Lo más rápido en NVIDIA. Necesita descargar el paquete CUDA.';
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
  if (Platform.isWindows || Platform.isLinux) {
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
      ortLog('Herrero IA: $ep no disponible para ${path.split(Platform.pathSeparator).last}: $e');
    }
  }
  try {
    return OrtOpened(_create(path, threads, OrtEp.cpu), OrtEp.cpu);
  } catch (e) {
    if (lastError != null) ortLog('Herrero IA: también falló la aceleración: $lastError');
    rethrow;
  }
}

/// Opciones del proveedor CUDA pensadas para gráficas con poca memoria (portátiles de
/// 4–8 GB como la RTX 4050 de 6 GB):
/// * la reserva crece solo lo pedido (por defecto dobla y agota la VRAM con la UNet);
/// * cuDNN elige el algoritmo por heurística y sin el espacio de trabajo máximo (la
///   búsqueda exhaustiva pide cientos de MB extra y tarda en la primera imagen);
/// * HERRERO_CUDA_MEM_MB limita la memoria de cada sesión si hace falta.
Map<String, String> cudaProviderOptions() {
  final limit = int.tryParse(Platform.environment['HERRERO_CUDA_MEM_MB'] ?? '') ?? 0;
  return {
    'device_id': '0',
    'arena_extend_strategy': 'kSameAsRequested',
    'cudnn_conv_algo_search': 'HEURISTIC',
    'cudnn_conv_use_max_workspace': '0',
    'do_copy_in_default_stream': '1',
    if (limit > 0) 'gpu_mem_limit': '${limit * 1024 * 1024}',
  };
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

  (ffi.Pointer<ffi.Pointer<ffi.Char>>, ffi.Pointer<ffi.Pointer<ffi.Char>>) kv(Map<String, String> opts) {
    final keys = calloc<ffi.Pointer<ffi.Char>>(opts.length + 1);
    final vals = calloc<ffi.Pointer<ffi.Char>>(opts.length + 1);
    toFree
      ..add(keys)
      ..add(vals);
    var i = 0;
    for (final e in opts.entries) {
      keys[i] = c(e.key);
      vals[i] = c(e.value);
      i++;
    }
    return (keys, vals);
  }

  void check(bg.OrtStatusPtr st) => OrtStatus.checkOrtStatus(st);
  void generic(String name, Map<String, String> opts) {
    final (keys, vals) = kv(opts);
    check(api.SessionOptionsAppendExecutionProvider.asFunction<
        bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtSessionOptions>, ffi.Pointer<ffi.Char>,
            ffi.Pointer<ffi.Pointer<ffi.Char>>, ffi.Pointer<ffi.Pointer<ffi.Char>>, int)>()(so, c(name), keys, vals, opts.length));
  }

  void cuda() {
    // CUDA V2 (opciones por clave); si no se puede, la llamada antigua sin opciones
    final op = calloc<ffi.Pointer<bg.OrtCUDAProviderOptionsV2>>();
    toFree.add(op);
    ffi.Pointer<bg.OrtCUDAProviderOptionsV2> opts = ffi.nullptr;
    try {
      check(api.CreateCUDAProviderOptions.asFunction<
          bg.OrtStatusPtr Function(ffi.Pointer<ffi.Pointer<bg.OrtCUDAProviderOptionsV2>>)>()(op));
      opts = op.value;
      final o = cudaProviderOptions();
      final (keys, vals) = kv(o);
      check(api.UpdateCUDAProviderOptions.asFunction<
          bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtCUDAProviderOptionsV2>, ffi.Pointer<ffi.Pointer<ffi.Char>>,
              ffi.Pointer<ffi.Pointer<ffi.Char>>, int)>()(opts, keys, vals, o.length));
      check(api.SessionOptionsAppendExecutionProvider_CUDA_V2.asFunction<
          bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtSessionOptions>, ffi.Pointer<bg.OrtCUDAProviderOptionsV2>)>()(
          so, opts));
    } catch (e) {
      ortLog('Herrero IA: opciones CUDA V2 no aplicadas ($e); CUDA con opciones por defecto');
      check(onnxRuntimeBinding.OrtSessionOptionsAppendExecutionProvider_CUDA(so, 0));
    } finally {
      if (opts != ffi.nullptr) {
        api.ReleaseCUDAProviderOptions.asFunction<void Function(ffi.Pointer<bg.OrtCUDAProviderOptionsV2>)>()(opts);
      }
    }
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
        // En portátiles con dos gráficas, el adaptador 0 suele ser la integrada: se pide
        // la de alto rendimiento (la NVIDIA). Si este ONNX Runtime no lo admite, el 0.
        try {
          generic('DML', {'performance_preference': 'high_performance', 'device_filter': 'gpu'});
        } catch (e) {
          ortLog('Herrero IA: DirectML sin preferencia de alto rendimiento ($e)');
          final dml = _loadedOrtLibrary()
              .lookupFunction<_AppendDmlC, _AppendDmlD>('OrtSessionOptionsAppendExecutionProvider_DML');
          check(dml(so, 0));
        }
      case OrtEp.cuda:
        cuda();
      case OrtEp.openvino:
        final cache = GpuPackStore.cacheDirFor('openvino');
        generic('OpenVINO', {
          'device_type': 'GPU',
          // la primera compilación del modelo para la GPU tarda: se guarda en caché
          if (cache != null) 'cache_dir': cache,
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

/// Gráfica NVIDIA según nvidia-smi.
class NvidiaGpu {
  final String name;
  final int vramMb;
  final String driver;
  const NvidiaGpu(this.name, this.vramMb, this.driver);
  @override
  String toString() => '$name · ${(vramMb / 1024).toStringAsFixed(vramMb % 1024 == 0 ? 0 : 1)} GB';
}

/// Gráficas NVIDIA con nombre, memoria y controlador (vacío si no hay nvidia-smi).
Future<List<NvidiaGpu>> detectNvidia() async {
  if (!Platform.isWindows && !Platform.isLinux) return const [];
  try {
    final r = await Process.run('nvidia-smi',
        ['--query-gpu=name,memory.total,driver_version', '--format=csv,noheader,nounits']).timeout(const Duration(seconds: 15));
    if (r.exitCode != 0) return const [];
    return [
      for (final l in (r.stdout as String).split(RegExp(r'\r?\n')))
        if (l.trim().isNotEmpty)
          () {
            final f = l.split(',').map((s) => s.trim()).toList();
            return NvidiaGpu(f[0], f.length > 1 ? int.tryParse(f[1]) ?? 0 : 0, f.length > 2 ? f[2] : '');
          }()
    ];
  } catch (_) {
    return const [];
  }
}

/// Nombres de las gráficas (Windows y Linux). Vacío si no se pueden leer.
Future<List<String>> detectGpus() async {
  if (Platform.isWindows) {
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
  if (!Platform.isLinux) return const [];
  final out = <String>[];
  // NVIDIA con el controlador cargado: nombre exacto
  try {
    final dir = Directory('/proc/driver/nvidia/gpus');
    if (dir.existsSync()) {
      for (final g in dir.listSync()) {
        final info = File('${g.path}/information');
        if (!info.existsSync()) continue;
        for (final l in info.readAsLinesSync()) {
          if (l.startsWith('Model:')) {
            final n = l.substring(6).trim();
            out.add(n.toUpperCase().contains('NVIDIA') ? n : 'NVIDIA $n');
          }
        }
      }
    }
  } catch (_) {}
  // el resto (y NVIDIA sin controlador) por lspci
  try {
    final r = await Process.run('lspci', const []);
    if (r.exitCode == 0) {
      for (final l in (r.stdout as String).split('\n')) {
        if (!RegExp(r'VGA compatible|3D controller|Display controller').hasMatch(l)) continue;
        final i = l.indexOf(': ');
        final n = i < 0 ? l.trim() : l.substring(i + 2).trim();
        if (n.toUpperCase().contains('NVIDIA') && out.any((o) => o.toUpperCase().contains('NVIDIA'))) continue;
        out.add(n);
      }
    }
  } catch (_) {}
  if (out.isEmpty && linuxNvidiaPciPresent()) out.add('NVIDIA (sin controlador cargado)');
  return out;
}

bool hasNvidia(List<String> gpus) => gpus.any((g) => g.toUpperCase().contains('NVIDIA'));
bool hasIntelGpu(List<String> gpus) => gpus.any((g) => g.toLowerCase().contains('intel'));

/// Hay una gráfica NVIDIA en el bus PCI (Linux), con o sin controlador.
bool linuxNvidiaPciPresent() {
  try {
    for (final d in Directory('/sys/bus/pci/devices').listSync()) {
      final v = File('${d.path}/vendor');
      final c = File('${d.path}/class');
      if (!v.existsSync() || !c.existsSync()) continue;
      // 0x10de = NVIDIA; clase 0x03xxxx = pantalla (VGA, 3D)
      if (v.readAsStringSync().trim() == '0x10de' && c.readAsStringSync().trim().startsWith('0x03')) return true;
    }
  } catch (_) {}
  return false;
}

// ---------------------------------------------------------------------------
// Despertar la gráfica NVIDIA al arrancar (Linux)
// ---------------------------------------------------------------------------

enum GpuWakeState { notNvidia, ready, noDriver, noDevice, failed }

/// Resultado de preparar la gráfica NVIDIA.
class GpuWake {
  final GpuWakeState state;
  final String message;

  /// Comandos para arreglarlo a mano (con sudo), si hace falta.
  final List<String> fix;
  final int devices;
  final Duration time;
  const GpuWake(this.state, this.message, {this.fix = const [], this.devices = 0, this.time = Duration.zero});
  bool get ok => state == GpuWakeState.ready;
}

const _fixModules = [
  'echo -e "nvidia\\nnvidia_uvm" | sudo tee /etc/modules-load.d/nvidia.conf',
  'sudo modprobe nvidia && sudo modprobe nvidia_uvm',
  'sudo systemctl enable --now nvidia-persistenced',
];

Future<GpuWake>? _wake;

/// Prepara la gráfica NVIDIA una vez por proceso (en Linux; en el resto, no hace nada).
///
/// Sin escritorio (modo texto) nadie inicializa la gráfica: puede faltar el módulo
/// nvidia_uvm o los dispositivos /dev/nvidia*, y CUDA falla con «no CUDA-capable device».
/// 1. Si faltan, se crean con nvidia-modprobe (viene con el controlador y no pide
///    contraseña: es setuid).
/// 2. Se llama a cuInit en libcuda: saca la gráfica del reposo (en portátiles se apaga
///    sola) y comprueba que CUDA la ve, antes de la primera petición a la IA.
Future<GpuWake> wakeNvidiaGpu() => _wake ??= _doWake();

Future<GpuWake> _doWake() async {
  if (!Platform.isLinux) return const GpuWake(GpuWakeState.notNvidia, 'No es Linux.');
  final sw = Stopwatch()..start();
  final pci = linuxNvidiaPciPresent();
  bool driver() => File('/proc/driver/nvidia/version').existsSync();
  bool nodes() => File('/dev/nvidiactl').existsSync() && File('/dev/nvidia-uvm').existsSync();
  if (!pci && !driver()) return const GpuWake(GpuWakeState.notNvidia, 'No hay gráfica NVIDIA.');

  if (!driver() || !nodes()) {
    for (final args in const <List<String>>[
      ['-c=0', '-u'],
      ['-u'],
      [],
    ]) {
      try {
        await Process.run('nvidia-modprobe', args).timeout(const Duration(seconds: 20));
      } catch (_) {}
      if (driver() && nodes()) break;
    }
  }
  if (!driver()) {
    return GpuWake(
      GpuWakeState.noDriver,
      'Hay una gráfica NVIDIA pero su controlador no está cargado (¿no instalado, o bloqueado por '
      'Secure Boot?). La IA usará la CPU.',
      fix: const [
        'sudo apt install nvidia-driver   # Debian (non-free); en Ubuntu: sudo ubuntu-drivers install',
        'sudo modprobe nvidia && sudo modprobe nvidia_uvm',
        'mokutil --sb-state   # si Secure Boot está activo, firma el módulo o desactívalo',
      ],
      time: sw.elapsed,
    );
  }
  final r = await Isolate.run(_cuInit);
  if (r.$1 == 0 && r.$2 > 0) {
    return GpuWake(GpuWakeState.ready, 'Gráfica NVIDIA lista para CUDA (${r.$2} dispositivo${r.$2 > 1 ? 's' : ''}).',
        devices: r.$2, time: sw.elapsed);
  }
  if (r.$1 == -1) {
    return GpuWake(GpuWakeState.failed, 'No se encuentra libcuda.so.1 (lo instala el controlador NVIDIA). ${r.$3}',
        fix: const ['sudo apt install libcuda1   # Debian; en Ubuntu viene con nvidia-driver-XXX'], time: sw.elapsed);
  }
  // 100 = CUDA_ERROR_NO_DEVICE: casi siempre faltan /dev/nvidia-uvm o los permisos
  final noDev = r.$1 == 100 || !nodes();
  return GpuWake(
    noDev ? GpuWakeState.noDevice : GpuWakeState.failed,
    noDev
        ? 'CUDA no ve la gráfica: faltan los dispositivos /dev/nvidia-uvm (sin escritorio nadie los crea) '
            'o no tienes permiso. La IA usará la CPU hasta arreglarlo.'
        : 'CUDA no arranca (error ${r.$1}${r.$3.isEmpty ? '' : ': ${r.$3}'}). La IA usará la CPU.',
    fix: [..._fixModules, if (noDev) 'sudo usermod -aG video,render \$USER   # y vuelve a iniciar sesión'],
    time: sw.elapsed,
  );
}

typedef _CuInitC = ffi.Int32 Function(ffi.Uint32);
typedef _CuInitD = int Function(int);
typedef _CuCountC = ffi.Int32 Function(ffi.Pointer<ffi.Int32>);
typedef _CuCountD = int Function(ffi.Pointer<ffi.Int32>);
typedef _CuErrC = ffi.Int32 Function(ffi.Int32, ffi.Pointer<ffi.Pointer<Utf8>>);
typedef _CuErrD = int Function(int, ffi.Pointer<ffi.Pointer<Utf8>>);

/// (código CUDA, dispositivos, texto del error). Código -1: no hay libcuda.
(int, int, String) _cuInit() {
  ffi.DynamicLibrary lib;
  try {
    lib = ffi.DynamicLibrary.open('libcuda.so.1');
  } catch (e) {
    return (-1, 0, '');
  }
  String err(int code) {
    try {
      final f = lib.lookupFunction<_CuErrC, _CuErrD>('cuGetErrorString');
      final p = calloc<ffi.Pointer<Utf8>>();
      try {
        return f(code, p) == 0 && p.value != ffi.nullptr ? p.value.toDartString() : '';
      } finally {
        calloc.free(p);
      }
    } catch (_) {
      return '';
    }
  }

  final init = lib.lookupFunction<_CuInitC, _CuInitD>('cuInit');
  final rc = init(0);
  if (rc != 0) return (rc, 0, err(rc));
  final count = lib.lookupFunction<_CuCountC, _CuCountD>('cuDeviceGetCount');
  final n = calloc<ffi.Int32>();
  try {
    final rc2 = count(n);
    return (rc2, rc2 == 0 ? n.value : 0, rc2 == 0 ? '' : err(rc2));
  } finally {
    calloc.free(n);
  }
}

// ---------------------------------------------------------------------------
// Paquetes de aceleración descargables (Windows y Linux)
// ---------------------------------------------------------------------------

/// Fichero de un paquete (zip, nupkg o wheel; se extraen sus bibliotecas).
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

const _windowsPacks = <GpuPack>[
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

const _linuxPacks = <GpuPack>[
  GpuPack(
    id: 'cuda',
    name: 'NVIDIA CUDA',
    engine: AiEngine.cuda,
    summary: 'ONNX Runtime 1.20.1 para CUDA 12 en Linux (paquete oficial de Microsoft). Si el sistema no tiene CUDA 12 y '
        'cuDNN 9, se descargan también sus librerías oficiales de NVIDIA (cudart, cuBLAS, cuFFT, cuRAND, NVRTC, cuDNN). '
        'Necesita el controlador NVIDIA 525.60 o superior; funciona también sin escritorio (modo texto).',
    files: [
      PackFile(
        'microsoft.ml.onnxruntime.gpu.linux.1.20.1.nupkg',
        'https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime.gpu.linux/1.20.1/microsoft.ml.onnxruntime.gpu.linux.1.20.1.nupkg',
        258663601,
        '02b829019e5624d4464b0debc7b484d2ef9b4b4015a07ed02f48e183a845d4ea',
      ),
    ],
    vendorDlls: [
      'libcudart.so.12',
      'libcublas.so.12',
      'libcublasLt.so.12',
      'libcufft.so.11',
      'libcurand.so.10',
      'libnvrtc.so.12',
      'libcudnn.so.9',
    ],
    vendorFiles: [
      PackFile(
        'nvidia_cuda_runtime_cu12-12.6.77-py3-none-manylinux2014_x86_64.manylinux_2_17_x86_64.whl',
        '$_pypi/e1/23/e717c5ac26d26cf39a27fbc076240fad2e3b817e5889d671b67f4f9f49c5/nvidia_cuda_runtime_cu12-12.6.77-py3-none-manylinux2014_x86_64.manylinux_2_17_x86_64.whl',
        897690,
        'ba3b56a4f896141e25e19ab287cd71e52a6a0f4b29d0d31609f60e3b4d5219b7',
      ),
      PackFile(
        'nvidia_cublas_cu12-12.6.4.1-py3-none-manylinux2014_x86_64.manylinux_2_17_x86_64.whl',
        '$_pypi/af/eb/ff4b8c503fa1f1796679dce648854d58751982426e4e4b37d6fce49d259c/nvidia_cublas_cu12-12.6.4.1-py3-none-manylinux2014_x86_64.manylinux_2_17_x86_64.whl',
        393138322,
        '08ed2686e9875d01b58e3cb379c6896df8e76c75e0d4a7f7dace3d7b6d9ef8eb',
      ),
      PackFile(
        'nvidia_cufft_cu12-11.3.0.4-py3-none-manylinux2014_x86_64.manylinux_2_17_x86_64.whl',
        '$_pypi/8f/16/73727675941ab8e6ffd86ca3a4b7b47065edcca7a997920b831f8147c99d/nvidia_cufft_cu12-11.3.0.4-py3-none-manylinux2014_x86_64.manylinux_2_17_x86_64.whl',
        200221632,
        'ccba62eb9cef5559abd5e0d54ceed2d9934030f51163df018532142a8ec533e5',
      ),
      PackFile(
        'nvidia_curand_cu12-10.3.7.77-py3-none-manylinux2014_x86_64.manylinux_2_17_x86_64.whl',
        '$_pypi/73/1b/44a01c4e70933637c93e6e1a8063d1e998b50213a6b65ac5a9169c47e98e/nvidia_curand_cu12-10.3.7.77-py3-none-manylinux2014_x86_64.manylinux_2_17_x86_64.whl',
        56279010,
        'a42cd1344297f70b9e39a1e4f467a4e1c10f1da54ff7a85c12197f6c652c8bdf',
      ),
      PackFile(
        'nvidia_cuda_nvrtc_cu12-12.6.77-py3-none-manylinux2014_x86_64.whl',
        '$_pypi/75/2e/46030320b5a80661e88039f59060d1790298b4718944a65a7f2aeda3d9e9/nvidia_cuda_nvrtc_cu12-12.6.77-py3-none-manylinux2014_x86_64.whl',
        23650380,
        '35b0cc6ee3a9636d5409133e79273ce1f3fd087abb0532d2d2e8fff1fe9efc53',
      ),
      PackFile(
        'nvidia_cudnn_cu12-9.5.1.17-py3-none-manylinux_2_28_x86_64.whl',
        '$_pypi/2a/78/4535c9c7f859a64781e43c969a3a7e84c54634e319a996d43ef32ce46f83/nvidia_cudnn_cu12-9.5.1.17-py3-none-manylinux_2_28_x86_64.whl',
        570988386,
        '30ac3869f6db17d170e0e556dd6cc5eee02647abc31ca856634d5a40f82c15b2',
      ),
    ],
  ),
];

/// Paquetes de aceleración de esta plataforma.
List<GpuPack> get gpuPacks => Platform.isWindows
    ? _windowsPacks
    : Platform.isLinux
        ? _linuxPacks
        : const [];

/// Nombre de la biblioteca principal de ONNX Runtime dentro de un paquete.
String get _ortLibName => Platform.isWindows ? 'onnxruntime.dll' : 'libonnxruntime.so';

/// Bibliotecas que se extraen de los paquetes en Linux (el proveedor TensorRT no se usa).
final _linuxLibRe = RegExp(
    r'^lib(onnxruntime(_providers_(cuda|shared))?|cudart|cublasLt|cublas|cufft|curand|cudnn[a-z_]*|nvrtc[a-z-]*|nvJitLink)\.so(\.\d+)*$');

/// Estado de instalación y descarga de los paquetes de aceleración (Dart puro; la app
/// lo envuelve en un ChangeNotifier, GpuPacks, y la TUI lo usa directamente).
class GpuPackStore {
  GpuPackStore();

  final Map<String, ModelStatus> status = {};
  final Map<String, bool> _cancel = {};
  final List<void Function()> _listeners = [];
  List<String> gpus = const [];
  List<NvidiaGpu> nvidia = const [];
  GpuWake? wake;
  Future<void>? _loading;

  void addListener(void Function() l) => _listeners.add(l);
  void removeListener(void Function() l) => _listeners.remove(l);
  void notifyListeners() {
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  static String get _sep => Platform.pathSeparator;

  /// Carpeta de los paquetes (la misma que usa scripts/ort_loader.dart).
  static String? get base {
    if (Platform.isWindows) {
      final la = Platform.environment['LOCALAPPDATA'];
      return la == null || la.isEmpty ? null : '$la\\Herrero\\gpu';
    }
    if (Platform.isLinux) {
      final xdg = Platform.environment['XDG_DATA_HOME'];
      if (xdg != null && xdg.startsWith('/')) return '$xdg/herrero/gpu';
      final home = Platform.environment['HOME'];
      return home == null || home.isEmpty ? null : '$home/.local/share/herrero/gpu';
    }
    return null;
  }

  static String? dirFor(String id) => base == null ? null : '${base!}$_sep$id';

  /// Caché de modelos compilados (OpenVINO).
  static String? cacheDirFor(String id) {
    final d = dirFor(id);
    if (d == null) return null;
    final c = Directory('$d${_sep}cache');
    try {
      if (!c.existsSync()) c.createSync(recursive: true);
    } catch (_) {
      return null;
    }
    return c.path;
  }

  bool installed(String id) {
    final d = dirFor(id);
    return d != null && File('$d${_sep}installed.json').existsSync() && File('$d$_sep$_ortLibName').existsSync();
  }

  /// Detecta las gráficas (y en Linux despierta la NVIDIA). Una vez por proceso.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    if (!(Platform.isWindows || Platform.isLinux)) return;
    if (Platform.isLinux) wake = await wakeNvidiaGpu();
    gpus = await detectGpus();
    nvidia = await detectNvidia();
    for (final p in gpuPacks) {
      status[p.id] ??= ModelStatus(installed(p.id) ? DlState.installed : DlState.notInstalled);
    }
    notifyListeners();
  }

  static Set<String>? _ldCache;

  /// Bibliotecas del fabricante ya instaladas (CUDA Toolkit / cuDNN del sistema).
  static bool _onPath(List<String> libs) {
    if (Platform.isWindows) {
      final dirs = (Platform.environment['PATH'] ?? '').split(';').where((d) => d.trim().isNotEmpty);
      return libs.every((f) => dirs.any((d) => File('${d.trim()}\\$f').existsSync()));
    }
    if (_ldCache == null) {
      final s = <String>{};
      for (final exe in const ['/sbin/ldconfig', '/usr/sbin/ldconfig', 'ldconfig']) {
        try {
          final r = Process.runSync(exe, const ['-p']);
          if (r.exitCode != 0) continue;
          for (final l in (r.stdout as String).split('\n')) {
            final t = l.trim();
            final i = t.indexOf(' ');
            if (i > 0) s.add(t.substring(0, i));
          }
          break;
        } catch (_) {}
      }
      _ldCache = s;
    }
    final dirs = (Platform.environment['LD_LIBRARY_PATH'] ?? '').split(':').where((d) => d.trim().isNotEmpty);
    return libs.every((f) => _ldCache!.contains(f) || dirs.any((d) => File('${d.trim()}/$f').existsSync()));
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
    final dl = Directory('${base!}${_sep}_descargas')..createSync(recursive: true);
    final files = filesFor(p);
    st.bytesTotal = files.fold(0, (a, f) => a + f.size);
    try {
      Directory(dir).createSync(recursive: true);
      var before = 0;
      var last = DateTime.now();
      for (final f in files) {
        final archive = File('${dl.path}$_sep${f.name}');
        if (!(archive.existsSync() && archive.lengthSync() == f.size)) {
          await downloadVerified(f.url, archive, f.size, f.sha256, (got) {
            st.bytesDone = before + got;
            st.progress = st.bytesTotal == 0 ? 0 : st.bytesDone / st.bytesTotal;
            if (DateTime.now().difference(last).inMilliseconds > 250) {
              last = DateTime.now();
              notifyListeners();
            }
          }, () => _cancel[p.id] == true);
        }
        st.state = DlState.verifying;
        notifyListeners();
        await _extractLibs(archive, dir);
        archive.deleteSync();
        st.state = DlState.downloading;
        before += f.size;
      }
      if (!File('$dir$_sep$_ortLibName').existsSync()) {
        throw Exception('El paquete descargado no trae $_ortLibName.');
      }
      File('$dir${_sep}installed.json').writeAsStringSync(jsonEncode({
        'pack': p.id,
        'files': [for (final f in files) f.name],
        'date': DateTime.now().toIso8601String(),
      }));
      status[p.id] = ModelStatus(DlState.installed, progress: 1);
    } catch (e) {
      status[p.id] = _cancel[p.id] == true
          ? ModelStatus(DlState.notInstalled)
          : ModelStatus(DlState.error, error: friendlyDownloadError(e));
    }
    notifyListeners();
  }

  /// Extrae las bibliotecas de un zip / nupkg / wheel en [dir] (planas, sin subcarpetas).
  static Future<void> _extractLibs(File archive, String dir) async {
    final tmp = Directory('${archive.path}.x');
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    tmp.createSync(recursive: true);
    try {
      if (Platform.isWindows) {
        // tar.exe (bsdtar) viene con Windows 10 1803 o posterior y abre zip
        final r = await Process.run('tar', ['-xf', archive.path, '-C', tmp.path]);
        if (r.exitCode != 0) throw Exception('No se pudo descomprimir ${archive.uri.pathSegments.last}: ${r.stderr}');
      } else {
        // unzip; si no está instalado, bsdtar o el módulo zipfile de Python
        ProcessResult? ok;
        Object? err;
        for (final (exe, args) in [
          ('unzip', ['-o', '-q', archive.path, '-d', tmp.path]),
          ('bsdtar', ['-xf', archive.path, '-C', tmp.path]),
          ('python3', ['-m', 'zipfile', '-e', archive.path, tmp.path]),
        ]) {
          try {
            final r = await Process.run(exe, args);
            if (r.exitCode == 0) {
              ok = r;
              break;
            }
            err = r.stderr;
          } catch (e) {
            err = e;
          }
        }
        if (ok == null) {
          throw Exception('No se pudo descomprimir ${archive.uri.pathSegments.last} (instala unzip): $err');
        }
      }
      await for (final e in tmp.list(recursive: true)) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last;
        final lower = name.toLowerCase();
        final want = Platform.isWindows
            ? lower.endsWith('.dll') && !lower.endsWith('_debug.dll')
            : _linuxLibRe.hasMatch(name);
        if (!want) continue;
        final dst = File('$dir$_sep$name');
        if (dst.existsSync()) dst.deleteSync();
        e.renameSync(dst.path);
      }
    } finally {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  /// Borra el paquete. No se puede mientras sus bibliotecas estén cargadas.
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

  /// Runtime que debe cargarse con [engine]: id del paquete o '' para el de serie.
  String desiredRuntime(AiEngine engine) {
    switch (engine) {
      case AiEngine.cuda:
        return installed('cuda') ? 'cuda' : '';
      case AiEngine.openvino:
        return installed('openvino') ? 'openvino' : '';
      case AiEngine.auto:
        // en Linux sin escritorio el nombre puede no leerse aún: basta con que haya NVIDIA
        final nv = hasNvidia(gpus) || nvidia.isNotEmpty || (Platform.isLinux && linuxNvidiaPciPresent());
        if (installed('cuda') && nv) return 'cuda';
        if (installed('openvino') && hasIntelGpu(gpus)) return 'openvino';
        return '';
      default:
        return '';
    }
  }

  /// Guarda qué runtime cargar al arrancar (lo lee scripts/ort_loader.dart).
  void syncRuntime(AiEngine engine) {
    if (!(Platform.isWindows || Platform.isLinux) || base == null) return;
    try {
      Directory(base!).createSync(recursive: true);
      File('${base!}${_sep}runtime.txt').writeAsStringSync(desiredRuntime(engine));
    } catch (_) {}
    notifyListeners();
  }

  /// Hay que reiniciar la app para cambiar de runtime (ya hay uno cargado y es otro).
  bool needsRestart(AiEngine engine) {
    final loaded = loadedRuntimeId();
    return loaded != null && loaded != desiredRuntime(engine);
  }
}

typedef _GetEnvLC = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>);

/// Variable de entorno leída del proceso (no la copia de Platform.environment, que no
/// ve lo que el cargador fija después de arrancar).
String? processEnv(String name) {
  if (Platform.isWindows) {
    final k32 = ffi.DynamicLibrary.open('kernel32.dll');
    final f = k32.lookupFunction<ffi.Uint32 Function(ffi.Pointer<Utf16>, ffi.Pointer<Utf16>, ffi.Uint32),
        int Function(ffi.Pointer<Utf16>, ffi.Pointer<Utf16>, int)>('GetEnvironmentVariableW');
    final n = name.toNativeUtf16();
    final buf = calloc<ffi.Uint16>(32768).cast<Utf16>();
    try {
      final len = f(n, buf, 32768);
      return len == 0 ? null : buf.toDartString(length: len);
    } finally {
      calloc.free(n);
      calloc.free(buf);
    }
  }
  final f = ffi.DynamicLibrary.process().lookupFunction<_GetEnvLC, _GetEnvLC>('getenv');
  final n = name.toNativeUtf8();
  try {
    final r = f(n);
    return r == ffi.nullptr ? null : r.toDartString();
  } finally {
    calloc.free(n);
  }
}

/// Runtime ya cargado en este proceso: id del paquete, '' el de serie o null si todavía
/// no se ha usado la IA (lo marca el cargador en la variable HERRERO_ORT_DIR).
String? loadedRuntimeId() {
  if (!(Platform.isWindows || Platform.isLinux)) return null;
  final dir = processEnv('HERRERO_ORT_DIR');
  if (dir == null || dir.isEmpty) return null;
  for (final p in gpuPacks) {
    final d = GpuPackStore.dirFor(p.id) ?? '';
    if (Platform.isWindows ? dir.toLowerCase() == d.toLowerCase() : dir == d) return p.id;
  }
  return '';
}
