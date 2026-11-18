// TUI de Herrero: la oficina técnica en una terminal (también en modo texto, sin
// escritorio), con la IA local acelerada por CUDA si hay gráfica NVIDIA.
//
// Pantallas: Petición → Lo que he entendido → Resultado (resumen, despiece,
// comprobaciones, uniones, montaje, normativa) y «IA y GPU» (Ctrl+G).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:onnxruntime/onnxruntime.dart';

import '../ai/comprehension_core.dart';
import '../ai/download.dart';
import '../ai/local_text.dart';
import '../ai/ort_core.dart';
import '../engine/designer.dart';
import '../engine/model.dart';
import '../engine/understanding.dart';
import 'support.dart';
import 'term.dart';

enum Screen { prompt, ficha, result, gpu, help }

const _examples = [
  'nave a dos aguas de 30 x 15 m, 6 m al alero, panel sándwich, en Vitoria',
  'marquesina para 3 coches en Burgos, que no pase de 2,5 m de alto',
  'altillo de 8 x 4 m para oficina con suelo de tramex, galvanizado',
  'escalera de caracol para salvar 3 m, diámetro 1,6 m',
  'barandilla de 12 m de acero inoxidable con cables',
  'cancela corredera de 5 m de hueco y 2 m de alto',
];

const _tabs = ['Resumen', 'Despiece', 'Comprobaciones', 'Uniones', 'Montaje', 'Normativa'];

/// Ajustes de la TUI (~/.config/herrero/tui.json).
class TuiSettings {
  static File get _file {
    final env = Platform.environment;
    final base = Platform.isWindows
        ? '${env['APPDATA'] ?? '.'}\\Herrero'
        : '${(env['XDG_CONFIG_HOME'] ?? '').startsWith('/') ? env['XDG_CONFIG_HOME'] : '${env['HOME'] ?? '.'}/.config'}/herrero';
    return File('$base${Platform.pathSeparator}tui.json');
  }

  static AiEngine? loadEngine() {
    try {
      final j = jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
      final n = j['engine'] as String?;
      return AiEngine.values.where((e) => e.name == n).firstOrNull;
    } catch (_) {
      return null;
    }
  }

  static void saveEngine(AiEngine e) {
    try {
      _file.parent.createSync(recursive: true);
      _file.writeAsStringSync(jsonEncode({'engine': e.name}));
    } catch (_) {}
  }
}

class _Bench {
  final String label;
  final int tokens;
  final Duration time;
  final String ep;
  const _Bench(this.label, this.tokens, this.time, this.ep);
  double get tps => time.inMilliseconds == 0 ? 0 : tokens * 1000 / time.inMilliseconds;
}

class TuiApp {
  TuiApp(this.term, {required this.modelsDir, required this.engine, String? exportDir})
      : exportDir = exportDir ?? defaultExportDir(),
        ai = ComprehensionEngine(modelsDir);

  final Terminal term;
  final String modelsDir;
  final String exportDir;
  final ComprehensionEngine ai;
  final GpuPackStore packs = GpuPackStore();
  AiEngine engine;

  Screen screen = Screen.prompt;
  Screen _back = Screen.prompt;
  final input = TextField();
  int _example = 0;

  // petición y comprensión
  String prompt = '';
  Understanding? u;
  List<(StructureType, double)> ranking = const [];
  Map<String, dynamic>? llm;
  bool embedBusy = false, llmBusy = false;
  String partial = '';
  final List<String> aiInfo = [];
  String? aiError;
  LlmJob? _job;
  int _run = 0; // invalida resultados de peticiones anteriores

  // resultado
  Design? design;
  String? calcError;
  int tab = 0;
  int scroll = 0;
  List<String> exported = const [];

  // IA y GPU
  bool _ortTried = false;
  List<String> providers = const [];
  String? ortError;
  final Map<String, (int, int, String?)> modelDl = {};
  final List<_Bench> bench = [];
  bool benchBusy = false;
  String? benchError;
  String? flash;

  int _spin = 0;
  bool _dirty = false;
  Timer? _ticker;
  StreamSubscription<Key>? _keys;
  final _done = Completer<void>();

  int get threads => math.max(1, math.min(8, Platform.numberOfProcessors - 1));

  /// Motor de los modelos ligeros (e5): como la app, Automático = CPU.
  AiEngine get lightEngine => engine == AiEngine.auto ? AiEngine.cpu : engine;

  bool get busy =>
      embedBusy || llmBusy || benchBusy || modelDl.values.any((v) => v.$3 == null && v.$1 < v.$2) || _packBusy;

  bool get _packBusy => packs.status.values.any((s) => s.state == DlState.downloading || s.state == DlState.verifying);

  Future<void> run() async {
    term.start();
    term.onResize = redraw;
    packs.addListener(redraw);
    _keys = term.keys.listen(_onKey);
    _ticker = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (busy) {
        _spin++;
        redraw();
      }
    });
    redraw();
    unawaited(_init());
    try {
      await _done.future;
    } finally {
      _ticker?.cancel();
      await _keys?.cancel();
      _job?.cancel();
      term.stop();
    }
  }

  void quit() {
    if (!_done.isCompleted) _done.complete();
  }

  Future<void> _init() async {
    await packs.load(); // en Linux despierta la gráfica NVIDIA
    packs.syncRuntime(engine);
    _loadOrt();
    redraw();
  }

  /// Carga ONNX Runtime (con el paquete CUDA si está elegido) para ver sus proveedores.
  void _loadOrt() {
    if (_ortTried) return;
    _ortTried = true;
    try {
      OrtEnv.instance.init();
      providers = ortProviders();
    } catch (e) {
      ortError = '$e';
    }
  }

  // -------------------------------------------------------------------------
  // Teclado
  // -------------------------------------------------------------------------

  void _onKey(Key k) {
    flash = null;
    if (k.isCtrl('c') || k.isCtrl('q')) {
      quit();
      return;
    }
    if (k.isCtrl('g') || k.k == K.f2) {
      _goGpu();
      redraw();
      return;
    }
    if (k.k == K.f1 || (screen != Screen.prompt && k.isChar('?'))) {
      if (screen != Screen.help) _back = screen;
      screen = Screen.help;
      redraw();
      return;
    }
    switch (screen) {
      case Screen.prompt:
        _keyPrompt(k);
      case Screen.ficha:
        _keyFicha(k);
      case Screen.result:
        _keyResult(k);
      case Screen.gpu:
        _keyGpu(k);
      case Screen.help:
        if (k.k == K.esc || k.k == K.enter || k.isChar('q')) screen = _back;
    }
    redraw();
  }

  void _goGpu() {
    if (screen != Screen.gpu) _back = screen == Screen.help ? Screen.prompt : screen;
    screen = Screen.gpu;
    scroll = 0;
  }

  void _keyPrompt(Key k) {
    if (k.k == K.enter) {
      final t = input.text.trim();
      if (t.isEmpty) return;
      input.remember();
      _start(t);
      return;
    }
    if (k.k == K.tab) {
      input.set(_examples[_example % _examples.length]);
      _example++;
      return;
    }
    if (k.k == K.esc) {
      input.set('');
      return;
    }
    input.handle(k);
  }

  void _keyFicha(Key k) {
    if (k.k == K.enter || k.isChar('c')) {
      _calc();
    } else if (k.isChar('s') && llmBusy) {
      _job?.cancel();
    } else if (k.k == K.esc || k.isChar('n')) {
      _job?.cancel();
      _run++;
      embedBusy = llmBusy = false;
      screen = Screen.prompt;
    } else if (k.isChar('g')) {
      _goGpu();
    }
  }

  void _keyResult(Key k) {
    final page = math.max(1, term.rows - 6);
    switch (k.k) {
      case K.left:
      case K.shiftTab:
        tab = (tab - 1 + _tabs.length) % _tabs.length;
        scroll = 0;
      case K.right:
      case K.tab:
        tab = (tab + 1) % _tabs.length;
        scroll = 0;
      case K.up:
        scroll = math.max(0, scroll - 1);
      case K.down:
        scroll++;
      case K.pageUp:
        scroll = math.max(0, scroll - page);
      case K.pageDown:
        scroll += page;
      case K.home:
        scroll = 0;
      case K.esc:
        screen = Screen.ficha;
      case K.char:
        final n = int.tryParse(k.ch);
        if (n != null && n >= 1 && n <= _tabs.length) {
          tab = n - 1;
          scroll = 0;
        } else if (k.ch == 'e') {
          _export();
        } else if (k.ch == 'n') {
          input.set('');
          screen = Screen.prompt;
        } else if (k.ch == 'g') {
          _goGpu();
        } else if (k.ch == 'q') {
          quit();
        }
      default:
        break;
    }
  }

  void _keyGpu(Key k) {
    final engines = enginesForPlatform();
    switch (k.k) {
      case K.left:
      case K.right:
        final i = engines.indexOf(engine);
        final n = (i + (k.k == K.left ? -1 : 1) + engines.length) % engines.length;
        engine = engines[n];
        TuiSettings.saveEngine(engine);
        packs.syncRuntime(engine);
      case K.up:
        scroll = math.max(0, scroll - 1);
      case K.down:
        scroll++;
      case K.esc:
        screen = _back;
        scroll = 0;
      case K.char:
        switch (k.ch) {
          case 'm':
            _downloadModels();
          case 'p':
            _installCuda();
          case 'b':
            _benchmark();
          case 'q':
            screen = _back;
        }
      default:
        break;
    }
  }

  // -------------------------------------------------------------------------
  // Acciones
  // -------------------------------------------------------------------------

  void _start(String text) {
    _job?.cancel();
    final run = ++_run;
    prompt = text;
    ranking = const [];
    llm = null;
    partial = '';
    aiInfo.clear();
    aiError = null;
    design = null;
    calcError = null;
    exported = const [];
    u = understand(prompt);
    screen = Screen.ficha;
    unawaited(_aiPass(run));
  }

  Future<void> _aiPass(int run) async {
    await packs.load();
    _loadOrt();
    if (run != _run) return;
    if (ai.embedReady) {
      embedBusy = true;
      redraw();
      final sw = Stopwatch()..start();
      try {
        ranking = await ai.rank(prompt, threads: math.min(threads, 4), engine: lightEngine);
        if (run != _run) return;
        aiInfo.add('Tipología con e5-small en ${num1(sw.elapsedMilliseconds / 1000, 1)} s (${lightEngine.label}).');
      } catch (e) {
        aiError = 'Comprensión: $e';
      }
      embedBusy = false;
      _recompute();
    }
    if (run != _run) return;
    if (ai.reasonReady()) {
      final type = u!.type;
      llmBusy = true;
      redraw();
      try {
        _job = ai.read(prompt, type, (p) {
          if (run != _run) return;
          partial = p;
          redraw();
        }, threads: threads, engine: engine);
        final r = await _job!.future;
        if (run != _run) return;
        llm = parseLlmJson(r.text, llmSeed(type));
        final secs = r.time.inMilliseconds / 1000;
        aiInfo.add('Ficha con Qwen3 en ${num1(secs, 1)} s con ${r.engineLabel} '
            '(${r.ids.length} tokens, ${num1(secs == 0 ? 0 : r.ids.length / secs, 1)} tok/s).');
      } catch (e) {
        if (!'$e'.contains('Cancelado')) aiError = 'Razonamiento: $e';
      }
      _job = null;
      llmBusy = false;
      _recompute();
    }
  }

  void _recompute() {
    u = understand(prompt, ranking: ranking, llm: llm);
    redraw();
  }

  void _calc() {
    if (u == null) return;
    try {
      design = designFromSpec(u!.spec, prompt);
      calcError = null;
      tab = 0;
      scroll = 0;
      exported = const [];
      screen = Screen.result;
    } catch (e) {
      calcError = 'No se pudo calcular: $e';
    }
  }

  void _export() {
    final d = design;
    if (d == null) return;
    try {
      exported = exportDesign(d, exportDir);
      flash = 'Exportado en ${File(exported.first).parent.path}';
    } catch (e) {
      flash = 'No se pudo exportar: $e';
    }
  }

  void _downloadModels() {
    for (final m in textModels) {
      if (m.installedIn(modelsDir)) continue;
      final cur = modelDl[m.id];
      if (cur != null && cur.$3 == null && cur.$1 < cur.$2) continue;
      modelDl[m.id] = (0, 1, null);
      unawaited(() async {
        try {
          await downloadTextModel(m, modelsDir, (done, total) {
            modelDl[m.id] = (done, total, null);
          });
          modelDl[m.id] = (1, 1, null);
        } catch (e) {
          modelDl[m.id] = (0, 1, friendlyDownloadError(e));
        }
        redraw();
      }());
    }
    if (modelDl.isEmpty) flash = 'Los modelos ya están instalados.';
  }

  void _installCuda() {
    final p = gpuPacks.where((p) => p.id == 'cuda').firstOrNull;
    if (p == null) {
      flash = 'No hay paquete CUDA para este sistema.';
      return;
    }
    if (packs.installed('cuda')) {
      flash = 'El paquete CUDA ya está instalado.';
      return;
    }
    if (_packBusy) return;
    unawaited(packs.install(p).then((_) {
      final st = packs.status['cuda'];
      if (st?.state == DlState.installed) {
        if (engine != AiEngine.auto) engine = AiEngine.cuda;
        TuiSettings.saveEngine(engine);
        packs.syncRuntime(engine);
        flash = 'Paquete CUDA instalado. Sal (Ctrl+C) y vuelve a abrir Herrero para usarlo.';
      }
      redraw();
    }));
  }

  void _benchmark() {
    if (benchBusy) return;
    if (!ai.reasonReady()) {
      benchError = 'Falta el modelo Qwen3: descárgalo con «m».';
      return;
    }
    benchBusy = true;
    benchError = null;
    bench.clear();
    unawaited(() async {
      final engines = <AiEngine>[
        if (providers.contains(OrtEp.cuda.ortName)) AiEngine.cuda,
        if (providers.contains(OrtEp.directml.ortName)) AiEngine.directml,
        AiEngine.cpu,
      ];
      const p = 'nave a dos aguas de 30 x 15 m, 6 m al alero, panel sándwich, en Vitoria';
      for (final e in engines) {
        try {
          // la primera pasada calienta (carga del modelo y de cuDNN); se mide la segunda
          for (var i = 0; i < 2; i++) {
            final job = ai.read(p, StructureType.nave, (_) {}, threads: threads, engine: e);
            final r = await job.future;
            if (i == 1) bench.add(_Bench(e.label, r.ids.length, r.time, r.engineLabel));
          }
        } catch (err) {
          benchError = '${e.label}: $err';
        }
        redraw();
      }
      benchBusy = false;
      redraw();
    }());
  }

  // -------------------------------------------------------------------------
  // Dibujo
  // -------------------------------------------------------------------------

  void redraw() {
    if (_dirty) return;
    _dirty = true;
    scheduleMicrotask(() {
      _dirty = false;
      _paint();
    });
  }

  String get _spinner {
    const f = ['|', '/', '-', '\\'];
    return f[_spin % f.length];
  }

  St _srcStyle(DataSource? s) => switch (s ?? DataSource.assumed) {
        DataSource.text => St.green,
        DataSource.deduced => St.cyan,
        DataSource.ai => St.magenta,
        DataSource.user => St.yellow,
        DataSource.assumed => St.dim,
      };

  String _gpuBadge() {
    final nv = packs.nvidia.isNotEmpty ? packs.nvidia.first.toString() : null;
    final cuda = providers.contains(OrtEp.cuda.ortName);
    final dml = providers.contains(OrtEp.directml.ortName);
    if (nv != null && cuda) return '$nv · CUDA';
    if (nv != null) return '$nv · ${dml ? 'DirectML' : 'CPU'}';
    if (dml) return 'GPU · DirectML';
    return providers.isEmpty ? 'IA: ${g('…', '...')}' : 'CPU';
  }

  void _paint() {
    final w = term.cols, h = term.rows;
    final lines = <Line>[];
    // cabecera
    final title = ' HERRERO · oficina técnica de estructuras metálicas ';
    final badge = ' ${_gpuBadge()} ';
    final gap = math.max(1, w - textWidth(title) - textWidth(badge));
    lines.add(Line([Seg(title, St.header), Seg(' ' * gap, St.header), Seg(badge, St.header)]));
    // migas
    final crumbs = <(String, bool)>[
      ('Petición', screen == Screen.prompt),
      ('Lo que he entendido', screen == Screen.ficha),
      ('Resultado', screen == Screen.result),
      ('IA y GPU', screen == Screen.gpu),
    ];
    final cl = Line();
    for (final (t, on) in crumbs) {
      cl.add(' $t ', on ? St.selected : St.dim);
      cl.add(' ');
    }
    lines.add(cl);
    lines.add(Line.of(term.hLine * w, St.dim));

    final bodyH = h - lines.length - 2;
    (int, int)? cursor;
    List<Line> body;
    switch (screen) {
      case Screen.prompt:
        final (b, c) = _bodyPrompt(w);
        body = b;
        if (c != null) cursor = (c.$1 + lines.length, c.$2);
      case Screen.ficha:
        body = _bodyFicha(w);
      case Screen.result:
        body = _bodyResult(w, bodyH);
      case Screen.gpu:
        body = _bodyGpu(w);
      case Screen.help:
        body = _bodyHelp(w);
    }
    // desplazamiento (resultado y GPU)
    if (screen == Screen.gpu && body.length > bodyH) {
      scroll = math.min(scroll, body.length - bodyH);
      body = body.sublist(scroll);
    }
    for (var i = 0; i < bodyH; i++) {
      lines.add(i < body.length ? body[i] : Line());
    }
    lines.add(Line.of(term.hLine * w, St.dim));
    final foot = flash ?? _hints();
    lines.add(Line.of(fit(' $foot', w), flash != null ? St.boldYellow : St.bar));
    term.draw(lines, cursor: cursor);
  }

  String _hints() {
    final lr = g('←→', '<->'), ud = g('↑↓', 'arriba/abajo'), sep = g(' · ', ' | ');
    return switch (screen) {
      Screen.prompt => ['Enter calcular', 'Tab ejemplo', '$ud historial', 'Ctrl+G IA y GPU', 'F1 ayuda', 'Ctrl+C salir'],
      Screen.ficha => ['Enter calcular', 's saltar IA', 'Esc nueva petición', 'g IA y GPU', '? ayuda'],
      Screen.result => ['$lr o 1-6 pestañas', '$ud RePág AvPág', 'e exportar', 'n nueva', 'Esc ficha', 'g GPU'],
      Screen.gpu => ['$lr motor', 'm modelos', 'p paquete CUDA', 'b prueba de velocidad', '$ud desplazar', 'Esc volver'],
      Screen.help => ['Esc volver'],
    }.join(sep);
  }

  (List<Line>, (int, int)?) _bodyPrompt(int w) {
    final out = <Line>[
      Line(),
      Line.of(' Describe la estructura como se la contarías a un calderero:', St.bold),
      Line(),
    ];
    final fieldW = math.max(10, w - 6);
    final (vis, cur) = input.view(fieldW);
    out.add(Line([Seg(' ${term.arrow} ', St.boldYellow), Seg(fit(vis, fieldW), St.inverse)]));
    final cursorRow = out.length - 1;
    out.add(Line());
    out.add(Line.of(' Ejemplos (Tab los va poniendo):', St.dim));
    for (final e in _examples) {
      out.add(Line.of('   ${term.bullet} $e', St.dim));
    }
    out.add(Line());
    out.add(Line.of(' Tipos: naves, marquesinas, altillos, escaleras, pasarelas, barandillas, cerchas, torres,', St.dim));
    out.add(Line.of(' estanterías, cancelas, vallas, rejas, pórticos y postes.', St.dim));
    out.add(Line());
    final models = textModels.where((m) => m.installedIn(modelsDir)).length;
    out.add(Line.of(
        models == textModels.length
            ? ' IA local lista (comprensión y razonamiento) · motor: ${engine.label}'
            : ' IA local: faltan modelos (Ctrl+G y «m» para descargarlos); sin ellos se usan las reglas.',
        models == textModels.length ? St.green : St.yellow));
    final wk = packs.wake;
    if (wk != null && wk.state != GpuWakeState.notNvidia && !wk.ok) {
      out.add(Line.of(' ${wk.message}', St.yellow));
    }
    out.add(Line());
    out.add(Line.of(' Predimensionado orientativo: debe revisarlo y firmarlo un técnico competente.', St.dim));
    return (out, (cursorRow, 3 + cur));
  }

  List<Line> _bodyFicha(int w) {
    final out = <Line>[];
    final uu = u;
    if (uu == null) return out;
    for (final l in wrap('«$prompt»', w - 2)) {
      out.add(Line.of(' $l', St.dim));
    }
    out.add(Line());
    if (embedBusy) out.add(Line.of(' $_spinner Comprendiendo la petición con IA local (e5, ${lightEngine.label})${g('…', '...')}', St.cyan));
    if (llmBusy) {
      out.add(Line.of(' $_spinner Razonando con Qwen3 (${engine.label})${g('…', '...')} puedes calcular ya o saltar con «s».', St.cyan));
      if (partial.isNotEmpty) {
        for (final l in wrap(partial.replaceAll('\n', ' '), w - 6).take(2)) {
          out.add(Line.of('     $l', St.dim));
        }
      }
    }
    for (final i in aiInfo) {
      out.add(Line.of(' ${term.bullet} $i', St.dim));
    }
    if (aiError != null) out.add(Line.of(' ${term.bullet} $aiError', St.red));
    if (embedBusy || llmBusy || aiInfo.isNotEmpty || aiError != null) out.add(Line());

    out.add(Line()
      ..add(' Tipología  ', St.bold)
      ..add(uu.type.label, St.boldWhite)
      ..add('  [${uu.typeSource.label}]', _srcStyle(uu.typeSource)));
    final alt = ranking.where((e) => e.$1 != uu.type).take(2).map((e) => e.$1.label).toList();
    if (alt.isNotEmpty) out.add(Line.of('            también podría ser: ${alt.join(', ')}', St.dim));
    out.add(Line());
    for (final (k, v, f) in fichaRows(uu)) {
      final src = uu.sources[f];
      out.add(Line()
        ..add(' ${fit(k, 26)}', St.none)
        ..add(fit(v, math.max(10, w - 48)), St.bold)
        ..add('  [${(src ?? DataSource.assumed).label}]', _srcStyle(src)));
    }
    if (uu.notes.isNotEmpty) {
      out.add(Line());
      for (final n in uu.notes) {
        final ls = wrap(n, w - 5);
        for (var i = 0; i < ls.length; i++) {
          out.add(Line.of('${i == 0 ? ' ${term.bullet} ' : '   '}${ls[i]}', St.dim));
        }
      }
    }
    out.add(Line());
    out.add(Line()
      ..add(' Origen: ')
      ..add('de tu texto ', St.green)
      ..add('deducido ', St.cyan)
      ..add('leído por la IA ', St.magenta)
      ..add('valor habitual', St.dim));
    if (calcError != null) out.add(Line.of(' $calcError', St.boldRed));
    out.add(Line.of(' Enter: calcular la estructura', St.boldYellow));
    return out;
  }

  Line _bar(double eta, int width) {
    final n = (eta.clamp(0, 1.5) / 1.5 * width).round();
    final st = eta > 1 ? St.red : (eta > 0.8 ? St.yellow : St.green);
    return Line()
      ..add(term.blockFull * n, st)
      ..add(term.blockLight * (width - n), St.dim);
  }

  List<Line> _bodyResult(int w, int h) {
    final d = design;
    if (d == null) return [Line.of(' Sin resultado.')];
    final out = <Line>[];
    final tl = Line()..add(' ');
    for (var i = 0; i < _tabs.length; i++) {
      tl.add(' ${i + 1} ${_tabs[i]} ', i == tab ? St.selected : St.none);
      tl.add(' ');
    }
    out.add(tl);
    out.add(Line());
    final content = switch (tab) {
      0 => _tabSummary(d, w),
      1 => _tabPieces(d, w),
      2 => _tabChecks(d, w),
      3 => _tabJoints(d, w),
      4 => _tabAssembly(d, w),
      _ => _tabNorms(d, w),
    };
    final room = h - out.length;
    if (content.length > room) {
      scroll = math.min(scroll, content.length - room);
      out.addAll(content.sublist(scroll, scroll + room));
    } else {
      scroll = 0;
      out.addAll(content);
    }
    return out;
  }

  List<Line> _tabSummary(Design d, int w) {
    final s = d.spec;
    final (ratio, unit) = d.steelRatio;
    final out = <Line>[
      Line()
        ..add(' ${s.type.label}', St.boldWhite)
        ..add('  ${dimsText(s)}', St.bold),
      Line.of(' ${s.grade.name} · ${s.finish}${s.type.hasRoof ? ' · cubierta ${s.roofing}' : ''}', St.dim),
      Line(),
      Line()
        ..add(' Acero        ', St.dim)
        ..add('${num1(d.steelKg, 0)} kg', St.boldWhite)
        ..add('  (${num1(ratio, 1)} $unit · perfiles ${num1(d.profilesKg, 0)} kg · chapas ${num1(d.platesKg, 0)} kg)'),
      Line()
        ..add(' Pintura      ', St.dim)
        ..add('${num1(d.paintM2, 1)} m²'),
      Line()
        ..add(' Soldadura    ', St.dim)
        ..add('${num1(d.weldMeters, 1)} m · consumible ${num1(d.consumableKg, 1)} kg'),
      Line()
        ..add(' Piezas       ', St.dim)
        ..add('${d.pieces.fold<int>(0, (a, p) => a + p.qty)} perfiles en ${d.pieces.length} marcas · '
            '${d.plates.fold<int>(0, (a, p) => a + p.qty)} chapas'),
      Line()
        ..add(' η máximo     ', St.dim)
        ..add('${num1(d.maxUtilization, 2)}  ', d.maxUtilization > 1 ? St.boldRed : St.boldGreen)
        ..segs.addAll(_bar(d.maxUtilization, 30).segs),
      Line(),
      Line.of(' Hipótesis', St.bold),
    ];
    for (final hyp in d.hypotheses) {
      final ls = wrap(hyp, w - 5);
      for (var i = 0; i < ls.length; i++) {
        out.add(Line.of('${i == 0 ? ' ${term.bullet} ' : '   '}${ls[i]}'));
      }
    }
    if (d.warnings.isNotEmpty) {
      out.add(Line());
      for (final wn in d.warnings) {
        for (final l in wrap('Aviso: $wn', w - 2)) {
          out.add(Line.of(' $l', St.yellow));
        }
      }
    }
    if (exported.isNotEmpty) {
      out.add(Line());
      out.add(Line.of(' Exportado:', St.bold));
      for (final p in exported) {
        out.add(Line.of('   $p', St.green));
      }
    }
    return out;
  }

  List<Line> _tabPieces(Design d, int w) {
    final descW = math.max(8, w - 56);
    final out = <Line>[
      Line.of(' ${fit('Marca', 7)}${fit('Ud.', 5, right: true)}  ${fit('Perfil', 16)}${fit('Long. mm', 9, right: true)}'
          '${fit('kg', 10, right: true)}  ${fit('Descripción', descW)}', St.bold),
    ];
    for (final p in d.pieces) {
      out.add(Line()
        ..add(' ${fit(p.mark, 7)}', St.boldCyan)
        ..add('${fit('${p.qty}', 5, right: true)}  ${fit(p.profile.name, 16)}'
            '${fit(p.lengthMm.toStringAsFixed(0), 9, right: true)}${fit(num1(p.totalKg, 1), 10, right: true)}  ')
        ..add(fit('${p.description}${p.cut == 'Escuadra' ? '' : ' · ${p.cut}'}', descW), St.dim));
    }
    out.add(Line.of(' ${fit('', 37)}${fit('Total', 9, right: true)}${fit(num1(d.profilesKg, 1), 10, right: true)}', St.bold));
    if (d.stock.isNotEmpty) {
      out.add(Line());
      out.add(Line.of(' Barras comerciales', St.bold));
      for (final st in d.stock) {
        out.add(Line.of('   ${fit(st.profile.name, 16)} ${st.bars} × ${num1(st.barLength / 1000, 1)} m'
            ' · merma ${num1(st.wastePct, 0)} %'));
      }
    }
    return out;
  }

  List<Line> _tabChecks(Design d, int w) {
    final out = <Line>[];
    for (final c in d.checks) {
      out.add(Line()
        ..add(' ${c.ok ? 'OK' : '!!'} ', c.ok ? St.boldGreen : St.boldRed)
        ..add('η ${fit(num1(c.utilization, 2), 5, right: true)} ')
        ..segs.addAll(_bar(c.utilization, 16).segs)
        ..add('  ${c.element}', St.bold)
        ..add(': ${c.description}'));
      for (final l in wrap(c.detail, w - 8)) {
        out.add(Line.of('       $l', St.dim));
      }
    }
    return out;
  }

  List<Line> _tabJoints(Design d, int w) {
    final out = <Line>[];
    if (d.plates.isNotEmpty) {
      out.add(Line.of(' Chapas', St.bold));
      for (final p in d.plates) {
        out.add(Line()
          ..add('   ${fit(p.mark, 7)}', St.boldCyan)
          ..add('${fit('${p.qty}', 4, right: true)} × ${fit('${p.w.toStringAsFixed(0)}×${p.h.toStringAsFixed(0)}×${p.t.toStringAsFixed(0)}', 16)}'
              '${fit(num1(p.totalKg, 1), 8, right: true)} kg  ')
          ..add(fit(p.description, math.max(8, w - 48)), St.dim));
      }
      out.add(Line());
    }
    if (d.bolts.isNotEmpty) {
      out.add(Line.of(' Tornillería', St.bold));
      for (final b in d.bolts) {
        out.add(Line.of('   ${fit('${b.qty}', 5, right: true)} × ${b.description} ${b.spec} — ${b.use}'));
      }
      out.add(Line());
    }
    if (d.welds.isNotEmpty) {
      out.add(Line.of(' Soldaduras', St.bold));
      for (final s in d.welds) {
        out.add(Line()
          ..add('   ${s.joint}', St.boldCyan)
          ..add(': ${s.type}, a = ${s.throat.toStringAsFixed(0)} mm, ${s.count} × ${s.lengthPerJoint.toStringAsFixed(0)} mm'
              ' (${num1(s.totalMeters, 1)} m)'));
        for (final l in wrap('${s.process} · ${s.position}${s.notes.isEmpty ? '' : ' · ${s.notes}'}', w - 7)) {
          out.add(Line.of('     $l', St.dim));
        }
      }
    }
    return out;
  }

  List<Line> _tabAssembly(Design d, int w) {
    final out = <Line>[];
    for (var i = 0; i < d.assembly.length; i++) {
      final ls = wrap(d.assembly[i], w - 7);
      for (var j = 0; j < ls.length; j++) {
        out.add(Line()
          ..add(j == 0 ? fit(' ${i + 1}.', 5, right: true) : '     ', St.boldCyan)
          ..add(' ${ls[j]}'));
      }
    }
    return out;
  }

  List<Line> _tabNorms(Design d, int w) {
    final out = <Line>[];
    for (final n in d.norms) {
      out.add(Line()
        ..add(' ${n.code}', St.boldCyan)
        ..add(' — ${n.title}', St.bold));
      for (final l in wrap(n.summary, w - 4)) {
        out.add(Line.of('   $l', St.dim));
      }
    }
    if (out.isEmpty) out.add(Line.of(' Sin normativa específica.', St.dim));
    return out;
  }

  Line _progress(int done, int total, int width) {
    final f = total <= 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    final n = (f * width).round();
    return Line()
      ..add('   ')
      ..add(term.blockFull * n, St.cyan)
      ..add(term.blockLight * (width - n), St.dim)
      ..add(' ${(f * 100).toStringAsFixed(0)} % de ${_mb(total)}');
  }

  String _mb(int b) => b >= 1 << 30 ? '${num1(b / (1 << 30), 2)} GB' : '${num1(b / (1 << 20), 0)} MB';

  List<Line> _bodyGpu(int w) {
    final out = <Line>[Line.of(' Gráficas', St.bold)];
    if (packs.gpus.isEmpty && packs.nvidia.isEmpty) out.add(Line.of('   (detectando${g('…', '...')})', St.dim));
    for (final g in packs.gpus) {
      out.add(Line.of('   ${term.bullet} $g'));
    }
    for (final n in packs.nvidia) {
      out.add(Line.of('   ${term.bullet} $n · controlador ${n.driver}', St.green));
    }
    final wk = packs.wake;
    if (wk != null && wk.state != GpuWakeState.notNvidia) {
      out.add(Line());
      out.add(Line.of(' Arranque de la gráfica NVIDIA', St.bold));
      for (final l in wrap(wk.message, w - 4)) {
        out.add(Line.of('   $l', wk.ok ? St.green : St.yellow));
      }
      if (wk.fix.isNotEmpty) {
        out.add(Line.of('   Para arreglarlo, en otra consola (Ctrl+Alt+F2):', St.dim));
        for (final f in wk.fix) {
          out.add(Line.of('     $f', St.cyan));
        }
      }
    }
    out.add(Line());
    out.add(Line.of(' ONNX Runtime', St.bold));
    final rt = loadedRuntimeId();
    out.add(Line.of(
        '   Cargado: ${rt == null ? 'todavía no' : rt.isEmpty ? 'el de serie' : 'paquete $rt (${GpuPackStore.dirFor(rt)})'}'));
    if (providers.isNotEmpty) out.add(Line.of('   Proveedores: ${providers.join(', ')}', St.dim));
    if (ortError != null) {
      for (final l in wrap('Error: $ortError', w - 4)) {
        out.add(Line.of('   $l', St.red));
      }
    }
    out.add(Line());
    final el = Line()..add(' Motor  ', St.bold);
    for (final e in enginesForPlatform()) {
      el.add(' ${e.label} ', e == engine ? St.selected : St.none);
      el.add(' ');
    }
    out.add(el);
    for (final l in wrap(engine.help, w - 4)) {
      out.add(Line.of('   $l', St.dim));
    }
    if (packs.needsRestart(engine)) {
      out.add(Line.of('   Sal y vuelve a abrir Herrero para cambiar de motor (ya está cargado otro).', St.yellow));
    }
    for (final p in gpuPacks) {
      out.add(Line());
      final st = packs.status[p.id];
      final state = st?.state ?? (packs.installed(p.id) ? DlState.installed : DlState.notInstalled);
      out.add(Line()
        ..add(' Paquete ${p.name}  ', St.bold)
        ..add(switch (state) {
          DlState.installed => 'instalado',
          DlState.downloading => 'descargando${g('…', '...')}',
          DlState.verifying => 'comprobando y descomprimiendo${g('…', '...')}',
          DlState.error => 'error',
          DlState.notInstalled => 'no instalado (${_mb(packs.sizeOf(p))}) · «p» para instalarlo',
        }, state == DlState.installed ? St.green : (state == DlState.error ? St.red : St.yellow)));
      if (state == DlState.downloading && st != null) out.add(_progress(st.bytesDone, st.bytesTotal, 30));
      if (state == DlState.error && st?.error != null) {
        for (final l in wrap(st!.error!, w - 4)) {
          out.add(Line.of('   $l', St.red));
        }
      }
    }
    out.add(Line());
    out.add(Line.of(' Modelos de IA  ($modelsDir)', St.bold));
    for (final m in textModels) {
      final dl = modelDl[m.id];
      final ok = m.installedIn(modelsDir);
      out.add(Line()
        ..add('   ${ok ? 'OK' : '--'} ', ok ? St.boldGreen : St.yellow)
        ..add(m.name)
        ..add('  ${m.summary}', St.dim));
      if (!ok && dl != null) {
        if (dl.$3 != null) {
          out.add(Line.of('      ${dl.$3}', St.red));
        } else {
          out.add(_progress(dl.$1, dl.$2, 30));
        }
      }
    }
    if (!textModels.every((m) => m.installedIn(modelsDir))) {
      out.add(Line.of('   «m» para descargar los que faltan (de GitHub, con SHA-256).', St.dim));
    }
    out.add(Line());
    out.add(Line()
      ..add(' Prueba de velocidad (Qwen3)', St.bold)
      ..add(benchBusy ? '  $_spinner midiendo${g('…', '...')}' : '  «b» para medir', St.dim));
    for (final b in bench) {
      out.add(Line()
        ..add('   ${fit(b.label, 18)}', St.bold)
        ..add('${fit(num1(b.tps, 1), 7, right: true)} tok/s', St.boldGreen)
        ..add('  ${b.tokens} tokens en ${num1(b.time.inMilliseconds / 1000, 2)} s · ejecutado con ${b.ep}', St.dim));
    }
    if (bench.length > 1 && bench.last.tps > 0) {
      out.add(Line.of('   ${num1(bench.first.tps / bench.last.tps, 1)}× más rápido que la CPU', St.boldCyan));
    }
    if (benchError != null) out.add(Line.of('   $benchError', St.red));
    return out;
  }

  List<Line> _bodyHelp(int w) {
    final t = <String>[
      'Herrero en la terminal',
      '',
      'Escribe la estructura en lenguaje natural («nave de 20 x 10 m en León»). Herrero',
      'la entiende (reglas + IA local), te enseña la ficha con el origen de cada dato y',
      'calcula el predimensionado según CTE DB-SE-A / Eurocódigo 3.',
      '',
      'Teclas',
      '  Ctrl+G / F2   IA y GPU: motor (CUDA o CPU), modelos, paquete CUDA, prueba',
      '  F1 / ?        esta ayuda',
      '  Ctrl+C        salir',
      '  En el resultado: ${g('←→', '<->')} o 1-6 pestañas, ${g('↑↓', 'arriba/abajo')}, RePág, AvPág; «e» exporta a $exportDir',
      '  (despiece.csv, planos.dxf y memoria.md).',
      '',
      'Sin escritorio (modo texto) la IA usa la gráfica NVIDIA entera: Herrero la',
      'despierta al arrancar. Sin modelos de IA funciona igual, solo con las reglas.',
      '',
      'Desde la línea de órdenes: herrero-tui --ayuda',
    ];
    return [for (final l in t) Line.of(' $l', l == t.first || l == 'Teclas' ? St.bold : St.none)];
  }
}
