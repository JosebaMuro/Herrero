import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'accel.dart';
import 'download.dart' as dl;
import 'download.dart' show DlState, ModelStatus;
import 'sd_pipeline.dart';

export 'download.dart' show DlState, ModelStatus;

const modelsRelease = 'https://github.com/JosebaMuro/Herrero/releases/download/models-sdturbo-v1';
const ocrRelease = 'https://github.com/JosebaMuro/Herrero/releases/download/models-ocr-v1';
const vlmRelease = 'https://github.com/JosebaMuro/Herrero/releases/download/models-vlm-v1';
const reasonRelease = 'https://github.com/JosebaMuro/Herrero/releases/download/models-reason-v1';

/// Paso de la app que usa un modelo de IA.
enum ModelTask { understand, reason, photo, plans, sketch }

extension ModelTaskLabel on ModelTask {
  String get label {
    switch (this) {
      case ModelTask.understand:
        return 'Comprensión de la petición (embeddings)';
      case ModelTask.reason:
        return 'Lectura con razonamiento (LLM local)';
      case ModelTask.photo:
        return 'Foto realista (IA local)';
      case ModelTask.plans:
        return 'Importar plano (lector OCR local)';
      case ModelTask.sketch:
        return 'Croquis a mano (visión local, VLM)';
    }
  }

  String get description {
    switch (this) {
      case ModelTask.understand:
        return 'Reconoce qué estructura pides aunque la describas con tus palabras («un techado para el coche», '
            '«algo para subir al altillo») comparando el significado con el catálogo. Ligero y rápido.';
      case ModelTask.reason:
        return 'Lee tu petición como un técnico y rellena la ficha (medidas, cubierta, acabado, ubicación, uso). '
            'Solo se aceptan datos que estén en tu texto; lo demás lo deduce la app y lo puedes revisar.';
      case ModelTask.photo:
        return 'Convierte el render 3D de la estructura en una fotografía realista, sin internet.';
      case ModelTask.plans:
        return 'Lee rótulos y cotas de fotos de planos y de PDF escaneados para convertirlos en el prompt.';
      case ModelTask.sketch:
        return 'Mira el croquis o plano como una persona: reconoce el tipo de estructura, pilares, vigas y '
            'cubierta aunque esté dibujado a mano. Se combina con el lector OCR para las cotas.';
    }
  }
}

/// Variante de modelo descargable.
class ModelVariant {
  final String id;
  final ModelTask task;
  final String name;
  final String summary;
  final String textEncoderFile;
  final String unetFile;
  final String vaeEncoderFile;
  final String vaeDecoderFile;
  final bool tinyVae;
  final double minRamGb;
  final double recRamGb;
  final bool pcOnly;
  final String quality; // texto
  final String speed; // texto
  final int approxBytes; // tamaño aproximado antes de leer el catálogo
  final String release; // URL base de la release con los ficheros
  final String subdir; // carpeta local
  final List<String>? fileList;
  final List<(String, String)>? partList;
  const ModelVariant({
    required this.id,
    required this.task,
    required this.name,
    required this.summary,
    this.textEncoderFile = 'sdturbo_text_encoder_int8.onnx',
    required this.unetFile,
    this.vaeEncoderFile = 'sdturbo_vae_encoder.onnx',
    this.vaeDecoderFile = 'sdturbo_vae_decoder.onnx',
    this.tinyVae = false,
    required this.minRamGb,
    required this.recRamGb,
    this.pcOnly = false,
    required this.quality,
    required this.speed,
    required this.approxBytes,
    this.release = modelsRelease,
    this.subdir = 'sdturbo',
    this.fileList,
    this.partList,
  });

  List<String> get files =>
      fileList ?? [textEncoderFile, unetFile, vaeEncoderFile, vaeDecoderFile, 'vocab.json', 'merges.txt'];

  /// Componentes, para mostrar al usuario qué se descarga y para qué paso.
  List<(String, String)> get parts => partList ?? [
    ('Codificador de texto (CLIP int8)', textEncoderFile),
    ('Generador de imagen (UNet)', unetFile),
    (tinyVae ? 'Codificador de imagen (TAESD)' : 'Codificador de imagen (VAE)', vaeEncoderFile),
    (tinyVae ? 'Decodificador de imagen (TAESD)' : 'Decodificador de imagen (VAE)', vaeDecoderFile),
  ];
}

const catalog = <ModelVariant>[
  ModelVariant(
    id: 'sdturbo-lite',
    task: ModelTask.photo,
    name: 'Ligero · Móvil',
    summary:
        'SD-Turbo int8 con autoencoder diminuto (TAESD). Usa mucha menos memoria y revela la '
        'imagen al instante. Ideal para móviles y equipos modestos; algo menos de detalle fino.',
    unetFile: 'sdturbo_unet_int8.onnx',
    vaeEncoderFile: 'taesd_encoder.onnx',
    vaeDecoderFile: 'taesd_decoder.onnx',
    tinyVae: true,
    minRamGb: 3,
    recRamGb: 4,
    quality: 'Buena',
    speed: 'Muy rápida',
    approxBytes: 1250000000,
  ),
  ModelVariant(
    id: 'sdturbo-int8',
    task: ModelTask.photo,
    name: 'Equilibrado',
    summary:
        'SD-Turbo int8 con el autoencoder completo: mejores texturas de acero, hormigón y cielo. '
        'Necesita más memoria al revelar la imagen. Para móviles potentes y PCs sin gráfica dedicada.',
    unetFile: 'sdturbo_unet_int8.onnx',
    minRamGb: 6,
    recRamGb: 8,
    quality: 'Muy buena',
    speed: 'Rápida',
    approxBytes: 1600000000,
  ),
  ModelVariant(
    id: 'ppocr-v4',
    task: ModelTask.plans,
    name: 'Lector de planos · PP-OCRv4',
    summary:
        'Detector y lector de texto ligeros (PaddleOCR, Apache-2.0). Lee rótulos, cotas y perfiles de '
        'fotos de planos y PDF escaneados. Funciona igual en móvil y en PC.',
    unetFile: '',
    minRamGb: 2,
    recRamGb: 3,
    quality: 'Texto impreso: muy buena · croquis a mano: limitada',
    speed: 'Unos segundos por plano',
    approxBytes: 15700000,
    release: ocrRelease,
    subdir: 'ocr',
    fileList: ['ppocrv4_det.onnx', 'ppocrv4_rec.onnx', 'ppocr_keys.txt'],
    partList: [
      ('Detector de texto', 'ppocrv4_det.onnx'),
      ('Lector de caracteres', 'ppocrv4_rec.onnx'),
      ('Diccionario de caracteres', 'ppocr_keys.txt'),
    ],
  ),
  ModelVariant(
    id: 'e5-small',
    task: ModelTask.understand,
    name: 'Comprensión · multilingual-e5-small',
    summary: 'Modelo de embeddings multilingüe (Microsoft, MIT) en int8: convierte tu petición en un vector de '
        'significado y lo compara con ejemplos de cada tipología. Funciona sin internet en cualquier móvil.',
    unetFile: '',
    minRamGb: 1,
    recRamGb: 2,
    quality: 'Reconocimiento de la tipología con palabras propias: muy bueno',
    speed: 'menos de 1 s por petición',
    approxBytes: 136000000,
    release: reasonRelease,
    subdir: 'reason',
    fileList: ['e5s_model_int8.onnx', 'e5s_tokenizer.json', 'e5s_config.json'],
    partList: [
      ('Modelo de embeddings (int8)', 'e5s_model_int8.onnx'),
      ('Tokenizador', 'e5s_tokenizer.json'),
      ('Configuración', 'e5s_config.json'),
    ],
  ),
  ModelVariant(
    id: 'qwen3-0.6b',
    task: ModelTask.reason,
    name: 'Razonamiento · Qwen3 0.6B',
    summary: 'Modelo de lenguaje pequeño (Alibaba Qwen, Apache-2.0) en int8. Lee la petición y rellena la ficha '
        'de la estructura; la app comprueba cada dato contra tu texto antes de usarlo.',
    unetFile: '',
    minRamGb: 3,
    recRamGb: 4,
    quality: 'Lectura de datos sueltos (ubicación, uso, cubierta, acabado): buena',
    speed: '5–30 s por petición',
    approxBytes: 627000000,
    release: reasonRelease,
    subdir: 'reason',
    fileList: ['qwen3_model_int8.onnx', 'qwen3_tokenizer.json', 'qwen3_config.json'],
    partList: [
      ('Modelo de lenguaje (int8)', 'qwen3_model_int8.onnx'),
      ('Tokenizador', 'qwen3_tokenizer.json'),
      ('Configuración', 'qwen3_config.json'),
    ],
  ),
  ModelVariant(
    id: 'smolvlm-256m',
    task: ModelTask.sketch,
    name: 'Visión de croquis · SmolVLM 256M',
    summary:
        'Modelo de visión y lenguaje pequeño (Hugging Face, Apache-2.0) en int8. Describe croquis y '
        'planos complejos para completar el prompt. Funciona sin internet en móvil y en PC.',
    unetFile: '',
    minRamGb: 3,
    recRamGb: 4,
    quality: 'Tipo de estructura y elementos: buena · cotas: mejor con el OCR',
    speed: '10–40 s por croquis',
    approxBytes: 262000000,
    release: vlmRelease,
    subdir: 'vlm',
    fileList: [
      'smolvlm_vision_int8.onnx',
      'smolvlm_embed_int8.onnx',
      'smolvlm_decoder_int8.onnx',
      'smolvlm_tokenizer.json',
      'smolvlm_config.json',
    ],
    partList: [
      ('Codificador de imagen (SigLIP int8)', 'smolvlm_vision_int8.onnx'),
      ('Embeddings de texto', 'smolvlm_embed_int8.onnx'),
      ('Modelo de lenguaje (int8)', 'smolvlm_decoder_int8.onnx'),
      ('Tokenizador', 'smolvlm_tokenizer.json'),
      ('Configuración', 'smolvlm_config.json'),
    ],
  ),
  ModelVariant(
    id: 'smolvlm-500m',
    task: ModelTask.sketch,
    name: 'Visión de croquis · SmolVLM 500M (calidad)',
    summary:
        'Hermano mayor del anterior: entiende mejor los croquis complicados y las cotas. Recomendado en PC '
        'y en móviles con 8 GB de RAM o más.',
    unetFile: '',
    minRamGb: 4,
    recRamGb: 8,
    quality: 'Tipo de estructura y elementos: muy buena · cotas: buena',
    speed: '20–60 s por croquis',
    approxBytes: 515000000,
    release: vlmRelease,
    subdir: 'vlm',
    fileList: [
      'smolvlm500_vision_int8.onnx',
      'smolvlm500_embed_int8.onnx',
      'smolvlm500_decoder_int8.onnx',
      'smolvlm500_tokenizer.json',
      'smolvlm500_config.json',
    ],
    partList: [
      ('Codificador de imagen (SigLIP int8)', 'smolvlm500_vision_int8.onnx'),
      ('Embeddings de texto', 'smolvlm500_embed_int8.onnx'),
      ('Modelo de lenguaje (int8)', 'smolvlm500_decoder_int8.onnx'),
      ('Tokenizador', 'smolvlm500_tokenizer.json'),
      ('Configuración', 'smolvlm500_config.json'),
    ],
  ),
];

/// Perfil del dispositivo para recomendar el modelo.
class DeviceProfile {
  final String platform;
  final bool isMobile;
  final double ramGb;
  final int cores;
  final double freeDiskGb;
  DeviceProfile(this.platform, this.isMobile, this.ramGb, this.cores, this.freeDiskGb);

  static Future<DeviceProfile> detect() async {
    final cores = Platform.numberOfProcessors;
    double ram = 0;
    try {
      if (Platform.isAndroid || Platform.isLinux) {
        final mi = await File('/proc/meminfo').readAsLines();
        final l = mi.firstWhere((e) => e.startsWith('MemTotal'));
        ram = double.parse(RegExp(r'(\d+)').firstMatch(l)![1]!) / 1024 / 1024;
      } else if (Platform.isWindows) {
        final r = await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          '(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory',
        ]);
        ram = double.parse((r.stdout as String).trim()) / 1024 / 1024 / 1024;
      } else if (Platform.isIOS || Platform.isMacOS) {
        ram = _appleMemoryGb();
      }
    } catch (_) {}
    double free = -1;
    try {
      if (Platform.isWindows) {
        final dir = await getApplicationSupportDirectory();
        final drive = dir.path.substring(0, 1);
        final r = await Process.run('powershell', ['-NoProfile', '-Command', '(Get-PSDrive $drive).Free']);
        free = double.parse((r.stdout as String).trim()) / 1024 / 1024 / 1024;
      } else if (Platform.isAndroid || Platform.isLinux) {
        final dir = await getApplicationSupportDirectory();
        final r = await Process.run('df', ['-k', dir.path]);
        final parts = (r.stdout as String).trim().split('\n').last.split(RegExp(r'\s+'));
        free = double.parse(parts[3]) / 1024 / 1024;
      }
    } catch (_) {}
    final mobile = Platform.isAndroid || Platform.isIOS;
    return DeviceProfile(
      Platform.isAndroid ? 'Android' : (Platform.isWindows ? 'Windows' : (Platform.isLinux ? 'Linux' : (Platform.isIOS ? 'iOS' : Platform.operatingSystem))),
      mobile,
      ram,
      cores,
      free,
    );
  }

  /// Memoria física en iOS / macOS (sysctl hw.memsize).
  static double _appleMemoryGb() {
    final sysctl = ffi.DynamicLibrary.process().lookupFunction<
        ffi.Int32 Function(ffi.Pointer<Utf8>, ffi.Pointer<ffi.Uint64>, ffi.Pointer<ffi.Size>, ffi.Pointer<ffi.Void>, ffi.Size),
        int Function(ffi.Pointer<Utf8>, ffi.Pointer<ffi.Uint64>, ffi.Pointer<ffi.Size>, ffi.Pointer<ffi.Void>, int)>('sysctlbyname');
    final name = 'hw.memsize'.toNativeUtf8();
    final out = calloc<ffi.Uint64>();
    final len = calloc<ffi.Size>()..value = 8;
    try {
      return sysctl(name, out, len, ffi.nullptr, 0) == 0 ? out.value / 1024 / 1024 / 1024 : 0;
    } finally {
      calloc.free(name);
      calloc.free(out);
      calloc.free(len);
    }
  }

  /// Modelo recomendado (el más equilibrado para este equipo).
  ModelVariant recommended(ModelTask task) {
    ModelVariant byId(String id) => catalog.firstWhere((m) => m.id == id);
    if (task == ModelTask.plans) return byId('ppocr-v4');
    if (task == ModelTask.understand) return byId('e5-small');
    if (task == ModelTask.reason) return byId('qwen3-0.6b');
    if (task == ModelTask.sketch) {
      return (!isMobile && (ramGb <= 0 || ramGb >= 6)) || ramGb >= 8 ? byId('smolvlm-500m') : byId('smolvlm-256m');
    }
    final known = ramGb > 0;
    if (isMobile) {
      // En móvil la memoria manda: el VAE completo a 512 px pide más de 2 GB libres.
      return known && ramGb >= 11 ? byId('sdturbo-int8') : byId('sdturbo-lite');
    }
    if (!known) return byId('sdturbo-int8');
    if (ramGb >= 7) return byId('sdturbo-int8');
    return byId('sdturbo-lite');
  }

  /// Por qué se recomienda (texto breve para el usuario).
  String reason(ModelTask task) {
    final r = recommended(task);
    final mem = ramGb > 0 ? '${ramGb.toStringAsFixed(0)} GB de RAM' : 'memoria desconocida';
    return '$platform · $mem · $cores núcleos → ${r.name}';
  }

  /// Resolución recomendada.
  int get recommendedSize => isMobile && (ramGb <= 0 || ramGb < 8) ? 384 : 512;

  /// Motor recomendado.
  AiEngine get recommendedEngine => AiEngine.auto;

  /// Hilos de cálculo recomendados (deja núcleos libres para la interfaz).
  int get recommendedThreads => math.max(1, math.min(isMobile ? 4 : 8, cores - (isMobile ? 2 : 1)));

  String suitability(ModelVariant m) {
    if (m.pcOnly && isMobile) return 'No recomendado en móvil';
    if (ramGb > 0 && ramGb < m.minRamGb) return 'Memoria insuficiente (${m.minRamGb.toStringAsFixed(0)} GB mín.)';
    if (ramGb > 0 && ramGb < m.recRamGb) return 'Funcionará, pero justo de memoria';
    return 'Compatible';
  }

  bool fits(ModelVariant m) => !(m.pcOnly && isMobile) && !(ramGb > 0 && ramGb < m.minRamGb);
}

/// Gestor de descargas de modelos (reanudable, con verificación SHA-256).
class ModelManager extends ChangeNotifier {
  ModelManager._();
  static final ModelManager instance = ModelManager._();

  /// Manifiestos por release (URL base).
  final Map<String, Map<String, dynamic>> manifests = {};
  Map<String, dynamic>? get manifest => manifests[modelsRelease];
  final Map<String, ModelStatus> status = {};
  final Map<String, bool> _cancel = {};
  String? activeId;
  int size = 512;
  AiEngine engine = AiEngine.auto;
  int fidelity = 1; // 0 fiel al render, 1 equilibrada, 2 más realista
  DeviceProfile? device;
  bool _loaded = false;

  Future<Directory> dir([String subdir = 'sdturbo']) async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}models${Platform.pathSeparator}$subdir');
    if (!d.existsSync()) d.createSync(recursive: true);
    if (Platform.isIOS && !_backupExcluded) {
      // en iPhone, los modelos (cientos de MB) fuera de la copia de iCloud
      try {
        await const MethodChannel('herrero/ios').invokeMethod('excludeFromBackup', '${base.path}/models');
        _backupExcluded = true;
      } catch (_) {}
    }
    return d;
  }

  bool _backupExcluded = false;

  static List<(String, String)> get _releases => {for (final m in catalog) m.release: m.subdir}.entries
      .map((e) => (e.key, e.value))
      .toList();

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    device = await DeviceProfile.detect();
    try {
      final sp = await SharedPreferences.getInstance();
      activeId = sp.getString('ai.active');
      size = sp.getInt('ai.size') ?? device!.recommendedSize;
      // 'ai.accel' desde v3.5; antes 'ai.engine' (en PC siempre era CPU: se pasa a Automático)
      final saved = sp.getInt('ai.accel') ?? (Platform.isAndroid ? sp.getInt('ai.engine') : null);
      engine = saved != null && saved >= 0 && saved < AiEngine.values.length
          ? AiEngine.values[saved]
          : device!.recommendedEngine;
      if (!enginesForPlatform().contains(engine)) engine = AiEngine.auto;
      fidelity = (sp.getInt('ai.fidelity') ?? 1).clamp(0, 2);
    } catch (_) {}
    if (Platform.isWindows || Platform.isLinux) {
      await GpuPacks.instance.load();
      GpuPacks.instance.syncRuntime(engine);
    }
    for (final (rel, sub) in _releases) {
      final d = await dir(sub);
      final mf = File('${d.path}${Platform.pathSeparator}manifest.json');
      if (mf.existsSync()) {
        try {
          manifests[rel] = json.decode(await mf.readAsString()) as Map<String, dynamic>;
        } catch (_) {}
      }
    }
    for (final m in catalog) {
      status[m.id] = ModelStatus(await _isInstalled(m) ? DlState.installed : DlState.notInstalled);
    }
    if (activeId == null || status[activeId]?.state != DlState.installed) {
      final inst = _photo.where((m) => status[m.id]!.state == DlState.installed).toList();
      activeId = inst.isEmpty ? null : inst.first.id;
    }
    notifyListeners();
  }

  Iterable<ModelVariant> get _photo => catalog.where((m) => m.task == ModelTask.photo);

  Future<void> savePrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (activeId != null) await sp.setString('ai.active', activeId!);
      await sp.setInt('ai.size', size);
      await sp.setInt('ai.accel', engine.index);
      await sp.setInt('ai.fidelity', fidelity);
    } catch (_) {}
    GpuPacks.instance.syncRuntime(engine);
    notifyListeners();
  }

  Future<bool> _isInstalled(ModelVariant m) async {
    final d = await dir(m.subdir);
    for (final f in m.files) {
      final file = File('${d.path}${Platform.pathSeparator}$f');
      if (!file.existsSync()) return false;
      final exp = _fileInfo(m, f)?['size'];
      if (exp is int && file.lengthSync() != exp) return false;
    }
    return true;
  }

  Map<String, dynamic>? _fileInfo(ModelVariant m, String f) =>
      (manifests[m.release]?['files'] as Map<String, dynamic>?)?[f] as Map<String, dynamic>?;

  /// Tamaño de un fichero de una variante según su manifiesto.
  int fileSize(ModelVariant m, String f) => (_fileInfo(m, f)?['size'] as int?) ?? 0;

  /// Tamaño total de una variante (bytes) según el manifiesto.
  int sizeOf(ModelVariant m) {
    var t = 0;
    for (final f in m.files) {
      final s = _fileInfo(m, f)?['size'];
      if (s is int) t += s;
    }
    return t;
  }

  Future<void> fetchManifest() async {
    Object? lastError;
    for (final (rel, sub) in _releases) {
      try {
        final r = await http.get(Uri.parse('$rel/manifest.json')).timeout(const Duration(seconds: 30));
        if (r.statusCode != 200) {
          throw Exception('No se pudo obtener el catálogo de modelos (HTTP ${r.statusCode}).');
        }
        manifests[rel] = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        final d = await dir(sub);
        await File('${d.path}${Platform.pathSeparator}manifest.json').writeAsBytes(r.bodyBytes);
      } catch (e) {
        lastError = e;
      }
    }
    if (manifests.isEmpty && lastError != null) throw lastError;
    for (final m in catalog) {
      final available = m.files.every((f) => _fileInfo(m, f) != null);
      if (!available) {
        status[m.id] = ModelStatus(DlState.error, error: 'Variante no publicada todavía');
      } else if (status[m.id]?.state != DlState.downloading) {
        status[m.id] = ModelStatus(await _isInstalled(m) ? DlState.installed : DlState.notInstalled);
      }
    }
    notifyListeners();
  }

  void cancel(String id) => _cancel[id] = true;

  Future<void> download(ModelVariant m) async {
    final st = status[m.id] = ModelStatus(DlState.downloading);
    _cancel[m.id] = false;
    notifyListeners();
    try {
      if (manifests[m.release] == null) await fetchManifest();
      final d = await dir(m.subdir);
      st.bytesTotal = sizeOf(m);
      var doneBefore = 0;
      final client = http.Client();
      try {
        for (final f in m.files) {
          final info = _fileInfo(m, f);
          if (info == null) throw Exception('El fichero $f no está en el catálogo.');
          final expSize = info['size'] as int;
          final target = File('${d.path}${Platform.pathSeparator}$f');
          if (target.existsSync() && target.lengthSync() == expSize) {
            doneBefore += expSize;
            st.bytesDone = doneBefore;
            st.progress = st.bytesTotal == 0 ? 0 : doneBefore / st.bytesTotal;
            notifyListeners();
            continue;
          }
          final part = File('${target.path}.part');
          // Si la conexión se corta o se cuelga (datos móviles), se reintenta
          // sola y sigue donde se quedó.
          for (var attempt = 1;; attempt++) {
            var have = part.existsSync() ? part.lengthSync() : 0;
            if (have > expSize) {
              part.deleteSync();
              have = 0;
            }
            if (have >= expSize) break;
            try {
              await _fetchInto(client, '${m.release}/$f', part, have, expSize, (got) {
                st.bytesDone = doneBefore + got;
                st.progress = st.bytesTotal == 0 ? 0 : st.bytesDone / st.bytesTotal;
              }, () => _cancel[m.id] == true);
              break;
            } on _Cancelled {
              rethrow;
            } catch (e) {
              final network = e is SocketException || e is http.ClientException || e is TimeoutException;
              if (!network || attempt >= _maxAttempts) rethrow;
              await Future<void>.delayed(Duration(seconds: 2 * attempt));
              if (_cancel[m.id] == true) throw _Cancelled();
            }
          }
          // verificación
          st.state = DlState.verifying;
          notifyListeners();
          final ok = await _verify(part.path, info['sha256'] as String);
          if (!ok) {
            part.deleteSync();
            throw Exception('El fichero $f está dañado (SHA-256 incorrecto). Vuelve a intentarlo.');
          }
          part.renameSync(target.path);
          st.state = DlState.downloading;
          doneBefore += expSize;
        }
      } finally {
        client.close();
      }
      status[m.id] = ModelStatus(DlState.installed, progress: 1);
      if (m.task == ModelTask.photo) activeId ??= m.id;
      await savePrefs();
    } on _Cancelled {
      status[m.id] = ModelStatus(DlState.notInstalled);
    } catch (e) {
      status[m.id] = ModelStatus(DlState.error, error: friendlyDownloadError(e));
    }
    notifyListeners();
  }

  static const _maxAttempts = 4;

  /// Descarga un fichero suelto con reintentos, reanudación y SHA-256 (paquetes de
  /// aceleración). [onBytes] recibe los bytes acumulados.
  Future<void> fetchVerified(String url, File target, int size, String sha,
          void Function(int got) onBytes, bool Function() cancelled) =>
      dl.downloadVerified(url, target, size, sha, onBytes, cancelled);

  /// Descarga [url] en [part] desde el byte [have] (reanudación con Range).
  Future<void> _fetchInto(http.Client client, String url, File part, int have, int expSize,
      void Function(int got) onBytes, bool Function() cancelled) async {
    final req = http.Request('GET', Uri.parse(url));
    if (have > 0) req.headers['Range'] = 'bytes=$have-';
    final resp = await client.send(req).timeout(const Duration(seconds: 30));
    if (resp.statusCode == 200 && have > 0) {
      have = 0; // el servidor no admite reanudación
    } else if (resp.statusCode != 200 && resp.statusCode != 206) {
      throw Exception('Error HTTP ${resp.statusCode} descargando ${url.split('/').last}');
    }
    final sink = part.openWrite(mode: have > 0 ? FileMode.append : FileMode.write);
    var got = have;
    var lastNotify = DateTime.now();
    try {
      // en datos móviles la conexión puede quedarse colgada sin dar error
      await for (final chunk in resp.stream.timeout(const Duration(seconds: 60))) {
        if (cancelled()) throw _Cancelled();
        sink.add(chunk);
        got += chunk.length;
        onBytes(got);
        if (DateTime.now().difference(lastNotify).inMilliseconds > 250) {
          lastNotify = DateTime.now();
          notifyListeners();
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    if (got < expSize) throw http.ClientException('Conexión cortada en el byte $got de $expSize', Uri.parse(url));
  }

  /// Mensaje claro para el usuario a partir de un error de red o de disco.
  static String friendlyDownloadError(Object e) {
    if (e is SocketException || e is http.ClientException || e is TimeoutException) {
      return 'Sin conexión con el servidor de modelos (GitHub). Comprueba internet y vuelve a '
          'intentarlo: la descarga sigue donde se quedó.';
    }
    if (e is TlsException) {
      return 'No se pudo abrir una conexión segura con GitHub. Comprueba la fecha y hora del dispositivo.';
    }
    if (e is FileSystemException) {
      return 'No se pudo guardar el modelo (${e.osError?.message ?? e.message}). Comprueba el espacio libre.';
    }
    final t = '$e';
    return t.startsWith('Exception: ') ? t.substring('Exception: '.length) : t;
  }

  static Future<bool> _verify(String path, String expected) => Isolate.run(() async {
    final digest = await sha256.bind(File(path).openRead()).first;
    return digest.toString() == expected;
  });

  /// Elimina una variante (los ficheros compartidos se conservan si otra los usa).
  Future<void> remove(ModelVariant m) async {
    final d = await dir(m.subdir);
    final keep = <String>{};
    for (final o in catalog) {
      if (o.id != m.id && o.subdir == m.subdir && status[o.id]?.state == DlState.installed) keep.addAll(o.files);
    }
    for (final f in m.files) {
      if (keep.contains(f)) continue;
      for (final p in [f, '$f.part']) {
        final file = File('${d.path}${Platform.pathSeparator}$p');
        if (file.existsSync()) file.deleteSync();
      }
    }
    status[m.id] = ModelStatus(DlState.notInstalled);
    if (activeId == m.id) {
      final inst = _photo.where((o) => status[o.id]!.state == DlState.installed).toList();
      activeId = inst.isEmpty ? null : inst.first.id;
    }
    await savePrefs();
  }

  ModelVariant? get active => activeId == null ? null : catalog.where((m) => m.id == activeId).firstOrNull;

  double vaeScaleFor(ModelVariant m) => m.tinyVae
      ? (manifest?['taesd_scaling_factor'] as num?)?.toDouble() ?? 1.0
      : (manifest?['vae_scaling_factor'] as num?)?.toDouble() ?? 0.18215;

  /// Prepara la petición de generación con la configuración actual.
  Future<SdRequest> buildRequest({required String prompt, required Uint8List initRgba, int seed = 0}) async {
    final m = active!;
    final d = await dir();
    return SdRequest(
      modelDir: d.path,
      textEncoderFile: m.textEncoderFile,
      unetFile: m.unetFile,
      vaeEncoderFile: m.vaeEncoderFile,
      vaeDecoderFile: m.vaeDecoderFile,
      vaeScale: vaeScaleFor(m),
      prompt: prompt,
      size: size,
      steps: fidelitySteps[fidelity].$1,
      strength: fidelitySteps[fidelity].$2,
      initRgba: initRgba,
      seed: seed,
      threads: device?.recommendedThreads ?? 4,
      engine: engine,
    );
  }

  /// Motor para los modelos pequeños o de tamaño variable (embeddings, OCR): en
  /// Automático van en CPU, donde arrancan antes que en la GPU y rinden igual.
  AiEngine get lightEngine => engine == AiEngine.auto ? AiEngine.cpu : engine;

  bool get ready => active != null && status[active!.id]?.state == DlState.installed;

  /// Lector OCR de planos.
  ModelVariant get ocr => catalog.firstWhere((m) => m.task == ModelTask.plans);
  bool get ocrReady => status[ocr.id]?.state == DlState.installed;
  /// Modelo de visión instalado (el más capaz) o, si no hay, el recomendado.
  ModelVariant get vlm {
    final all = catalog.where((m) => m.task == ModelTask.sketch).toList();
    for (final m in all.reversed) {
      if (status[m.id]?.state == DlState.installed) return m;
    }
    return device?.recommended(ModelTask.sketch) ?? all.first;
  }

  bool get vlmReady => status[vlm.id]?.state == DlState.installed;

  /// Comprensión (embeddings) y razonamiento (LLM) de la petición.
  ModelVariant get embedder => catalog.firstWhere((m) => m.task == ModelTask.understand);
  ModelVariant get reasoner => catalog.firstWhere((m) => m.task == ModelTask.reason);
  bool get embedReady => status[embedder.id]?.state == DlState.installed;
  bool get reasonReady => status[reasoner.id]?.state == DlState.installed;

  /// Prefijo de ficheros del modelo de visión (smolvlm / smolvlm500).
  String get vlmPrefix => vlm.files.first.split('_').first;
}

class _Cancelled implements Exception {}

/// (pasos del planificador, fuerza img2img) → pasos UNet efectivos 1, 1 y 2.
const fidelitySteps = <(int, double)>[(4, 0.25), (2, 0.5), (3, 0.67)];
const fidelityLabels = ['Fiel al render', 'Equilibrada', 'Más realista'];
const fidelityHelp = [
  'Respeta la geometría y los colores del render; solo añade texturas y luz.',
  'Equilibrio entre la estructura calculada y el realismo fotográfico.',
  'Más libertad para el entorno y los materiales (puede alterar detalles).',
]; 

String fmtBytes(int b) {
  if (b <= 0) return '—';
  if (b > 1e9) return '${(b / 1e9).toStringAsFixed(2).replaceAll('.', ',')} GB';
  return '${(b / 1e6).toStringAsFixed(0)} MB';
}
