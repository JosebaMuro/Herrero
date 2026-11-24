// Utilidades de la TUI sin interfaz: carpetas de la app, descarga de los modelos de
// comprensión y razonamiento, exportación (CSV, DXF, memoria) e informe en texto.
//
// Dart puro: no importa Flutter, para poder compilarse con `dart compile exe`.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../ai/download.dart';
import '../cad/dxf.dart';
import '../cad/sheets.dart';
import '../engine/bom.dart';
import '../engine/model.dart';
import '../engine/understanding.dart';

/// Mismo origen que ModelManager.reasonRelease (la app).
const reasonRelease = 'https://github.com/JosebaMuro/Herrero/releases/download/models-reason-v1';

String get _sep => Platform.pathSeparator;

/// Carpeta de datos de la app de escritorio (path_provider: getApplicationSupportDirectory),
/// para compartir con ella los modelos ya descargados.
String herreroDataDir() {
  final env = Platform.environment;
  if (Platform.isWindows) return '${env['APPDATA'] ?? '.'}\\es.herrero\\herrero';
  if (Platform.isMacOS) return '${env['HOME']}/Library/Application Support/es.herrero.herrero';
  final xdg = env['XDG_DATA_HOME'];
  final base = xdg != null && xdg.startsWith('/') ? xdg : '${env['HOME'] ?? '.'}/.local/share';
  return '$base/es.herrero.herrero';
}

/// Carpeta de los modelos de comprensión y razonamiento.
String reasonModelsDir([String? override]) {
  final o = override ?? Platform.environment['HERRERO_MODELOS'];
  if (o != null && o.isNotEmpty) return o;
  return '${herreroDataDir()}${_sep}models${_sep}reason';
}

/// Modelos de texto que usa la TUI.
class TextModel {
  final String id;
  final String name;
  final String summary;
  final List<String> files;
  const TextModel(this.id, this.name, this.summary, this.files);

  bool installedIn(String dir) => files.every((f) => File('$dir$_sep$f').existsSync());
}

const textModels = [
  TextModel('e5-small', 'Comprensión · multilingual-e5-small',
      'Reconoce la tipología aunque uses tus propias palabras (≈136 MB).',
      ['e5s_model_int8.onnx', 'e5s_tokenizer.json', 'e5s_config.json']),
  TextModel('qwen3-0.6b', 'Razonamiento · Qwen3 0.6B',
      'Lee la petición y rellena la ficha (ubicación, uso, cubierta…) (≈627 MB).',
      ['qwen3_model_int8.onnx', 'qwen3_tokenizer.json', 'qwen3_config.json']),
];

/// Descarga los ficheros de [m] que falten (con SHA-256 del manifiesto publicado).
/// [progress] recibe (bytes hechos, bytes totales).
Future<void> downloadTextModel(TextModel m, String dir, void Function(int, int) progress,
    {bool Function()? cancelled}) async {
  Directory(dir).createSync(recursive: true);
  final r = await http.get(Uri.parse('$reasonRelease/manifest.json')).timeout(const Duration(seconds: 30));
  if (r.statusCode != 200) throw Exception('No se pudo leer el catálogo de modelos (HTTP ${r.statusCode}).');
  await File('$dir${_sep}manifest.json').writeAsBytes(r.bodyBytes);
  final files = (jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>)['files'] as Map<String, dynamic>;
  final infos = <String, Map<String, dynamic>>{};
  for (final f in m.files) {
    final i = files[f];
    if (i is! Map<String, dynamic>) throw Exception('El fichero $f no está en el catálogo.');
    infos[f] = i;
  }
  final total = infos.values.fold<int>(0, (a, i) => a + (i['size'] as int));
  var before = 0;
  for (final f in m.files) {
    final info = infos[f]!;
    final size = info['size'] as int;
    final target = File('$dir$_sep$f');
    if (!(target.existsSync() && target.lengthSync() == size)) {
      await downloadVerified('$reasonRelease/$f', target, size, info['sha256'] as String,
          (got) => progress(before + got, total), cancelled ?? () => false);
    }
    before += size;
    progress(before, total);
  }
}

// ---------------------------------------------------------------------------
// Textos
// ---------------------------------------------------------------------------

String num1(double v, [int d = 1]) => v.toStringAsFixed(d).replaceAll('.', ',');

/// Texto de dimensiones según la tipología (omite las que no aplican).
String dimsText(StructureSpec s) {
  final (l, w, h) = s.type.dimLabels;
  return [
    for (final (k, v) in [(l, s.length), (w, s.width), (h, s.height)])
      if (!k.contains('no aplica') && v > 0) '${k.toLowerCase()} ${num1(v, 2)} m',
  ].join(' · ');
}

/// Campos de la ficha «Lo que he entendido»: (etiqueta, valor, clave de origen).
List<(String, String, String)> fichaRows(Understanding u) {
  final s = u.spec;
  final (l, w, h) = s.type.dimLabels;
  return [
    for (final (k, f, v) in [(l, 'length', s.length), (w, 'width', s.width), (h, 'height', s.height)])
      if (!k.contains('no aplica') && v > 0) (k, '${num1(v, 2)} m', f),
    if (s.type.hasRoof) ('Cubierta', s.roofing, 'roofing'),
    if (s.cladding.isNotEmpty) ('Cerramiento', s.cladding, 'cladding'),
    ('Acero', s.grade.name, 'grade'),
    ('Acabado', s.finish, 'finish'),
    if (s.use.isNotEmpty) ('Uso', s.use, 'use'),
    if (s.liveLoad > 0) ('Sobrecarga', '${num1(s.liveLoad, 1)} kN/m²', 'liveLoad'),
    if (s.levels > 0) ('Niveles', '${s.levels}', 'levels'),
    if (s.variant.isNotEmpty) ('Forma', s.variant, 'variant'),
    ('Nieve / viento', '${num1(s.snow, 2)} / ${num1(s.wind, 2)} kN/m²', 'city'),
  ];
}

String _slug(Design d) {
  final t = d.spec.type.label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9áéíóúñü]+'), '-');
  final dims = [d.spec.length, d.spec.width, d.spec.height].where((v) => v > 0).map((v) => num1(v, 1)).join('x');
  return '${t}_$dims'.replaceAll(RegExp(r'-+$'), '');
}

/// Memoria de cálculo en Markdown (se lee en cualquier editor y se convierte a PDF).
String memoriaMarkdown(Design d) {
  final sb = StringBuffer();
  final s = d.spec;
  sb.writeln('# ${s.type.label} — memoria de predimensionado');
  sb.writeln();
  sb.writeln('> «${d.prompt.trim()}»');
  sb.writeln();
  sb.writeln('**Dimensiones:** ${dimsText(s)}  ');
  sb.writeln('**Acero:** ${s.grade.name} · **Acabado:** ${s.finish}${s.type.hasRoof ? ' · **Cubierta:** ${s.roofing}' : ''}  ');
  final (ratio, unit) = d.steelRatio;
  sb.writeln('**Acero total:** ${num1(d.steelKg, 0)} kg (${num1(ratio, 1)} $unit) · perfiles ${num1(d.profilesKg, 0)} kg · '
      'chapas ${num1(d.platesKg, 0)} kg  ');
  sb.writeln('**Pintura:** ${num1(d.paintM2, 1)} m² · **Soldadura:** ${num1(d.weldMeters, 1)} m '
      '(${num1(d.consumableKg, 1)} kg de consumible) · **η máx.:** ${num1(d.maxUtilization, 2)}');
  sb.writeln();
  void list(String title, List<String> items) {
    if (items.isEmpty) return;
    sb.writeln('## $title');
    sb.writeln();
    for (final i in items) {
      sb.writeln('- $i');
    }
    sb.writeln();
  }

  list('Hipótesis', d.hypotheses);
  sb.writeln('## Comprobaciones (CTE DB-SE-A / EC3)');
  sb.writeln();
  sb.writeln('| Elemento | Comprobación | η | Detalle |');
  sb.writeln('|---|---|---:|---|');
  for (final c in d.checks) {
    sb.writeln('| ${c.element} | ${c.description} | ${num1(c.utilization, 2)}${c.ok ? '' : ' ⚠'} | ${c.detail} |');
  }
  sb.writeln();
  sb.writeln('## Despiece');
  sb.writeln();
  sb.writeln('| Marca | Descripción | Perfil | Long. (mm) | Ud. | Corte | kg total |');
  sb.writeln('|---|---|---|---:|---:|---|---:|');
  for (final p in d.pieces) {
    sb.writeln('| ${p.mark} | ${p.description} | ${p.profile.name} | ${p.lengthMm.toStringAsFixed(0)} | ${p.qty} | '
        '${p.cut} | ${num1(p.totalKg, 1)} |');
  }
  sb.writeln();
  if (d.stock.isNotEmpty) {
    sb.writeln('## Barras comerciales');
    sb.writeln();
    for (final st in d.stock) {
      sb.writeln('- ${st.profile.name}: ${st.bars} barras de ${num1(st.barLength / 1000, 1)} m '
          '(merma ${num1(st.wastePct, 0)} %)');
    }
    sb.writeln();
  }
  if (d.plates.isNotEmpty) {
    sb.writeln('## Chapas');
    sb.writeln();
    sb.writeln('| Marca | Chapa | Medidas (mm) | Ud. | kg total |');
    sb.writeln('|---|---|---|---:|---:|');
    for (final p in d.plates) {
      sb.writeln('| ${p.mark} | ${p.description} | ${p.w.toStringAsFixed(0)}×${p.h.toStringAsFixed(0)}×'
          '${p.t.toStringAsFixed(0)} | ${p.qty} | ${num1(p.totalKg, 1)} |');
    }
    sb.writeln();
  }
  list('Tornillería', [for (final b in d.bolts) '${b.qty} × ${b.description} ${b.spec} — ${b.use}']);
  list('Soldaduras', [
    for (final w in d.welds)
      '${w.joint}: ${w.type}, a = ${w.throat.toStringAsFixed(0)} mm, ${w.count} × ${w.lengthPerJoint.toStringAsFixed(0)} mm '
          '(${num1(w.totalMeters, 1)} m) · ${w.process}'
  ]);
  list('Secuencia de montaje', d.assembly);
  list('Avisos', d.warnings);
  list('Normativa de referencia', [for (final n in d.norms) '${n.code} — ${n.title}']);
  sb.writeln('---');
  sb.writeln();
  sb.writeln('*Predimensionado orientativo generado por Herrero. Debe revisarlo y firmarlo un técnico competente '
      'antes de fabricar o montar.*');
  return sb.toString();
}

/// Exporta despiece (CSV), planos (DXF) y memoria (Markdown) a `[base]/<proyecto>/`.
List<String> exportDesign(Design d, String base) {
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp = '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}';
  final dir = Directory('$base$_sep${_slug(d)}_$stamp')..createSync(recursive: true);
  final out = <String>[];
  void write(String name, List<int> bytes) {
    final f = File('${dir.path}$_sep$name')..writeAsBytesSync(bytes);
    out.add(f.path);
  }

  write('despiece.csv', utf8.encode(bomCsv(d)));
  write('memoria.md', utf8.encode(memoriaMarkdown(d)));
  try {
    write('planos.dxf', sheetsDxf(buildSheets(d)));
  } catch (e) {
    out.add('(planos DXF no generados: $e)');
  }
  return out;
}

/// Carpeta de exportación por defecto: ~/Herrero.
String defaultExportDir() {
  final home = Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'] ?? '.';
  return '$home${_sep}Herrero';
}

/// Informe en texto plano (modo no interactivo: --calcular).
String plainReport(Understanding u, Design d) {
  final sb = StringBuffer();
  sb.writeln('HERRERO · ${d.spec.type.label} (${u.typeSource.label})');
  sb.writeln('«${u.prompt.trim()}»');
  sb.writeln();
  sb.writeln('Lo que he entendido:');
  for (final (k, v, f) in fichaRows(u)) {
    sb.writeln('  ${k.padRight(24)} ${v.padRight(34)} [${(u.sources[f] ?? DataSource.assumed).label}]');
  }
  for (final n in u.notes) {
    sb.writeln('  · $n');
  }
  sb.writeln();
  final (ratio, unit) = d.steelRatio;
  sb.writeln('Acero ${num1(d.steelKg, 0)} kg (${num1(ratio, 1)} $unit) · pintura ${num1(d.paintM2, 1)} m² · '
      'soldadura ${num1(d.weldMeters, 1)} m · η máx. ${num1(d.maxUtilization, 2)}');
  sb.writeln();
  sb.writeln('Comprobaciones:');
  for (final c in d.checks) {
    sb.writeln('  ${c.ok ? 'OK ' : '!! '} η ${num1(c.utilization, 2).padLeft(5)}  ${c.element}: ${c.description}');
  }
  sb.writeln();
  sb.writeln('Despiece:');
  for (final p in d.pieces) {
    sb.writeln('  ${p.mark.padRight(6)} ${p.qty.toString().padLeft(3)} × ${p.profile.name.padRight(14)} '
        '${p.lengthMm.toStringAsFixed(0).padLeft(6)} mm  ${num1(p.totalKg, 1).padLeft(8)} kg  ${p.description}');
  }
  for (final w in d.warnings) {
    sb.writeln('Aviso: $w');
  }
  sb.writeln();
  sb.writeln('Predimensionado orientativo: debe revisarlo y firmarlo un técnico competente.');
  return sb.toString();
}
