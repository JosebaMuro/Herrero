import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import 'cad.dart';

/// Dibuja una lámina CAD en un lienzo de Flutter (pantalla o imagen).
class CadPainter extends CustomPainter {
  final CadSheet sheet;
  final bool monochrome; // impresión en negro (convención de plotter)
  CadPainter(this.sheet, {this.monochrome = false});

  @override
  void paint(Canvas canvas, Size size) {
    final k = math.min(size.width / sheet.width, size.height / sheet.height); // px por mm
    final ox = (size.width - sheet.width * k) / 2;
    final oy = (size.height - sheet.height * k) / 2;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFE9ECEE));
    canvas.drawRect(Rect.fromLTWH(ox, oy, sheet.width * k, sheet.height * k), Paint()..color = const Color(0xFFFFFFFF));
    Offset p(double x, double y) => Offset(ox + x * k, oy + (sheet.height - y) * k);
    Color col(CadLayer l) => monochrome ? const Color(0xFF000000) : Color(l.argb);
    Paint stroke(CadLayer l) => Paint()
      ..color = col(l)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.5, l.weight * k)
      ..strokeCap = StrokeCap.butt;

    void seg(Offset a, Offset b, CadLayer l, Paint pen) {
      final pat = l.linetype.pattern;
      if (pat.isEmpty) {
        canvas.drawLine(a, b, pen);
        return;
      }
      final d = b - a;
      final len = d.distance;
      if (len < 0.01) return;
      final u = d / len;
      var t = 0.0;
      var i = 0;
      while (t < len) {
        final v = pat[i % pat.length] * k;
        if (v > 0) {
          canvas.drawLine(a + u * t, a + u * math.min(len, t + v), pen);
          t += v;
        } else if (v == 0) {
          canvas.drawCircle(a + u * t, pen.strokeWidth / 2, Paint()..color = pen.color);
        } else {
          t += -v;
        }
        i++;
      }
    }

    for (final e in sheet.ents) {
      switch (e) {
        case CLine():
          seg(p(e.x1, e.y1), p(e.x2, e.y2), e.layer, stroke(e.layer));
        case CPoly():
          final pts = <Offset>[for (var i = 0; i + 1 < e.pts.length; i += 2) p(e.pts[i], e.pts[i + 1])];
          if (pts.length < 2) continue;
          if (e.fill) {
            final path = Path()..addPolygon(pts, true);
            canvas.drawPath(path, Paint()..color = col(e.layer));
          } else {
            final pen = stroke(e.layer);
            for (var i = 0; i + 1 < pts.length; i++) {
              seg(pts[i], pts[i + 1], e.layer, pen);
            }
            if (e.closed) seg(pts.last, pts.first, e.layer, pen);
          }
        case CCircle():
          final c = p(e.cx, e.cy);
          if (e.fill) {
            canvas.drawCircle(c, e.r * k, Paint()..color = col(e.layer));
          } else {
            canvas.drawCircle(c, e.r * k, stroke(e.layer));
          }
        case CText():
          final tp = TextPainter(
            text: TextSpan(
              text: e.text,
              style: TextStyle(
                fontSize: e.h * k * 1.38, // altura de mayúscula ≈ 0,72 del cuerpo
                height: 1.0,
                color: col(e.layer),
                fontWeight: e.bold ? FontWeight.w700 : FontWeight.w400,
                fontFamily: 'Roboto',
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          final at = p(e.x, e.y);
          canvas.save();
          canvas.translate(at.dx, at.dy);
          if (e.angle != 0) canvas.rotate(-e.angle * math.pi / 180);
          final dx = -tp.width * (e.hAlign + 1) / 2;
          // base: el texto se apoya en la línea; centro: centrado; arriba: cuelga
          final asc = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
          final dy = switch (e.vAlign) { -1 => -asc, 0 => -asc + e.h * k / 2, _ => -asc + e.h * k };
          tp.paint(canvas, Offset(dx, dy));
          canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant CadPainter old) => old.sheet != sheet || old.monochrome != monochrome;
}
