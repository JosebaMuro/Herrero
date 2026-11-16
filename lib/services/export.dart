import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../engine/bom.dart';
import '../engine/materials.dart';
import '../engine/model.dart';
import '../views/drawing_utils.dart';
import '../views/iso_view.dart';
import '../views/plan_view.dart';
import '../views/render_view.dart';

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

/// Guarda bytes en la carpeta de la app y los comparte / abre.
Future<String> saveAndShare(Uint8List bytes, String filename, {String? text}) async {
  final dir = await outputDir();
  final f = File('${dir.path}${Platform.pathSeparator}$filename');
  await f.writeAsBytes(bytes, flush: true);
  if (Platform.isAndroid || Platform.isIOS) {
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: text));
  } else if (Platform.isWindows) {
    await Process.run('explorer', ['/select,', f.path]);
  }
  return f.path;
}

Future<String> exportCsv(Design d) async {
  final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...bomCsvBytes(d)]);
  return saveAndShare(bytes, '${_slug(d)}_despiece.csv');
}

List<int> bomCsvBytes(Design d) => utf8.encode(bomCsv(d));

/// Genera el PDF completo del proyecto.
Future<Uint8List> buildPdf(Design d,
    {Finish finish = Finish.galvanizado, Uint8List? aiPhoto}) async {
  final reg = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
  final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: reg, bold: bold),
      title: 'Herrero – ${d.spec.type.label}',
      author: 'Herrero · Oficina técnica');

  final render = await renderPng(d, finish, OrbitCamera());
  final iso = await _png(await paintToImage(
      (c, s) => IsoPainter(d).paint(c, s), const Size(1100, 760), 2));
  final sheets = <Uint8List>[];
  for (final v in SheetView.values) {
    sheets.add(await _png(await paintToImage(
        (c, s) => SheetPainter(d, v).paint(c, s), const Size(1188, 840), 2)));
  }

  final s = d.spec;
  const head = pw.TextStyle(fontSize: 8, color: PdfColors.white);
  const cell = pw.TextStyle(fontSize: 7.5);
  pw.Widget table(List<String> headers, List<List<String>> rows) =>
      pw.TableHelper.fromTextArray(
        headers: headers,
        data: rows,
        headerStyle: head.copyWith(font: bold),
        headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF263238)),
        cellStyle: cell,
        cellAlignment: pw.Alignment.centerLeft,
        oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1F4F5)),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      );
  pw.Widget h1(String t) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10, bottom: 5),
      child: pw.Text(t, style: pw.TextStyle(fontSize: 13, font: bold, color: const PdfColor.fromInt(0xFFBF360C))));

  pw.Widget footer(pw.Context ctx) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Herrero · Predimensionado orientativo – validar por técnico competente',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
          pw.Text('${ctx.pageNumber}/${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
        ],
      );

  // Portada
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('HERRERO · OFICINA TÉCNICA',
          style: pw.TextStyle(font: bold, fontSize: 10, color: const PdfColor.fromInt(0xFFBF360C), letterSpacing: 2)),
      pw.SizedBox(height: 4),
      pw.Text(s.type.label, style: pw.TextStyle(font: bold, fontSize: 22)),
      pw.Text('${dimsText(s)} · ${s.grade.name}',
          style: const pw.TextStyle(fontSize: 12)),
      pw.SizedBox(height: 8),
      pw.Container(
        padding: const pw.EdgeInsets.all(6),
        color: const PdfColor.fromInt(0xFFF1F4F5),
        child: pw.Text('Solicitud: "${d.prompt}"', style: const pw.TextStyle(fontSize: 9)),
      ),
      pw.SizedBox(height: 10),
      pw.ClipRRect(
          horizontalRadius: 6,
          verticalRadius: 6,
          child: pw.Image(pw.MemoryImage(aiPhoto ?? render), height: 330, fit: pw.BoxFit.cover)),
      pw.SizedBox(height: 12),
      pw.Row(children: [
        _kpi(metalLabel(s.grade), '${_n(d.steelKg, 0)} kg', bold),
        _kpi('Perfiles', '${_n(d.profilesKg, 0)} kg', bold),
        _kpi('Chapas', '${_n(d.platesKg, 0)} kg', bold),
        _kpi('Ratio', '${_n(d.steelRatio.$1, 1)} ${d.steelRatio.$2}', bold),
      ]),
      pw.SizedBox(height: 6),
      pw.Row(children: [
        _kpi('Soldadura', '${_n(d.weldMeters, 1)} m', bold),
        _kpi('Consumible', '${_n(d.consumableKg, 1)} kg', bold),
        _kpi('Pintura', '${_n(d.paintM2, 0)} m²', bold),
        _kpi('η máx.', '${_n(d.maxUtilization * 100, 0)} %', bold),
      ]),
      pw.Spacer(),
      ...d.warnings.map((w) => pw.Bullet(text: w, style: const pw.TextStyle(fontSize: 8, color: PdfColors.red900))),
      pw.SizedBox(height: 4),
      pw.Text('Generado el ${DateTime.now().toString().substring(0, 16)}',
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
    ]),
  ));

  // Memoria de cálculo
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    footer: footer,
    build: (ctx) => [
      h1('Materiales'),
      pw.Table(
        columnWidths: const {0: pw.FixedColumnWidth(110), 1: pw.FlexColumnWidth()},
        children: [
          for (final (k, v) in materialRows(d))
            pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 1.5), child: pw.Text(k, style: pw.TextStyle(font: bold, fontSize: 8.5))),
              pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 1.5), child: pw.Text(v, style: const pw.TextStyle(fontSize: 8.5))),
            ]),
        ],
      ),
      h1('1. Memoria de cálculo – hipótesis'),
      ...d.hypotheses.map((h) => pw.Bullet(text: h, style: const pw.TextStyle(fontSize: 8.5))),
      h1('2. Comprobaciones (ELU / ELS)'),
      table(['Elemento', 'Comprobación', 'η', 'Estado', 'Detalle'], [
        for (final c in d.checks)
          [
            c.element,
            c.description,
            '${_n(c.utilization * 100, 0)} %',
            c.ok ? 'CUMPLE' : 'NO CUMPLE',
            c.detail
          ]
      ]),
      h1('3. Despiece de perfiles'),
      table(['Marca', 'Elemento', 'Perfil', 'Long. (mm)', 'Ud.', 'Corte', 'kg/ud', 'kg'], [
        for (final p in d.pieces)
          [
            p.mark,
            p.description,
            p.profile.name,
            p.lengthMm.toStringAsFixed(0),
            '${p.qty}',
            p.cut,
            _n(p.unitKg),
            _n(p.totalKg, 0)
          ],
        ['', 'TOTAL PERFILES', '', '', '${d.pieces.fold<int>(0, (a, p) => a + p.qty)}', '', '', _n(d.profilesKg, 0)],
      ]),
      h1('4. Chapas'),
      table(['Marca', 'Descripción', 'Dimensiones (mm)', 'Ud.', 'kg', 'Notas'], [
        for (final p in d.plates)
          [
            p.mark,
            p.description,
            '${p.w.toStringAsFixed(0)} x ${p.h.toStringAsFixed(0)} x ${p.t.toStringAsFixed(0)}',
            '${p.qty}',
            _n(p.totalKg, 0),
            p.notes
          ]
      ]),
      h1('5. Tornillería y anclajes'),
      table(['Elemento', 'Especificación', 'Ud.', 'Uso'], [
        for (final b in d.bolts) [b.description, b.spec, '${b.qty}', b.use]
      ]),
      h1('6. Soldaduras'),
      table(['Unión', 'Tipo', 'a (mm)', 'L/unión (mm)', 'Nº', 'Total (m)', 'Consumible (kg)', 'Proceso / posición'], [
        for (final w in d.welds)
          [
            w.joint,
            w.type,
            w.throat.toStringAsFixed(0),
            w.lengthPerJoint.toStringAsFixed(0),
            '${w.count}',
            _n(w.totalMeters),
            _n(w.consumableKg, 2),
            '${w.process} · ${w.position}'
          ],
        ['TOTAL', '', '', '', '', _n(d.weldMeters), _n(d.consumableKg, 2), ''],
      ]),
      pw.Text(
          'Soldadores cualificados según EN ISO 9606-1. WPS/WPQR según EN ISO 15614-1. Calidad nivel C (EN ISO 5817). Inspección visual 100 % (EN ISO 17637) y END adicionales según EN 1090-2 EXC2.',
          style: const pw.TextStyle(fontSize: 7.5)),
      h1('7. Pedido de material (barras comerciales)'),
      table(['Perfil', 'Barra (m)', 'Nº barras', 'Metros', 'kg aprox.', 'Merma'], [
        for (final st in d.stock)
          [
            st.profile.name,
            _n(st.barLength / 1000, 0),
            '${st.bars}',
            _n(st.bars * st.barLength / 1000, 0),
            _n(st.bars * st.barLength / 1000 * st.profile.kgm, 0),
            '${_n(st.wastePct, 1)} %'
          ]
      ]),
      h1('8. Secuencia de montaje'),
      ...d.assembly.asMap().entries.map((e) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Text('${e.key + 1}. ${e.value}', style: const pw.TextStyle(fontSize: 8.5)))),
    ],
  ));

  // Isométrica
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4.landscape,
    margin: const pw.EdgeInsets.all(20),
    build: (ctx) => pw.Column(children: [
      pw.Text('Vista isométrica con marcas de despiece', style: pw.TextStyle(font: bold, fontSize: 12)),
      pw.Expanded(child: pw.Image(pw.MemoryImage(iso), fit: pw.BoxFit.contain)),
    ]),
  ));
  // Planos
  for (final img in sheets) {
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(12),
      build: (ctx) => pw.Center(child: pw.Image(pw.MemoryImage(img), fit: pw.BoxFit.contain)),
    ));
  }
  return doc.save();
}

pw.Widget _kpi(String label, String value, pw.Font bold) => pw.Expanded(
      child: pw.Container(
        margin: const pw.EdgeInsets.only(right: 6),
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
            borderRadius: pw.BorderRadius.circular(4)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
          pw.Text(value, style: pw.TextStyle(font: bold, fontSize: 12)),
        ]),
      ),
    );

Future<String> exportPdf(Design d, {Finish finish = Finish.galvanizado, Uint8List? aiPhoto}) async {
  final bytes = await buildPdf(d, finish: finish, aiPhoto: aiPhoto);
  return saveAndShare(bytes, '${_slug(d)}.pdf', text: 'Proyecto Herrero');
}

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
