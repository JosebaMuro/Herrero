import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sd_pipeline.dart';

const modelsRelease = 'https://github.com/JosebaMuro/Herrero/releases/download/models-sdturbo-v1';

/// Paso de la app que usa un modelo de IA.
enum ModelTask { photo }

extension ModelTaskLabel on ModelTask {
  String get label {
    switch (this) {
      case ModelTask.photo:
        return 'Foto realista (IA local)';
    }
  }

  String get description {
    switch (this) {
      case ModelTask.photo:
        return 'Convierte el render 3D de la estructura en una fotografía realista, sin internet.';
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
  });

  List<String> get files => [textEncoderFile, unetFile, vaeEncoderFile, vaeDecoderFile, 'vocab.json', 'merges.txt'];

  /// Componentes, para mostrar al usuario qué se descarga y para qué paso.
  List<(String, String)> get parts => [
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
      Platform.isAndroid ? 'Android' : (Platform.isWindows ? 'Windows' : Platform.operatingSystem),
      mobile,
      ram,
      cores,
      free,
    );
  }

  /// Modelo recomendado (el más equilibrado para este equipo).
  ModelVariant recommended(ModelTask task) {
    ModelVariant byId(String id) => catalog.firstWhere((m) => m.id == id);
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
  AiEngine get recommendedEngine => Platform.isAndroid ? AiEngine.auto : AiEngine.cpu;

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

enum DlState { notInstalled, downloading, verifying, installed, error }

class ModelStatus {
  DlState state;
  double progress; // 0..1
  int bytesDone;
  int bytesTotal;
  String? error;
  ModelStatus(this.state, {this.progress = 0, this.bytesDone = 0, this.bytesTotal = 0, this.error});
}

/// Gestor de descargas de modelos (reanudable, con verificación SHA-256).
class ModelManager extends ChangeNotifier {
  ModelManager._();
  static final ModelManager instance = ModelManager._();

  Map<String, dynamic>? manifest;
  final Map<String, ModelStatus> status = {};
  final Map<String, bool> _cancel = {};
  String? activeId;
  int size = 512;
  AiEngine engine = AiEngine.auto;
  int fidelity = 1; // 0 fiel al render, 1 equilibrada, 2 más realista
  DeviceProfile? device;
  bool _loaded = false;

  Future<Directory> dir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}models${Platform.pathSeparator}sdturbo');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    device = await DeviceProfile.detect();
    try {
      final sp = await SharedPreferences.getInstance();
      activeId = sp.getString('ai.active');
      size = sp.getInt('ai.size') ?? device!.recommendedSize;
      engine = AiEngine.values[sp.getInt('ai.engine') ?? device!.recommendedEngine.index];
      fidelity = (sp.getInt('ai.fidelity') ?? 1).clamp(0, 2);
    } catch (_) {}
    final d = await dir();
    final mf = File('${d.path}${Platform.pathSeparator}manifest.json');
    if (mf.existsSync()) {
      try {
        manifest = json.decode(await mf.readAsString()) as Map<String, dynamic>;
      } catch (_) {}
    }
    for (final m in catalog) {
      status[m.id] = ModelStatus(await _isInstalled(m) ? DlState.installed : DlState.notInstalled);
    }
    if (activeId == null || status[activeId]?.state != DlState.installed) {
      final inst = catalog.where((m) => status[m.id]!.state == DlState.installed).toList();
      activeId = inst.isEmpty ? null : inst.first.id;
    }
    notifyListeners();
  }

  Future<void> savePrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (activeId != null) await sp.setString('ai.active', activeId!);
      await sp.setInt('ai.size', size);
      await sp.setInt('ai.engine', engine.index);
      await sp.setInt('ai.fidelity', fidelity);
    } catch (_) {}
    notifyListeners();
  }

  Future<bool> _isInstalled(ModelVariant m) async {
    final d = await dir();
    for (final f in m.files) {
      final file = File('${d.path}${Platform.pathSeparator}$f');
      if (!file.existsSync()) return false;
      final exp = _fileInfo(f)?['size'];
      if (exp is int && file.lengthSync() != exp) return false;
    }
    return true;
  }

  Map<String, dynamic>? _fileInfo(String f) =>
      (manifest?['files'] as Map<String, dynamic>?)?[f] as Map<String, dynamic>?;

  /// Tamaño total de una variante (bytes) según el manifiesto.
  int sizeOf(ModelVariant m) {
    var t = 0;
    for (final f in m.files) {
      final s = _fileInfo(f)?['size'];
      if (s is int) t += s;
    }
    return t;
  }

  Future<void> fetchManifest() async {
    final r = await http.get(Uri.parse('$modelsRelease/manifest.json'));
    if (r.statusCode != 200) {
      throw Exception('No se pudo obtener el catálogo de modelos (HTTP ${r.statusCode}).');
    }
    manifest = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final d = await dir();
    await File('${d.path}${Platform.pathSeparator}manifest.json').writeAsBytes(r.bodyBytes);
    for (final m in catalog) {
      final available = m.files.every((f) => _fileInfo(f) != null);
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
      if (manifest == null) await fetchManifest();
      final d = await dir();
      st.bytesTotal = sizeOf(m);
      var doneBefore = 0;
      final client = http.Client();
      try {
        for (final f in m.files) {
          final info = _fileInfo(f);
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
          var have = part.existsSync() ? part.lengthSync() : 0;
          if (have > expSize) {
            part.deleteSync();
            have = 0;
          }
          if (have < expSize) {
            final req = http.Request('GET', Uri.parse('$modelsRelease/$f'));
            if (have > 0) req.headers['Range'] = 'bytes=$have-';
            final resp = await client.send(req);
            if (resp.statusCode == 200 && have > 0) {
              have = 0; // el servidor no admite reanudación
              part.writeAsBytesSync([]);
            } else if (resp.statusCode != 200 && resp.statusCode != 206) {
              throw Exception('Error HTTP ${resp.statusCode} descargando $f');
            }
            final sink = part.openWrite(mode: have > 0 ? FileMode.append : FileMode.write);
            var got = have;
            var lastNotify = DateTime.now();
            try {
              await for (final chunk in resp.stream) {
                if (_cancel[m.id] == true) throw _Cancelled();
                sink.add(chunk);
                got += chunk.length;
                st.bytesDone = doneBefore + got;
                st.progress = st.bytesTotal == 0 ? 0 : st.bytesDone / st.bytesTotal;
                if (DateTime.now().difference(lastNotify).inMilliseconds > 250) {
                  lastNotify = DateTime.now();
                  notifyListeners();
                }
              }
            } finally {
              await sink.flush();
              await sink.close();
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
      activeId ??= m.id;
      await savePrefs();
    } on _Cancelled {
      status[m.id] = ModelStatus(DlState.notInstalled);
    } catch (e) {
      status[m.id] = ModelStatus(DlState.error, error: '$e');
    }
    notifyListeners();
  }

  static Future<bool> _verify(String path, String expected) => Isolate.run(() async {
    final digest = await sha256.bind(File(path).openRead()).first;
    return digest.toString() == expected;
  });

  /// Elimina una variante (los ficheros compartidos se conservan si otra los usa).
  Future<void> remove(ModelVariant m) async {
    final d = await dir();
    final keep = <String>{};
    for (final o in catalog) {
      if (o.id != m.id && status[o.id]?.state == DlState.installed) keep.addAll(o.files);
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
      final inst = catalog.where((o) => status[o.id]!.state == DlState.installed).toList();
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

  bool get ready => active != null && status[active!.id]?.state == DlState.installed;
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
