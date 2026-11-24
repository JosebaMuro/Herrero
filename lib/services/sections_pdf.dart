import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../cad/cad.dart';
import '../cad/cad_pdf.dart';
import '../cad/sheets.dart';
import '../engine/budget.dart';
import '../engine/cutting.dart';
import '../engine/materials.dart';
import '../engine/model.dart';
import '../engine/normativa.dart';
import '../engine/pricing.dart';
import '../views/drawing_utils.dart';
import '../views/iso_view.dart';
import '../views/render_view.dart';

/// Apartados del proyecto. Cada uno se imprime aislado (empieza en página
/// nueva, lleva su cabecera con el destinatario y su propia numeración) para
/// entregar a cada uno solo su parte: compras, taller, soldadura, montaje…
enum ProjectSection { resumen, calculo, materiales, fabricacion, soldadura, montaje, planos, presupuesto }

extension ProjectSectionInfo on ProjectSection {
  String get label => switch (this) {
        ProjectSection.resumen => 'Resumen del proyecto',
        ProjectSection.calculo => 'Memoria de cálculo',
        ProjectSection.materiales => 'Materiales y pedido',
        ProjectSection.fabricacion => 'Fabricación en taller',
        ProjectSection.soldadura => 'Soldadura',
        ProjectSection.montaje => 'Montaje en obra',
        ProjectSection.planos => 'Planos',
        ProjectSection.presupuesto => 'Presupuesto',
      };

  /// A quién va dirigido.
  String get recipient => switch (this) {
        ProjectSection.resumen => 'Dirección del proyecto / cliente',
        ProjectSection.calculo => 'Oficina técnica / técnico que firma',
        ProjectSection.materiales => 'Compras y almacén',
        ProjectSection.fabricacion => 'Taller: corte, taladro y armado',
        ProjectSection.soldadura => 'Soldadores y control de calidad',
        ProjectSection.montaje => 'Equipo de montaje',
        ProjectSection.planos => 'Oficina técnica, taller y montaje',
        ProjectSection.presupuesto => 'Cliente',
      };

  String get fileSuffix => switch (this) {
        ProjectSection.resumen => '0_resumen',
        ProjectSection.calculo => '1_calculo',
        ProjectSection.materiales => '2_materiales',
        ProjectSection.fabricacion => '3_fabricacion',
        ProjectSection.soldadura => '4_soldadura',
        ProjectSection.montaje => '5_montaje',
        ProjectSection.planos => '6_planos',
        ProjectSection.presupuesto => '7_presupuesto',
      };

  /// Si el apartado necesita el render o la isométrica (para no generarlos
  /// cuando no hacen falta: ahorra memoria y tiempo en el móvil).
  bool get needsRender => this == ProjectSection.resumen || this == ProjectSection.montaje;
  bool get needsIso => this == ProjectSection.fabricacion || this == ProjectSection.montaje;
}

/// Datos del proyecto guardado para las cabeceras.
class ProjectInfo {
  final String name;
  final String client;
  final String site;
  const ProjectInfo({this.name = '', this.client = '', this.site = ''});
}

String _n(double v, [int d = 1]) => v.toStringAsFixed(d).replaceAll('.', ',');
String _eur(double v) {
  final s = v.toStringAsFixed(2);
  final parts = s.split('.');
  final ent = parts[0].replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.');
  return '$ent,${parts[1]} €';
}

Future<Uint8List> _png(ui.Image img) async {
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return bd!.buffer.asUint8List();
}

/// Láminas CAD de cada apartado.
List<CadSheet> sheetsFor(ProjectSection s, List<CadSheet> all) {
  bool has(CadSheet sh, List<String> ws) => ws.any((w) => sh.title.toLowerCase().contains(w));
  return switch (s) {
    ProjectSection.planos => all,
    ProjectSection.fabricacion => [for (final sh in all) if (has(sh, ['despiece', 'detalle', 'alzado', 'sección', 'seccion'])) sh],
    ProjectSection.soldadura => [for (final sh in all) if (has(sh, ['soldadura', 'detalle'])) sh],
    ProjectSection.montaje => [for (final sh in all) if (has(sh, ['replanteo', 'planta', 'alzado', 'cimentación'])) sh],
    ProjectSection.materiales => [for (final sh in all) if (has(sh, ['lista de materiales'])) sh],
    _ => const [],
  };
}

/// Genera un PDF con los apartados pedidos, cada uno empezando en página
/// nueva con su cabecera y su propia numeración («Soldadura · pág. 2 de 3»).
Future<Uint8List> buildSectionsPdf(
  Design d,
  List<ProjectSection> sections, {
  Finish finish = Finish.galvanizado,
  Uint8List? aiPhoto,
  Budget? budget,
  ProjectInfo info = const ProjectInfo(),
  bool budgetDetail = true,
}) async {
  final reg = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
  final title = info.name.isNotEmpty ? info.name : d.spec.type.label;
  final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: reg, bold: bold),
      title: sections.length == 1 ? '$title – ${sections.first.label}' : 'Herrero – $title',
      author: 'Herrero · Oficina técnica');

  // Imágenes solo si algún apartado las usa, y se sueltan al acabar.
  Uint8List? render, iso;
  if (aiPhoto == null && sections.any((s) => s.needsRender)) {
    final (_, img) = await renderHq(d, finish, OrbitCamera(), width: 1200, height: 800, ss: 2);
    render = await _png(img);
  }
  if (sections.any((s) => s.needsIso)) {
    iso = await _png(await paintToImage((c, s) => IsoPainter(d).paint(c, s), const Size(1100, 760), 2));
  }
  final needSheets = sections.any((s) => s == ProjectSection.planos || s == ProjectSection.fabricacion ||
      s == ProjectSection.soldadura || s == ProjectSection.montaje || s == ProjectSection.materiales);
  final sheets = needSheets ? buildSheets(d) : const <CadSheet>[];

  final b = _Builder(d, bold, info, title);
  for (final s in sections) {
    switch (s) {
      case ProjectSection.resumen:
        b.resumen(doc, aiPhoto ?? render!);
      case ProjectSection.calculo:
        b.calculo(doc);
      case ProjectSection.materiales:
        b.materiales(doc);
      case ProjectSection.fabricacion:
        b.fabricacion(doc, iso!);
      case ProjectSection.soldadura:
        b.soldadura(doc);
      case ProjectSection.montaje:
        b.montaje(doc, iso!, aiPhoto ?? render);
      case ProjectSection.planos:
        break;
      case ProjectSection.presupuesto:
        if (budget != null) b.presupuesto(doc, budget, detail: budgetDetail);
    }
    final cad = sheetsFor(s, sheets);
    if (cad.isNotEmpty) addCadPages(doc, cad, reg, bold);
  }
  return doc.save();
}

class _Builder {
  final Design d;
  final pw.Font bold;
  final ProjectInfo info;
  final String title;
  _Builder(this.d, this.bold, this.info, this.title);

  static const head = pw.TextStyle(fontSize: 8, color: PdfColors.white);
  static const cell = pw.TextStyle(fontSize: 7.5);
  static const accent = PdfColor.fromInt(0xFFBF360C);

  pw.Widget table(List<String> headers, List<List<String>> rows,
          {Map<int, pw.Alignment>? align, Map<int, pw.TableColumnWidth>? widths}) =>
      pw.TableHelper.fromTextArray(
        columnWidths: widths,
        headers: headers,
        data: rows,
        headerStyle: head.copyWith(font: bold),
        headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF263238)),
        cellStyle: cell,
        cellAlignment: pw.Alignment.centerLeft,
        cellAlignments: align,
        oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1F4F5)),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      );

  pw.Widget h1(String t) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10, bottom: 5),
      child: pw.Text(t, style: pw.TextStyle(fontSize: 13, font: bold, color: accent)));

  pw.Widget bullet(String t, {double size = 8.5}) => pw.Bullet(text: t, style: pw.TextStyle(fontSize: size));

  /// Cabecera de cada página del apartado: proyecto, apartado y destinatario.
  pw.Widget Function(pw.Context) header(ProjectSection s) => (ctx) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 8),
        padding: const pw.EdgeInsets.only(bottom: 4),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: accent, width: 1))),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(s.label.toUpperCase(), style: pw.TextStyle(font: bold, fontSize: 12, color: accent, letterSpacing: 1)),
              pw.Text(
                  [title, if (info.client.isNotEmpty) 'Cliente: ${info.client}', if (info.site.isNotEmpty) 'Obra: ${info.site}']
                      .join(' · '),
                  style: const pw.TextStyle(fontSize: 8)),
            ]),
          ),
          pw.Text('Para: ${s.recipient}', style: pw.TextStyle(font: bold, fontSize: 8)),
        ]),
      );

  /// Pie con numeración propia del apartado. Cada apartado es un MultiPage
  /// distinto: pagesCount cuenta solo sus páginas.
  pw.Widget Function(pw.Context) footer(ProjectSection s) => (ctx) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Herrero · Predimensionado orientativo – validar por técnico competente',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
          pw.Text('${s.label} · pág. ${ctx.pageNumber - _first[s]! + 1} de ${_count(ctx, s)}',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
        ],
      );

  // pdf numera las páginas del documento entero; guardamos dónde empieza
  // cada apartado para numerar dentro de él.
  final _first = <ProjectSection, int>{};
  final _last = <ProjectSection, int>{};
  int _count(pw.Context ctx, ProjectSection s) => (_last[s] ?? ctx.pageNumber) - _first[s]! + 1;

  pw.MultiPage page(ProjectSection s, List<pw.Widget> Function() content, {PdfPageFormat? format}) => pw.MultiPage(
        pageFormat: format ?? PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (ctx) {
          _first.putIfAbsent(s, () => ctx.pageNumber);
          _last[s] = ctx.pageNumber > (_last[s] ?? 0) ? ctx.pageNumber : _last[s]!;
          return header(s)(ctx);
        },
        footer: footer(s),
        build: (_) => content(),
      );

  pw.Widget kpi(String label, String value) => pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.only(right: 6),
          padding: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 0.5), borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(label, style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
            pw.Text(value, style: pw.TextStyle(font: bold, fontSize: 12)),
          ]),
        ),
      );

  String dims() {
    final s = d.spec;
    final (l, w, h) = s.type.dimLabels;
    return [
      for (final (k, v) in [(l, s.length), (w, s.width), (h, s.height)])
        if (!k.contains('no aplica') && v > 0) '${k.toLowerCase()} ${_n(v, 2)} m',
    ].join(' · ');
  }

  // ---------------------------------------------------------------- Resumen
  void resumen(pw.Document doc, Uint8List image) {
    final s = d.spec;
    doc.addPage(page(ProjectSection.resumen, () => [
          pw.Text(s.type.label, style: pw.TextStyle(font: bold, fontSize: 22)),
          pw.Text('${dims()} · ${s.grade.name}', style: const pw.TextStyle(fontSize: 12)),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            color: const PdfColor.fromInt(0xFFF1F4F5),
            child: pw.Text('Solicitud: "${d.prompt}"', style: const pw.TextStyle(fontSize: 9)),
          ),
          pw.SizedBox(height: 10),
          pw.ClipRRect(
              horizontalRadius: 6, verticalRadius: 6, child: pw.Image(pw.MemoryImage(image), height: 330, fit: pw.BoxFit.cover)),
          pw.SizedBox(height: 12),
          pw.Row(children: [
            kpi(metalLabel(s.grade), '${_n(d.steelKg, 0)} kg'),
            kpi('Perfiles', '${_n(d.profilesKg, 0)} kg'),
            kpi('Chapas', '${_n(d.platesKg, 0)} kg'),
            kpi('Ratio', '${_n(d.steelRatio.$1, 1)} ${d.steelRatio.$2}'),
          ]),
          pw.SizedBox(height: 6),
          pw.Row(children: [
            kpi('Soldadura', '${_n(d.weldMeters, 1)} m'),
            kpi('Consumible', '${_n(d.consumableKg, 1)} kg'),
            kpi('Pintura', '${_n(d.paintM2, 0)} m²'),
            kpi('η máx.', '${_n(d.maxUtilization * 100, 0)} %'),
          ]),
          pw.SizedBox(height: 10),
          ...d.warnings.map((w) => pw.Bullet(text: w, style: const pw.TextStyle(fontSize: 8, color: PdfColors.red900))),
          pw.SizedBox(height: 4),
          pw.Text('Generado el ${DateTime.now().toString().substring(0, 16)}',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
        ]));
  }

  // ---------------------------------------------------------------- Cálculo
  void calculo(pw.Document doc) {
    doc.addPage(page(ProjectSection.calculo, () => [
          h1('Materiales'),
          pw.Table(
            columnWidths: const {0: pw.FixedColumnWidth(110), 1: pw.FlexColumnWidth()},
            children: [
              for (final (k, v) in materialRows(d))
                pw.TableRow(children: [
                  pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                      child: pw.Text(k, style: pw.TextStyle(font: bold, fontSize: 8.5))),
                  pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                      child: pw.Text(v, style: const pw.TextStyle(fontSize: 8.5))),
                ]),
            ],
          ),
          h1('Hipótesis'),
          ...d.hypotheses.map(bullet),
          h1('Comprobaciones (ELU / ELS)'),
          table(['Elemento', 'Comprobación', 'η', 'Estado', 'Detalle'], [
            for (final c in d.checks)
              [c.element, c.description, '${_n(c.utilization * 100, 0)} %', c.ok ? 'CUMPLE' : 'NO CUMPLE', c.detail]
          ]),
          if (d.norms.isNotEmpty) ...[
            h1('Normativa de referencia'),
            ...d.norms.map((n) => bullet('${n.code}: ${n.title}.', size: 8)),
            pw.Text('Resumen orientativo; consultar la edición vigente de cada norma (AENOR, BOE).',
                style: const pw.TextStyle(fontSize: 7.5)),
          ],
        ]));
  }

  // ------------------------------------------------------------- Materiales
  List<pw.Widget> _orderTable() => [
        table(['Perfil', 'Pedido', 'Metros', 'kg aprox.', 'Merma', 'Retales útiles (mm)'], [
          for (final st in d.stock)
            [
              '${st.profile.name} ${d.spec.grade.name}',
              st.orderText,
              _n(st.purchasedMm / 1000, 1),
              _n(st.purchasedKg * d.spec.grade.density / 7850, 0),
              '${_n(st.wastePct, 1)} %',
              st.remnants.isEmpty ? '-' : st.remnants.join(' / '),
            ]
        ]),
      ];

  void materiales(pw.Document doc) {
    final plateKg = <double, (double, int)>{};
    for (final p in d.plates) {
      final o = plateKg[p.t] ?? (0.0, 0);
      plateKg[p.t] = (o.$1 + p.totalKg, o.$2 + p.qty);
    }
    doc.addPage(page(ProjectSection.materiales, () => [
          pw.Text('${d.spec.type.label} · ${dims()} · ${metalLabel(d.spec.grade)} ${d.spec.grade.name}',
              style: const pw.TextStyle(fontSize: 9)),
          h1('Pedido de barras comerciales'),
          ..._orderTable(),
          h1('Chapa'),
          table(['Espesor', 'Piezas', 'kg netos', 'kg a pedir (+15 % recortes)'], [
            for (final e in (plateKg.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
              ['${_n(e.key, 0)} mm', '${e.value.$2}', _n(e.value.$1, 0), _n(e.value.$1 * 1.15, 0)]
          ]),
          h1('Tornillería y anclajes'),
          table(['Elemento', 'Especificación', 'Ud.'], [
            for (final bo in d.bolts) [bo.description, bo.spec, '${bo.qty}']
          ]),
          h1('Consumibles y acabado'),
          table(['Concepto', 'Cantidad'], [
            ['Consumible de soldadura (${d.welds.isEmpty ? '-' : d.welds.first.process})', '${_n(d.consumableKg, 1)} kg'],
            ['Superficie a pintar', '${_n(d.paintM2, 0)} m²'],
            ['Acabado', d.spec.finish],
            ['Peso total de acero', '${_n(d.steelKg, 0)} kg'],
          ]),
        ]));
  }

  // ------------------------------------------------------------ Fabricación
  void fabricacion(pw.Document doc, Uint8List iso) {
    doc.addPage(page(ProjectSection.fabricacion, () => [
          h1('Despiece de perfiles'),
          table(['Marca', 'Elemento', 'Perfil', 'Long. (mm)', 'Ud.', 'Corte', 'kg/ud', 'kg'], [
            for (final p in d.pieces)
              [p.mark, p.description, p.profile.name, p.lengthMm.toStringAsFixed(0), '${p.qty}', p.cut, _n(p.unitKg), _n(p.totalKg, 0)],
            ['', 'TOTAL PERFILES', '', '', '${d.pieces.fold<int>(0, (a, p) => a + p.qty)}', '', '', _n(d.profilesKg, 0)],
          ]),
          h1('Chapas'),
          table(['Marca', 'Descripción', 'Dimensiones (mm)', 'Ud.', 'kg', 'Notas'], [
            for (final p in d.plates)
              [p.mark, p.description, '${p.w.toStringAsFixed(0)} x ${p.h.toStringAsFixed(0)} x ${p.t.toStringAsFixed(0)}', '${p.qty}', _n(p.totalKg, 0), p.notes]
          ]),
          h1('Plan de corte'),
          if (d.stock.isNotEmpty)
            pw.Text(
                'Sierra ${d.stock.first.settings.kerf} mm, despunte ${d.stock.first.settings.trim} mm por extremo, '
                'retal útil desde ${d.stock.first.settings.minRemnant} mm. Barras iguales agrupadas:',
                style: const pw.TextStyle(fontSize: 7.5)),
          for (final st in d.stock)
            for (final l in cutPlanLines(st)) pw.Text('${st.profile.name} · $l', style: const pw.TextStyle(fontSize: 7.5)),
          h1('Vista isométrica con marcas'),
          pw.Image(pw.MemoryImage(iso), height: 420, fit: pw.BoxFit.contain),
        ]));
  }

  // -------------------------------------------------------------- Soldadura
  void soldadura(pw.Document doc) {
    final f = d.spec.fab;
    final weldNorms = [
      for (final n in d.norms)
        if (RegExp(r'ISO (2553|3834|9606|15614|15609|5817|17637|4063)|1090|ISO 14731', caseSensitive: false).hasMatch(n.code)) n
    ];
    doc.addPage(page(ProjectSection.soldadura, () => [
          table(['Concepto', 'Valor'], [
            ['Material base', '${d.spec.grade.name} · ${d.spec.grade.norm}'],
            ['Proceso y aportación', d.spec.grade.weld],
            ['Clase de ejecución (EN 1090-2)', 'EXC${f.execClass}'],
            ['Nivel de calidad (EN ISO 5817)', f.qualityLevel],
            if (f.ndt.isNotEmpty) ['Ensayos pedidos', f.ndt.map((e) => '$e: ${ndtNames[e] ?? e}').join('; ')],
            if (f.siteWelding) ['Soldadura en obra', 'Sí'],
          ]),
          h1('Uniones soldadas'),
          table(['Unión', 'Tipo', 'a (mm)', 'L/unión (mm)', 'Nº', 'Total (m)', 'Consumible (kg)', 'Proceso / posición'], [
            for (final w in d.welds)
              [w.joint, w.type, w.throat.toStringAsFixed(0), w.lengthPerJoint.toStringAsFixed(0), '${w.count}', _n(w.totalMeters), _n(w.consumableKg, 2), '${w.process} · ${w.position}'],
            ['TOTAL', '', '', '', '', _n(d.weldMeters), _n(d.consumableKg, 2), ''],
          ]),
          for (final w in d.welds)
            if (w.notes.isNotEmpty) bullet('${w.joint}: ${w.notes}', size: 7.5),
          pw.SizedBox(height: 6),
          pw.Text(weldingHypothesis(f), style: const pw.TextStyle(fontSize: 7.5)),
          if (weldNorms.isNotEmpty) ...[
            h1('Normativa de soldadura'),
            ...weldNorms.map((n) => bullet('${n.code}: ${n.title}.', size: 8)),
          ],
        ]));
  }

  // ---------------------------------------------------------------- Montaje
  void montaje(pw.Document doc, Uint8List iso, Uint8List? render) {
    doc.addPage(page(ProjectSection.montaje, () => [
          h1('Secuencia de montaje'),
          ...d.assembly.asMap().entries.map((e) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Text('${e.key + 1}. ${e.value}', style: const pw.TextStyle(fontSize: 8.5)))),
          h1('Tornillería y anclajes'),
          table(['Elemento', 'Especificación', 'Ud.', 'Uso'], [
            for (final bo in d.bolts) [bo.description, bo.spec, '${bo.qty}', bo.use]
          ]),
          h1('Piezas que llegan a obra'),
          table(['Marca', 'Elemento', 'Perfil', 'Long. (mm)', 'Ud.'], [
            for (final p in d.pieces) [p.mark, p.description, p.profile.name, p.lengthMm.toStringAsFixed(0), '${p.qty}']
          ]),
          h1('Vista isométrica con marcas'),
          pw.Image(pw.MemoryImage(iso), height: 380, fit: pw.BoxFit.contain),
          if (render != null) ...[
            h1('Vista final'),
            pw.Image(pw.MemoryImage(render), height: 300, fit: pw.BoxFit.contain),
          ],
        ]));
  }

  // ------------------------------------------------------------ Presupuesto
  void presupuesto(pw.Document doc, Budget bu, {bool detail = true}) {
    String unitTxt(BudgetLine l) => l.unit == PriceUnit.servicio ? 'h' : l.unit.short;
    final r = bu.rates;
    doc.addPage(page(ProjectSection.presupuesto, () => [
          pw.Text('${d.spec.type.label} · ${dims()} · ${d.spec.grade.name} · ${d.spec.finish}',
              style: const pw.TextStyle(fontSize: 9)),
          pw.Text('Fecha: ${DateTime.now().toString().substring(0, 10)}', style: const pw.TextStyle(fontSize: 8)),
          for (final s in BudgetSection.values)
            if (bu.of(s).isNotEmpty) ...[
              h1(s.label),
              table(
                detail ? ['Concepto', 'Cantidad', 'Precio', 'Importe', 'Origen del precio'] : ['Concepto', 'Cantidad', 'Importe'],
                [
                  for (final l in bu.of(s))
                    detail
                        ? [
                            l.concept,
                            '${_n(l.qty, l.qty < 10 ? 2 : 1)} ${unitTxt(l)}',
                            l.unitPrice == null ? '—' : '${_n(l.unitPrice!, 3)} €/${unitTxt(l)}',
                            l.total == null ? 'SIN PRECIO' : _eur(l.total!),
                            l.origin,
                          ]
                        : [l.concept, '${_n(l.qty, l.qty < 10 ? 2 : 1)} ${unitTxt(l)}', l.total == null ? 'SIN PRECIO' : _eur(l.total!)],
                  [
                    'Subtotal ${s.label.toLowerCase()}',
                    '',
                    if (detail) '',
                    _eur(bu.subtotalOf(s)),
                    if (detail) '',
                  ],
                ],
                align: detail
                    ? {1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight}
                    : {1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight},
                widths: detail
                    ? const {
                        0: pw.FlexColumnWidth(3.2),
                        1: pw.FixedColumnWidth(52),
                        2: pw.FixedColumnWidth(58),
                        3: pw.FixedColumnWidth(62),
                        4: pw.FlexColumnWidth(2.6),
                      }
                    : const {0: pw.FlexColumnWidth(4), 1: pw.FixedColumnWidth(70), 2: pw.FixedColumnWidth(80)},
              ),
            ],
          pw.SizedBox(height: 12),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.SizedBox(
              width: 260,
              child: table(['Resumen', 'Importe'], [
                ['Coste directo', _eur(bu.direct - bu.extras)],
                if (bu.extras > 0) ['Transporte y medios auxiliares', _eur(bu.extras)],
                if (r.marginPct > 0) ['Gastos generales y beneficio (${_n(r.marginPct, 1)} %)', _eur(bu.margin)],
                ['Base imponible', _eur(bu.base)],
                ['IVA (${_n(r.vatPct, 0)} %)', _eur(bu.vat)],
                ['TOTAL', _eur(bu.total)],
              ], align: {1: pw.Alignment.centerRight}),
            ),
          ),
          if (!bu.complete)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 8),
              child: pw.Text(
                  'ATENCIÓN: ${bu.missing.length} línea(s) sin precio no están sumadas en el total. '
                  'Complétalas antes de entregar este presupuesto.',
                  style: pw.TextStyle(font: bold, fontSize: 9, color: PdfColors.red900)),
            ),
          pw.SizedBox(height: 8),
          pw.Text(
              'Presupuesto orientativo basado en el predimensionado de Herrero y en los precios de la base del taller '
              '(facturas, tarifas y precios fijados). Validez sujeta a la variación del precio del acero.',
              style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
        ]));
  }
}
