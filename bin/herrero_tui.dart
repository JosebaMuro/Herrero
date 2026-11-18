// Herrero en la terminal (TUI). Funciona sin escritorio, en la consola de texto de Linux,
// y usa la gráfica NVIDIA con CUDA para la IA local si está el paquete CUDA.
//
// Compilar:  scripts/build_tui.sh build/linux/x64/release/bundle/herrero-tui
// (junto a la app de Linux, en la carpeta del bundle, para que encuentre lib/).
import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:herrero/ai/comprehension_core.dart';
import 'package:herrero/ai/download.dart';
import 'package:herrero/ai/ort_core.dart';
import 'package:herrero/engine/designer.dart';
import 'package:herrero/engine/understanding.dart';
import 'package:herrero/tui/app.dart';
import 'package:herrero/tui/support.dart';
import 'package:herrero/tui/term.dart';
import 'package:onnxruntime/onnxruntime.dart';

const _help = '''
Herrero · oficina técnica de estructuras metálicas (terminal)

Uso:
  herrero-tui                          abre la TUI interactiva
  herrero-tui --calcular "TEXTO"       calcula y escribe el resultado (sin TUI)
      --sin-ia                         solo reglas, sin modelos de IA
      --exportar [CARPETA]             guarda despiece.csv, planos.dxf y memoria.md
  herrero-tui --gpu                    diagnóstico de la gráfica, CUDA y ONNX Runtime
  herrero-tui --descargar-modelos      descarga los modelos de comprensión y razonamiento
  herrero-tui --descargar-cuda CARPETA descarga los ficheros del paquete CUDA (sin instalar)
  herrero-tui --instalar-cuda [--desde CARPETA]
                                       instala el paquete CUDA (desde CARPETA: sin conexión)

Opciones:
  --motor auto|cuda|cpu                motor de la IA (se recuerda)
  --modelos CARPETA                    carpeta de los modelos (o HERRERO_MODELOS)
  --ascii                              sin caracteres de dibujo (fuentes de consola básicas)
  --ayuda                              esta ayuda
''';

String? _opt(List<String> a, String name) {
  final i = a.indexOf(name);
  if (i < 0 || i + 1 >= a.length || a[i + 1].startsWith('--')) return null;
  return a[i + 1];
}

/// Sale sin pasar por los destructores de las bibliotecas nativas: el proveedor CUDA de
/// ONNX Runtime puede romperse al descargarse (p. ej. si la gráfica no arrancó), y eso
/// mostraría «Violación de segmento» al salir de la TUI.
Future<Never> _exitNow(int code) async {
  await stdout.flush();
  await stderr.flush();
  if (Platform.isLinux || Platform.isMacOS) {
    try {
      ffi.DynamicLibrary.process()
          .lookupFunction<ffi.Void Function(ffi.Int32), void Function(int)>('_exit')(code);
    } catch (_) {}
  }
  exit(code);
}

Future<void> main(List<String> args) async {
  await _main(args);
  await _exitNow(exitCode);
}

Future<void> _main(List<String> args) async {
  if (args.contains('--ayuda') || args.contains('--help') || args.contains('-h')) {
    stdout.write(_help);
    return;
  }
  final modelsDir = reasonModelsDir(_opt(args, '--modelos'));
  final engineArg = _opt(args, '--motor');
  var engine = TuiSettings.loadEngine() ?? AiEngine.auto;
  if (engineArg != null) {
    final e = {'auto': AiEngine.auto, 'cuda': AiEngine.cuda, 'cpu': AiEngine.cpu}[engineArg];
    if (e == null) {
      stderr.writeln('Motor desconocido: $engineArg (auto, cuda o cpu)');
      exitCode = 2;
      return;
    }
    engine = e;
    TuiSettings.saveEngine(engine);
  }
  if (!enginesForPlatform().contains(engine)) engine = AiEngine.auto;

  if (args.contains('--gpu')) {
    exitCode = await _gpu(engine);
    return;
  }
  if (args.contains('--descargar-modelos')) {
    exitCode = await _downloadModels(modelsDir);
    return;
  }
  if (args.contains('--descargar-cuda')) {
    final dir = _opt(args, '--descargar-cuda');
    if (dir == null) {
      stderr.writeln('Falta la carpeta: --descargar-cuda CARPETA');
      exitCode = 2;
      return;
    }
    exitCode = await _downloadCuda(dir);
    return;
  }
  if (args.contains('--instalar-cuda')) {
    exitCode = await _installCuda(_opt(args, '--desde'), engine);
    return;
  }
  final text = _opt(args, '--calcular');
  if (args.contains('--calcular')) {
    if (text == null) {
      stderr.writeln('Falta el texto: --calcular "nave de 20 x 10 m en León"');
      exitCode = 2;
      return;
    }
    exitCode = await _calc(text, modelsDir, engine,
        ai: !args.contains('--sin-ia'),
        export: args.contains('--exportar') ? (_opt(args, '--exportar') ?? defaultExportDir()) : null);
    return;
  }

  if (!stdin.hasTerminal || !stdout.hasTerminal) {
    stderr.writeln('La TUI necesita una terminal. Para usarlo en guiones: herrero-tui --calcular "TEXTO"');
    exitCode = 2;
    return;
  }
  ortLog = (_) {}; // nada de mensajes sueltos sobre la pantalla
  final term = Terminal(ascii: args.contains('--ascii'));
  final app = TuiApp(term, modelsDir: modelsDir, engine: engine);
  try {
    await app.run();
  } catch (e, st) {
    term.stop();
    stderr.writeln('Error: $e\n$st');
    exitCode = 1;
  }
}

Future<int> _gpu(AiEngine engine) async {
  final packs = GpuPackStore();
  await packs.load();
  packs.syncRuntime(engine);
  stdout.writeln('Sistema: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
  stdout.writeln('Gráficas: ${packs.gpus.isEmpty ? '(ninguna detectada)' : packs.gpus.join(' · ')}');
  for (final n in packs.nvidia) {
    stdout.writeln('NVIDIA: $n · controlador ${n.driver}');
  }
  final wk = packs.wake;
  if (wk != null) {
    stdout.writeln('Arranque NVIDIA: ${wk.message} (${wk.time.inMilliseconds} ms)');
    for (final f in wk.fix) {
      stdout.writeln('  arreglo: $f');
    }
  }
  stdout.writeln('Motor elegido: ${engine.label}');
  for (final p in gpuPacks) {
    stdout.writeln('Paquete ${p.name}: ${packs.installed(p.id) ? 'instalado en ${GpuPackStore.dirFor(p.id)}' : 'no instalado'}');
  }
  try {
    OrtEnv.instance.init();
    final pr = ortProviders();
    final rt = loadedRuntimeId();
    stdout.writeln('ONNX Runtime: ${rt == null || rt.isEmpty ? 'el de serie' : 'paquete $rt'} · ${pr.join(', ')}');
    final cuda = pr.contains(OrtEp.cuda.ortName);
    if (Platform.isLinux && wk != null && wk.state != GpuWakeState.notNvidia) {
      if (!cuda) stdout.writeln('CUDA no disponible: instala el paquete con  herrero-tui --instalar-cuda');
      return wk.ok && cuda ? 0 : 1;
    }
  } catch (e) {
    stdout.writeln('ONNX Runtime no se pudo cargar: $e');
    return 1;
  }
  return 0;
}

void Function(int, int) _printer(String label) {
  var last = -1;
  return (done, total) {
    final pc = total <= 0 ? 0 : done * 100 ~/ total;
    if (pc != last && (pc % 5 == 0 || pc == 100)) {
      last = pc;
      stdout.write('\r$label ${pc.toString().padLeft(3)} % de ${(total / (1 << 20)).toStringAsFixed(0)} MB');
    }
  };
}

Future<int> _downloadModels(String dir) async {
  var rc = 0;
  for (final m in textModels) {
    if (m.installedIn(dir)) {
      stdout.writeln('${m.name}: ya instalado');
      continue;
    }
    try {
      await downloadTextModel(m, dir, _printer(m.name));
      stdout.writeln('\n${m.name}: instalado en $dir');
    } catch (e) {
      stdout.writeln('\n${m.name}: ${friendlyDownloadError(e)}');
      rc = 1;
    }
  }
  return rc;
}

GpuPack? get _cudaPack => gpuPacks.where((p) => p.id == 'cuda').firstOrNull;

Future<int> _downloadCuda(String dir) async {
  final p = _cudaPack;
  if (p == null) {
    stderr.writeln('No hay paquete CUDA para este sistema.');
    return 1;
  }
  Directory(dir).createSync(recursive: true);
  for (final f in [...p.files, ...p.vendorFiles]) {
    final target = File('$dir${Platform.pathSeparator}${f.name}');
    if (target.existsSync() && target.lengthSync() == f.size) {
      stdout.writeln('${f.name}: ya descargado');
      continue;
    }
    final pr = _printer(f.name);
    try {
      await downloadVerified(f.url, target, f.size, f.sha256, (got) => pr(got, f.size), () => false);
      stdout.writeln('\n${f.name}: listo');
    } catch (e) {
      stdout.writeln('\n${f.name}: ${friendlyDownloadError(e)}');
      return 1;
    }
  }
  return 0;
}

Future<int> _installCuda(String? from, AiEngine engine) async {
  final p = _cudaPack;
  if (p == null) {
    stderr.writeln('No hay paquete CUDA para este sistema.');
    return 1;
  }
  final packs = GpuPackStore();
  await packs.load();
  if (packs.installed('cuda')) {
    stdout.writeln('El paquete CUDA ya está instalado en ${GpuPackStore.dirFor('cuda')}');
  } else {
    if (from != null) {
      // sin conexión: los ficheros ya descargados van a la carpeta de descargas, donde
      // la instalación los da por buenos y no los vuelve a pedir
      final dl = Directory('${GpuPackStore.base}${Platform.pathSeparator}_descargas')..createSync(recursive: true);
      for (final f in packs.filesFor(p)) {
        final src = File('$from${Platform.pathSeparator}${f.name}');
        if (!src.existsSync() || src.lengthSync() != f.size) {
          stderr.writeln('Falta ${f.name} en $from (o está incompleto).');
          return 1;
        }
        stdout.writeln('Comprobando ${f.name}…');
        if (!await verifySha256(src.path, f.sha256)) {
          stderr.writeln('${f.name} está dañado (SHA-256 incorrecto).');
          return 1;
        }
        src.copySync('${dl.path}${Platform.pathSeparator}${f.name}');
      }
    }
    final done = Completer<void>();
    var last = -1;
    packs.addListener(() {
      final st = packs.status['cuda'];
      if (st == null) return;
      if (st.state == DlState.verifying && last != -2) {
        last = -2;
        stdout.writeln('\nDescomprimiendo…');
      } else if (st.state == DlState.downloading) {
        final pc = (st.progress * 100).floor();
        if (pc != last && pc % 5 == 0) {
          last = pc;
          stdout.write('\rDescargando ${pc.toString().padLeft(3)} %');
        }
      }
    });
    unawaited(packs.install(p).then((_) => done.complete()));
    await done.future;
    final st = packs.status['cuda']!;
    if (st.state != DlState.installed) {
      stderr.writeln('\nNo se pudo instalar: ${st.error}');
      return 1;
    }
    stdout.writeln('\nPaquete CUDA instalado en ${GpuPackStore.dirFor('cuda')}');
  }
  packs.syncRuntime(engine == AiEngine.cpu ? AiEngine.cpu : engine);
  if (engine == AiEngine.cpu) stdout.writeln('Aviso: el motor elegido es «Solo CPU» (cámbialo con --motor auto).');
  return 0;
}

Future<int> _calc(String text, String modelsDir, AiEngine engine, {required bool ai, String? export}) async {
  var u = understand(text);
  if (ai) {
    final c = ComprehensionEngine(modelsDir);
    final packs = GpuPackStore();
    await packs.load();
    packs.syncRuntime(engine);
    final threads = (Platform.numberOfProcessors - 1).clamp(1, 8).toInt();
    try {
      final ranking = c.embedReady
          ? await c.rank(text, threads: threads.clamp(1, 4).toInt(), engine: engine == AiEngine.auto ? AiEngine.cpu : engine)
          : const <Never>[];
      u = understand(text, ranking: ranking);
      if (c.reasonReady()) {
        final r = await c.read(text, u.type, (_) {}, threads: threads, engine: engine).future;
        stderr.writeln('IA: Qwen3 en ${(r.time.inMilliseconds / 1000).toStringAsFixed(1)} s con ${r.engineLabel}');
        u = understand(text, ranking: ranking, llm: parseLlmJson(r.text, llmSeed(u.type)));
      }
    } catch (e) {
      stderr.writeln('IA no disponible ($e); se usan las reglas.');
    }
  }
  final d = designFromSpec(u.spec, text);
  stdout.write(plainReport(u, d));
  if (export != null) {
    for (final p in exportDesign(d, export)) {
      stdout.writeln('Exportado: $p');
    }
  }
  return 0;
}
