// Elección automática del motor de inferencia según el hardware detectado, por tarea,
// con la opción de fijarlo a mano para cada tarea.
//
// La decisión es una función pura (decideEngine) para poder probarla sin el equipo.
import 'dart:io';

import 'accel.dart';
import 'model_manager.dart';

/// Hardware que importa para elegir motor.
class HardwareInfo {
  final String platform; // 'Android', 'Windows', 'iOS', 'linux'…
  final String arch; // 'arm64', 'x64'…
  final int cores;
  final double ramGb;
  final List<String> gpus; // Windows: nombres de las gráficas
  final int androidSdk; // 0 si no es Android
  final String soc; // Android: chip (p. ej. 'SM8550', 'mt6983'); vacío si no se sabe
  const HardwareInfo({
    required this.platform,
    this.arch = '',
    this.cores = 0,
    this.ramGb = 0,
    this.gpus = const [],
    this.androidSdk = 0,
    this.soc = '',
  });

  bool get isAndroid => platform == 'Android';
  bool get isWindows => platform == 'Windows';
  bool get hasNvidiaGpu => hasNvidia(gpus);
  bool get hasIntelGpuOrNpu => hasIntelGpu(gpus);
  bool get hasAmdGpu => gpus.any((g) => g.toUpperCase().contains('AMD') || g.toUpperCase().contains('RADEON'));

  /// NNAPI existe desde Android 8.1 (API 27); en Android 15 (API 35) Google lo da por obsoleto
  /// pero sigue funcionando.
  bool get hasNnapi => isAndroid && androidSdk >= 27;

  /// Fabricante del chip del móvil, si se reconoce.
  String get socVendor {
    final s = soc.toLowerCase();
    if (s.isEmpty) return '';
    if (s.startsWith('sm') || s.startsWith('qcom') || s.contains('snapdragon') || s.startsWith('msm') || s.startsWith('sdm')) {
      return 'Qualcomm Snapdragon';
    }
    if (s.startsWith('mt') || s.contains('mediatek') || s.contains('dimensity')) return 'MediaTek';
    if (s.contains('exynos') || s.startsWith('s5e') || s.startsWith('universal')) return 'Samsung Exynos';
    if (s.contains('tensor') || s.startsWith('gs') || s.startsWith('zuma')) return 'Google Tensor';
    if (s.contains('kirin') || s.startsWith('hi')) return 'HiSilicon Kirin';
    if (s.contains('unisoc') || s.startsWith('ums') || s.startsWith('sc9')) return 'Unisoc';
    return soc;
  }

  String get summary {
    final parts = <String>[platform];
    if (arch.isNotEmpty) parts.add(arch);
    if (isAndroid) {
      if (androidSdk > 0) parts.add('Android API $androidSdk');
      if (socVendor.isNotEmpty) parts.add(socVendor);
    }
    if (gpus.isNotEmpty) parts.add(gpus.join(' + '));
    return parts.join(' · ');
  }

  static HardwareInfo? _cached;

  /// Detecta el hardware (una vez por sesión).
  static Future<HardwareInfo> detect({DeviceProfile? device}) async {
    if (_cached != null) return _cached!;
    final v = Platform.version; // '... on "android_arm64"'
    final m = RegExp(r'on "[a-z]+_([a-z0-9]+)"').firstMatch(v);
    var sdk = 0;
    var soc = '';
    if (Platform.isAndroid) {
      Future<String> prop(String k) async {
        try {
          final r = await Process.run('getprop', [k]);
          return (r.stdout as String).trim();
        } catch (_) {
          return '';
        }
      }

      sdk = int.tryParse(await prop('ro.build.version.sdk')) ?? 0;
      for (final k in ['ro.soc.model', 'ro.board.platform', 'ro.hardware.chipname', 'ro.hardware']) {
        soc = await prop(k);
        if (soc.isNotEmpty) break;
      }
    }
    return _cached = HardwareInfo(
      platform: device?.platform ??
          (Platform.isAndroid ? 'Android' : (Platform.isWindows ? 'Windows' : (Platform.isIOS ? 'iOS' : Platform.operatingSystem))),
      arch: m?.group(1) ?? '',
      cores: Platform.numberOfProcessors,
      ramGb: device?.ramGb ?? 0,
      gpus: Platform.isWindows ? await detectGpus() : const [],
      androidSdk: sdk,
      soc: soc,
    );
  }
}

/// Tareas con modelos pequeños o de tamaño variable: en Automático van en CPU, donde
/// arrancan antes que en la GPU y rinden igual.
bool isLightTask(ModelTask t) => t == ModelTask.understand || t == ModelTask.plans;

/// Motor elegido para una tarea y por qué.
class EngineDecision {
  final ModelTask task;
  /// Lo que se pasa al motor (AiEngine.auto deja que el runtime cargado elija la GPU).
  final AiEngine engine;
  /// Cómo se va a ejecutar, en palabras (p. ej. «GPU · DirectML (NVIDIA RTX 3060)»).
  final String runsOn;
  final String reason;
  final bool manual;
  /// Consejo para ir más rápido (p. ej. instalar el paquete CUDA), o vacío.
  final String tip;
  const EngineDecision(this.task, this.engine, this.runsOn, this.reason, {this.manual = false, this.tip = ''});
}

/// Elige el motor de [task]. [global] es el ajuste general; [override], el fijado para
/// esta tarea (null = como el general). [packs]: paquetes de aceleración instalados.
EngineDecision decideEngine(ModelTask task, HardwareInfo hw,
    {AiEngine global = AiEngine.auto, AiEngine? override, Set<String> packs = const {}}) {
  final chosen = override ?? global;
  final manual = override != null || global != AiEngine.auto;
  final gpuName = hw.gpus.isEmpty ? '' : ' (${hw.gpus.first})';

  String tipFor() {
    if (!hw.isWindows) return '';
    if (hw.hasNvidiaGpu && !packs.contains('cuda')) {
      return 'Tienes una NVIDIA: con el paquete CUDA (más abajo) irá más rápido que con DirectML.';
    }
    if (!hw.hasNvidiaGpu && hw.hasIntelGpuOrNpu && !packs.contains('openvino')) {
      return 'Tienes gráficos Intel: el paquete OpenVINO (más abajo) suele ir más rápido que DirectML.';
    }
    return '';
  }

  if (manual) {
    final why = override != null ? 'Fijado a mano para esta tarea.' : 'Fijado a mano en el motor general.';
    var runs = chosen.label;
    var note = '';
    if (hw.isWindows && (chosen == AiEngine.cuda || chosen == AiEngine.openvino)) {
      final id = chosen == AiEngine.cuda ? 'cuda' : 'openvino';
      if (!packs.contains(id)) note = ' Falta su paquete: mientras tanto va por DirectML o CPU.';
    }
    if (hw.isAndroid && chosen == AiEngine.nnapi && !hw.hasNnapi) {
      note = ' Este Android no tiene NNAPI (necesita 8.1 o superior): irá en CPU.';
    }
    return EngineDecision(task, chosen, runs, '$why$note', manual: true);
  }

  // --- Automático ---
  if (isLightTask(task)) {
    return EngineDecision(task, AiEngine.cpu, 'CPU',
        'Modelo pequeño: en la CPU arranca antes y va igual de rápido que en la GPU.');
  }
  if (hw.isAndroid) {
    if (!hw.hasNnapi) {
      return EngineDecision(task, AiEngine.cpu, 'CPU',
          'Android ${hw.androidSdk > 0 ? '(API ${hw.androidSdk}) ' : ''}sin NNAPI: todo en la CPU.');
    }
    final npu = hw.socVendor.isEmpty ? 'NPU/GPU' : 'NPU/GPU ${hw.socVendor}';
    if (task == ModelTask.photo) {
      return EngineDecision(task, AiEngine.auto, 'CPU + $npu (NNAPI)',
          'El generador int8 va en la CPU (NNAPI no lo admite) y el revelado de la imagen en la $npu.');
    }
    return EngineDecision(task, AiEngine.auto, 'CPU',
        'Modelo int8 dinámico: NNAPI no lo admite y en la CPU es más rápido y estable.');
  }
  if (hw.isWindows) {
    if (packs.contains('cuda') && hw.hasNvidiaGpu) {
      return EngineDecision(task, AiEngine.auto, 'GPU · NVIDIA CUDA$gpuName',
          'Gráfica NVIDIA con el paquete CUDA instalado: lo más rápido.');
    }
    if (packs.contains('openvino') && hw.hasIntelGpuOrNpu) {
      return EngineDecision(task, AiEngine.auto, 'GPU · Intel OpenVINO$gpuName',
          'Gráficos Intel con el paquete OpenVINO instalado.');
    }
    if (hw.gpus.isNotEmpty) {
      final brand = hw.hasNvidiaGpu ? 'NVIDIA' : (hw.hasAmdGpu ? 'AMD' : (hw.hasIntelGpuOrNpu ? 'Intel' : ''));
      return EngineDecision(task, AiEngine.auto, 'GPU · DirectML$gpuName',
          'DirectML viene de serie y vale para cualquier gráfica${brand.isEmpty ? '' : ' $brand'} con DirectX 12. '
              'Si no admite el modelo, ese paso va a la CPU.',
          tip: tipFor());
    }
    return EngineDecision(task, AiEngine.auto, 'DirectML o CPU',
        'No se ha podido leer la gráfica: se prueba DirectML y, si no hay GPU, la CPU.');
  }
  return EngineDecision(task, AiEngine.cpu, 'CPU', 'En ${hw.platform} la app usa la CPU.');
}

/// Motores que se pueden fijar para una tarea concreta en esta plataforma. En Windows
/// solo se puede cargar un runtime por sesión, así que CUDA y OpenVINO se eligen en el
/// motor general.
List<AiEngine> taskEngineChoices() {
  if (Platform.isWindows) return const [AiEngine.directml, AiEngine.cpu];
  if (Platform.isAndroid) return const [AiEngine.nnapi, AiEngine.xnnpack, AiEngine.cpu];
  return const [AiEngine.cpu];
}
