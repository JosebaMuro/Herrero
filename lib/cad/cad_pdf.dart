import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:vector_math/vector_math_64.dart' show Matrix4;

import 'cad.dart';

const double _pt = 72 / 25.4; // puntos PDF por mm

/// Añade las láminas CAD al documento como páginas vectoriales a tamaño real
/// (A3 apaisado 1:1, se pueden imprimir a escala). [monochrome] imprime todo
/// en negro, como un plotter.
void addCadPages(pw.Document doc, List<CadSheet> sheets, pw.Font regular, pw.Font bold,
    {bool monochrome = false}) {
  for (final sh in sheets) {
    final fmt = PdfPageFormat(sh.width * _pt, sh.height * _pt);
    doc.addPage(pw.Page(
      pageFormat: fmt,
      margin: pw.EdgeInsets.zero,
      build: (ctx) {
        final fr = regular.getFont(ctx);
        final fb = bold.getFont(ctx);
        return pw.CustomPaint(
          size: PdfPoint(fmt.width, fmt.height),
          painter: (g, size) => _paint(g, sh, fr, fb, monochrome),
        );
      },
    ));
  }
}

void _paint(PdfGraphics g, CadSheet sh, PdfFont fr, PdfFont fb, bool mono) {
  PdfColor col(CadLayer l) => mono ? PdfColors.black : PdfColor.fromInt(l.argb);
  CadLayer? cur;
  void pen(CadLayer l) {
    if (identical(cur, l)) return;
    cur = l;
    g
      ..setStrokeColor(col(l))
      ..setFillColor(col(l))
      ..setLineWidth(math.max(0.13, l.weight) * _pt)
      ..setLineCap(PdfLineCap.butt)
      ..setLineJoin(PdfLineJoin.miter);
    final pat = l.linetype.pattern;
    if (pat.isEmpty) {
      g.setLineDashPattern();
    } else {
      g.setLineDashPattern([for (final v in pat) (v == 0 ? 0.3 : v.abs()) * _pt]);
    }
  }

  g.saveContext();
  for (final e in sh.ents) {
    switch (e) {
      case CLine():
        pen(e.layer);
        g
          ..moveTo(e.x1 * _pt, e.y1 * _pt)
          ..lineTo(e.x2 * _pt, e.y2 * _pt)
          ..strokePath();
      case CPoly():
        if (e.pts.length < 4) continue;
        pen(e.layer);
        g.moveTo(e.pts[0] * _pt, e.pts[1] * _pt);
        for (var i = 2; i + 1 < e.pts.length; i += 2) {
          g.lineTo(e.pts[i] * _pt, e.pts[i + 1] * _pt);
        }
        if (e.fill) {
          g
            ..closePath()
            ..fillPath();
        } else {
          if (e.closed) g.closePath();
          g.strokePath();
        }
      case CCircle():
        pen(e.layer);
        g.drawEllipse(e.cx * _pt, e.cy * _pt, e.r * _pt, e.r * _pt);
        e.fill ? g.fillPath() : g.strokePath();
      case CText():
        if (e.text.isEmpty) continue;
        pen(e.layer);
        final font = e.bold ? fb : fr;
        final size = e.h * 1.38 * _pt; // altura de mayúscula ≈ 0,72 del cuerpo
        final w = font.stringMetrics(e.text).advanceWidth * size;
        final dx = -w * (e.hAlign + 1) / 2;
        final capH = e.h * _pt;
        final dy = switch (e.vAlign) { -1 => 0.0, 0 => -capH / 2, _ => -capH };
        g.saveContext();
        g.setTransform(Matrix4.identity()
          ..translateByDouble(e.x * _pt, e.y * _pt, 0, 1)
          ..rotateZ(e.angle * math.pi / 180));
        g.drawString(font, size, e.text, dx, dy);
        g.restoreContext();
    }
  }
  g.restoreContext();
}
