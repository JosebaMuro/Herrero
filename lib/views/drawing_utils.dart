import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../engine/model.dart';

/// Colores por tipo de barra (para planos e isométrica).
Color roleColor(MemberRole r) {
  switch (r) {
    case MemberRole.column:
      return const Color(0xFF1565C0);
    case MemberRole.rafter:
      return const Color(0xFFC62828);
    case MemberRole.haunch:
      return const Color(0xFFAD1457);
    case MemberRole.purlin:
      return const Color(0xFF2E7D32);
    case MemberRole.beam:
      return const Color(0xFFC62828);
    case MemberRole.joist:
      return const Color(0xFF2E7D32);
    case MemberRole.tie:
      return const Color(0xFF6A1B9A);
    case MemberRole.brace:
      return const Color(0xFFEF6C00);
    case MemberRole.gablePost:
      return const Color(0xFF00838F);
    case MemberRole.post:
    case MemberRole.handrail:
    case MemberRole.baluster:
      return const Color(0xFF546E7A);
  }
}

String fmt(double v, [int d = 2]) =>
    v.toStringAsFixed(d).replaceAll('.', ',');

void drawText(
  Canvas c,
  String text,
  Offset at, {
  double size = 11,
  Color color = const Color(0xFF222222),
  bool bold = false,
  double angle = 0,
  Alignment align = Alignment.center,
  Color? background,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: size,
        color: color,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        fontFamily: 'Roboto',
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  c.save();
  c.translate(at.dx, at.dy);
  if (angle != 0) c.rotate(angle);
  final dx = -tp.width * (align.x + 1) / 2;
  final dy = -tp.height * (align.y + 1) / 2;
  if (background != null) {
    c.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(dx - 3, dy - 1, tp.width + 6, tp.height + 2),
            const Radius.circular(3)),
        Paint()..color = background);
  }
  tp.paint(c, Offset(dx, dy));
  c.restore();
}

/// Línea de cota entre p1 y p2 desplazada `off` píxeles en la normal.
void drawDim(Canvas c, Offset p1, Offset p2, double off, String label,
    {Color color = const Color(0xFF37474F), double textSize = 10}) {
  final d = p2 - p1;
  final len = d.distance;
  if (len < 4) return;
  final u = d / len;
  final n = Offset(-u.dy, u.dx);
  final a = p1 + n * off, b = p2 + n * off;
  final pen = Paint()
    ..color = color
    ..strokeWidth = 0.8;
  c.drawLine(p1 + n * (off.sign * 3), a + n * (off.sign * 4), pen);
  c.drawLine(p2 + n * (off.sign * 3), b + n * (off.sign * 4), pen);
  c.drawLine(a, b, pen);
  // marcas de cota (trazo oblicuo)
  final t = (u + n) * 4 / math.sqrt2;
  c.drawLine(a - t, a + t, pen..strokeWidth = 1.4);
  c.drawLine(b - t, b + t, pen);
  var ang = math.atan2(u.dy, u.dx);
  if (ang > math.pi / 2) ang -= math.pi;
  if (ang < -math.pi / 2) ang += math.pi;
  drawText(c, label, (a + b) / 2 + n * (off.sign * 7), size: textSize, color: color, angle: ang);
}

/// Burbuja de eje (rejilla) con su nombre.
void drawAxisBubble(Canvas c, Offset at, String name, {double r = 9}) {
  c.drawCircle(at, r, Paint()..color = const Color(0xFFFFFFFF));
  c.drawCircle(
      at,
      r,
      Paint()
        ..color = const Color(0xFF37474F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1);
  drawText(c, name, at, size: r * 1.1, bold: true);
}

void dashedLine(Canvas c, Offset a, Offset b, Paint p,
    {double dash = 8, double gap = 4}) {
  final d = b - a;
  final len = d.distance;
  if (len == 0) return;
  final u = d / len;
  var t = 0.0;
  while (t < len) {
    final e = math.min(t + dash, len);
    c.drawLine(a + u * t, a + u * e, p);
    t = e + gap;
  }
}

String axisLetter(int i) => String.fromCharCode(65 + i);

/// Renderiza un CustomPainter a imagen (para PDF / exportar).
Future<ui.Image> paintToImage(
    void Function(Canvas, Size) paint, Size size, double pixelRatio) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.scale(pixelRatio);
  c.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF));
  paint(c, size);
  final pic = rec.endRecording();
  return pic.toImage(
      (size.width * pixelRatio).round(), (size.height * pixelRatio).round());
}

/// Caja envolvente de los miembros.
(Vec3, Vec3) bounds(Iterable<Vec3> pts) {
  var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity, maxZ = -double.infinity;
  for (final p in pts) {
    minX = math.min(minX, p.x);
    minY = math.min(minY, p.y);
    minZ = math.min(minZ, p.z);
    maxX = math.max(maxX, p.x);
    maxY = math.max(maxY, p.y);
    maxZ = math.max(maxZ, p.z);
  }
  return (Vec3(minX, minY, minZ), Vec3(maxX, maxY, maxZ));
}
