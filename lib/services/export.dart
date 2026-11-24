import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../cad/cad_pdf.dart';
import '../cad/collada.dart';
import '../cad/dxf.dart';
import '../cad/sheets.dart';
import '../engine/bom.dart';
import '../engine/budget.dart';
import '../engine/model.dart';
import '../views/render_view.dart';
import 'sections_pdf.dart';

export 'sections_pdf.dart' show ProjectSection, ProjectSectionInfo, ProjectInfo, buildSectionsPdf;

String _n(double v, [int d = 1]) => v.toStringAsFixed(d).replaceAll('.', ',');

Future<Uint8List> _png(ui.Image img) async {
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  return bd!.buffer.asUint8List();
}

Future<Uint8List> renderPng(Design d, Finish finish, OrbitCamera cam,
    {Size size = const Size(1200, 800), int ss = 2}) async {
  final (_, img) = await renderHq(d, finish, cam, width: size.width.round(), height: size.height.round(), ss: ss);
  final png = await _png(img);
  img.dispose();
  return png;
}

/// Carpeta de trabajo de la app (Documentos/Herrero).
Future<Directory> outputDir() async {
  Directory base;
  try {
    base = Platform.isAndroid
        ? (await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory())
        : await getApplicationDocumentsDirectory();
  } catch (_) {
    base = await getApplicationDocumentsDirectory();
  }
  final dir = Directory('${base.path}${Platform.pathSeparator}Herrero');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir;
}

String _slug(Design d) {
  final s = d.spec;
  final t = s.type.name;
  final ts = DateTime.now();
  return 'Herrero_${t}_${s.length.toStringAsFixed(0)}x${s.width.toStringAsFixed(0)}_${ts.year}${ts.month.toString().padLeft(2, '0')}${ts.day.toString().padLeft(2, '0')}_${ts.hour.toString().padLeft(2, '0')}${ts.minute.toString().padLeft(2, '0')}';
}

/// En iPad, el menú de compartir necesita un punto de anclaje en pantalla.
ui.Rect? _shareOrigin() {
  if (!Platform.isIOS) return null;
  final views = ui.PlatformDispatcher.instance.views;
  if (views.isEmpty) return null;
  final v = views.first;
  final size = v.physicalSize / v.devicePixelRatio;
  return ui.Rect.fromCenter(center: ui.Offset(size.width / 2, size.height / 3), width: 2, height: 2);
}

/// Guarda bytes en la carpeta de la app y los comparte / abre.
Future<String> saveAndShare(Uint8List bytes, String filename, {String? text}) async {
  final dir = await outputDir();
  final f = File('${dir.path}${Platform.pathSeparator}$filename');
  await f.writeAsBytes(bytes, flush: true);
  if (Platform.isAndroid || Platform.isIOS) {
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: text, sharePositionOrigin: _shareOrigin()));
  } else if (Platform.isWindows) {
    await Process.run('explorer', ['/select,', f.path]);
  } else if (Platform.isLinux) {
    await Process.run('xdg-open', [dir.path]).catchError((_) => ProcessResult(0, 1, '', ''));
  }
  return f.path;
}

Future<String> exportCsv(Design d) async {
  final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...bomCsvBytes(d)]);
  return saveAndShare(bytes, '${_slug(d)}_despiece.csv');
}

List<int> bomCsvBytes(Design d) => utf8.encode(bomCsv(d));

/// Genera el PDF completo del proyecto: todos los apartados, cada uno en
/// páginas propias con su cabecera y numeración (ver sections_pdf.dart).
Future<Uint8List> buildPdf(Design d,
        {Finish finish = Finish.galvanizado, Uint8List? aiPhoto, Budget? budget, ProjectInfo info = const ProjectInfo()}) =>
    buildSectionsPdf(
      d,
      [
        for (final s in ProjectSection.values)
          if (s != ProjectSection.presupuesto || budget != null) s
      ],
      finish: finish,
      aiPhoto: aiPhoto,
      budget: budget,
      info: info,
    );

Future<String> exportPdf(Design d,
    {Finish finish = Finish.galvanizado, Uint8List? aiPhoto, Budget? budget, ProjectInfo info = const ProjectInfo()}) async {
  final bytes = await buildPdf(d, finish: finish, aiPhoto: aiPhoto, budget: budget, info: info);
  return saveAndShare(bytes, '${_slug(d)}.pdf', text: 'Proyecto Herrero');
}

/// Solo los planos CAD, en PDF vectorial A3 (color o negro para plotter).
Future<String> exportCadPdf(Design d, {bool monochrome = false}) async {
  final reg = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
  final doc = pw.Document(title: 'Herrero – planos ${d.spec.type.label}', author: 'Herrero · Oficina técnica');
  addCadPages(doc, buildSheets(d), reg, bold, monochrome: monochrome);
  return saveAndShare(await doc.save(), '${_slug(d)}_planos.pdf', text: 'Planos Herrero');
}

/// Planos 2D en DXF (R12): todas las láminas a tamaño real, en mm.
Future<String> exportSheetsDxf(Design d) =>
    saveAndShare(sheetsDxf(buildSheets(d)), '${_slug(d)}_planos.dxf', text: 'Planos Herrero (DXF)');

/// Modelo 3D en DXF (3DFACE por capas, en mm).
Future<String> exportModelDxf(Design d, Finish finish) =>
    saveAndShare(modelDxf(SceneMesh.groups(d, finish)), '${_slug(d)}_modelo3d.dxf', text: 'Modelo 3D Herrero (DXF)');

/// Modelo 3D para SketchUp 2017 (Archivo > Importar > COLLADA .dae).
Future<String> exportSketchUp(Design d, Finish finish) => saveAndShare(
    colladaModel(SceneMesh.groups(d, finish), title: '${d.spec.type.label} ${dimsText(d.spec)}'),
    '${_slug(d)}_sketchup.dae',
    text: 'Modelo 3D Herrero para SketchUp');

Future<String> exportPng(Uint8List png, Design d, String suffix) =>
    saveAndShare(png, '${_slug(d)}_$suffix.png');

/// Texto de dimensiones según la tipología (omite las que no aplican).
String dimsText(StructureSpec s) {
  final (l, w, h) = s.type.dimLabels;
  return [
    for (final (k, v) in [(l, s.length), (w, s.width), (h, s.height)])
      if (!k.contains('no aplica') && v > 0) '${k.toLowerCase()} ${_n(v, 2)} m',
  ].join(' · ');
}

/// Exporta los apartados elegidos. Con [separate], un PDF por apartado
/// (para entregar a cada uno solo lo suyo); si no, todos en un PDF.
Future<List<String>> exportSections(Design d, List<ProjectSection> sections,
    {bool separate = true,
    Finish finish = Finish.galvanizado,
    Uint8List? aiPhoto,
    Budget? budget,
    ProjectInfo info = const ProjectInfo(),
    bool budgetDetail = true}) async {
  final dir = await outputDir();
  final base = _slug(d);
  final files = <String>[];
  Future<void> one(List<ProjectSection> ss, String name) async {
    // un apartado cada vez: se libera la memoria del anterior antes de seguir
    final bytes = await buildSectionsPdf(d, ss,
        finish: finish, aiPhoto: aiPhoto, budget: budget, info: info, budgetDetail: budgetDetail);
    final f = File('${dir.path}${Platform.pathSeparator}$name');
    await f.writeAsBytes(bytes, flush: true);
    files.add(f.path);
  }

  if (separate) {
    for (final s in sections) {
      await one([s], '${base}_${s.fileSuffix}.pdf');
    }
  } else {
    await one(sections, '${base}_apartados.pdf');
  }
  if (Platform.isAndroid || Platform.isIOS) {
    await SharePlus.instance.share(
        ShareParams(files: [for (final f in files) XFile(f)], text: 'Proyecto Herrero', sharePositionOrigin: _shareOrigin()));
  } else if (Platform.isWindows) {
    await Process.run('explorer', ['/select,', files.first]);
  } else if (Platform.isLinux) {
    await Process.run('xdg-open', [dir.path]).catchError((_) => ProcessResult(0, 1, '', ''));
  }
  return files;
}
