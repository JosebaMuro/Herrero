import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../engine/model.dart';
import '../engine/profiles.dart';
import 'drawing_utils.dart';

enum SheetView { front, side, plan, detail }

extension SheetViewName on SheetView {
  String get title {
    switch (this) {
      case SheetView.front:
        return 'Alzado frontal – pórtico tipo';
      case SheetView.side:
        return 'Alzado lateral – fachada eje A';
      case SheetView.plan:
        return 'Planta de estructura y cubierta';
      case SheetView.detail:
        return 'Detalle placa de anclaje';
    }
  }

  String get number {
    switch (this) {
      case SheetView.front:
        return 'E-01';
      case SheetView.side:
        return 'E-02';
      case SheetView.plan:
        return 'E-03';
      case SheetView.detail:
        return 'E-04';
    }
  }
}

/// Plano de montaje en formato lámina (con cajetín).
class SheetPainter extends CustomPainter {
  final Design d;
  final SheetView view;
  SheetPainter(this.d, this.view);

  static const _ink = Color(0xFF263238);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF));
    final border = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final frame = Rect.fromLTWH(8, 8, size.width - 16, size.height - 16);
    canvas.drawRect(frame, border);

    // Cajetín
    final cw = math.min(300.0, frame.width * 0.62);
    const ch = 62.0;
    final cb = Rect.fromLTWH(frame.right - cw, frame.bottom - ch, cw, ch);
    canvas.drawRect(cb, Paint()..color = const Color(0xFFF5F7F8));
    canvas.drawRect(cb, border..strokeWidth = 1);
    canvas.drawLine(Offset(cb.left, cb.top + 22), Offset(cb.right, cb.top + 22), border..strokeWidth = 0.6);
    canvas.drawLine(Offset(cb.right - 62, cb.top), Offset(cb.right - 62, cb.bottom), border);
    drawText(canvas, 'HERRERO · Oficina técnica', Offset(cb.left + 6, cb.top + 11),
        size: 11, bold: true, align: Alignment.centerLeft);
    drawText(canvas, view.title, Offset(cb.left + 6, cb.top + 33),
        size: 10, align: Alignment.centerLeft);
    drawText(canvas,
        '${d.spec.type.label} · ${fmt(d.spec.length)}x${fmt(d.spec.width)}x${fmt(d.spec.height)} m · ${d.spec.grade.name}',
        Offset(cb.left + 6, cb.top + 49),
        size: 8, align: Alignment.centerLeft, color: const Color(0xFF546E7A));
    drawText(canvas, view.number, Offset(cb.right - 31, cb.top + 11), size: 12, bold: true);
    drawText(canvas, 'Escala S/E', Offset(cb.right - 31, cb.top + 33), size: 8);
    final now = DateTime.now();
    drawText(canvas, '${now.day}/${now.month}/${now.year}', Offset(cb.right - 31, cb.top + 49), size: 8);
    drawText(canvas, 'PREDIMENSIONADO ORIENTATIVO – A VALIDAR POR TÉCNICO COMPETENTE',
        Offset(frame.left + 8, frame.bottom - 8),
        size: 7, color: const Color(0xFFB71C1C), align: Alignment.centerLeft);

    final area = Rect.fromLTRB(frame.left + 50, frame.top + 40, frame.right - 40,
        frame.bottom - ch - 36);
    drawText(canvas, view.title.toUpperCase(), Offset(frame.left + 14, frame.top + 16),
        size: 12, bold: true, align: Alignment.centerLeft);

    switch (view) {
      case SheetView.front:
        _front(canvas, area);
        break;
      case SheetView.side:
        _side(canvas, area);
        break;
      case SheetView.plan:
        _plan(canvas, area);
        break;
      case SheetView.detail:
        _detail(canvas, area);
        break;
    }
  }

  // Ajusta coordenadas 2D (m) al área de dibujo.
  (double, Offset Function(double, double)) _fit(
      Rect area, double minU, double maxU, double minV, double maxV) {
    final sc = math.min(area.width / (maxU - minU), area.height / (maxV - minV));
    final ox = area.left + (area.width - (maxU - minU) * sc) / 2;
    final oy = area.bottom - (area.height - (maxV - minV) * sc) / 2;
    return (sc, (double u, double v) => Offset(ox + (u - minU) * sc, oy - (v - minV) * sc));
  }

  void _members(Canvas c, Iterable<Member> ms, Offset Function(Vec3) p, double sc,
      {bool labels = true}) {
    final seen = <String>{};
    for (final m in ms) {
      final pen = Paint()
        ..color = roleColor(m.role)
        ..strokeWidth = math.max(1.2, math.min(6.0, m.profile.h / 1000 * sc))
        ..strokeCap = StrokeCap.butt;
      if (m.role == MemberRole.brace) {
        dashedLine(c, p(m.a), p(m.b), pen..strokeWidth = 1.4, dash: 10, gap: 4);
      } else {
        c.drawLine(p(m.a), p(m.b), pen);
      }
    }
    if (!labels) return;
    for (final m in ms) {
      if (m.role == MemberRole.baluster) continue;
      if (seen.contains(m.mark)) continue;
      seen.add(m.mark);
      final a = p(m.a), b = p(m.b);
      if ((a - b).distance < 6) continue;
      drawText(c, '${m.mark} ${m.profile.name}', (a + b) / 2,
          size: 9, bold: true, color: const Color(0xFFFFFFFF), background: roleColor(m.role));
    }
  }

  void _sections(Canvas c, Iterable<Member> ms, Offset Function(Vec3) p, double sc) {
    for (final m in ms) {
      final s = math.max(4.0, m.profile.h / 1000 * sc);
      c.drawRect(Rect.fromCenter(center: p(m.a), width: s * 0.7, height: s),
          Paint()..color = roleColor(m.role));
    }
  }

  bool _near(double a, double b) => (a - b).abs() < 0.02;

  void _front(Canvas c, Rect area) {
    final x0 = d.frameX.length > 2 ? d.frameX[1] : d.frameX.first;
    final inPlane = d.members.where((m) => _near(m.a.x, x0) && _near(m.b.x, x0)).toList();
    final across = d.members.where((m) =>
        (_near(m.a.x, x0) || _near(m.b.x, x0)) &&
        !_near(m.a.x, m.b.x) &&
        (m.role == MemberRole.purlin || m.role == MemberRole.tie || m.role == MemberRole.beam));
    final yMax = d.gridY.last;
    final zMax = d.ridgeHeight + (d.spec.railing ? 1.2 : 0.3);
    final (sc, f) = _fit(area, -1.2, yMax + 1.2, -0.9, zMax);
    Offset p(Vec3 v) => f(v.y, v.z);
    _ground(c, f(-1.2, 0), f(yMax + 1.2, 0));
    _sections(c, across, p, sc);
    _members(c, inPlane, p, sc);
    for (var j = 0; j < d.gridY.length; j++) {
      final b = f(d.gridY[j], -0.6);
      dashedLine(c, b, f(d.gridY[j], zMax), Paint()..color = const Color(0x44607D8B), dash: 12, gap: 3);
      drawAxisBubble(c, b + const Offset(0, 14), axisLetter(j));
    }
    for (var j = 0; j < d.gridY.length - 1; j++) {
      drawDim(c, f(d.gridY[j], 0), f(d.gridY[j + 1], 0), 26, '${fmt(d.gridY[j + 1] - d.gridY[j])}');
    }
    if (d.gridY.length > 2) drawDim(c, f(0, 0), f(yMax, 0), 44, '${fmt(yMax)}');
    drawDim(c, f(0, 0), f(0, d.spec.height), -28, fmt(d.spec.height));
    if (d.ridgeHeight > d.spec.height + 0.05) {
      drawDim(c, f(yMax, 0), f(yMax, d.ridgeHeight), 28, fmt(d.ridgeHeight));
      final mid = f(yMax * 0.25, d.spec.height + (d.ridgeHeight - d.spec.height) * 0.5);
      drawText(c, 'Pendiente ${fmt(d.spec.slopePct, 1)} %', mid + const Offset(0, -22), size: 9);
    }
    _legend(c, area, sc);
  }

  void _side(Canvas c, Rect area) {
    final ms = d.members.where((m) => _near(m.a.y, 0) && _near(m.b.y, 0)).toList();
    final across = d.members.where((m) =>
        (_near(m.a.y, 0) || _near(m.b.y, 0)) && !_near(m.a.y, m.b.y) &&
        (m.role == MemberRole.rafter || m.role == MemberRole.beam || m.role == MemberRole.joist));
    final xMax = d.frameX.last;
    final zMax = math.max(d.spec.height, d.ridgeHeight) + (d.spec.railing ? 1.2 : 0.3);
    final (sc, f) = _fit(area, -1.2, xMax + 1.2, -0.9, zMax);
    Offset p(Vec3 v) => f(v.x, v.z);
    _ground(c, f(-1.2, 0), f(xMax + 1.2, 0));
    _sections(c, across, p, sc);
    _members(c, ms, p, sc);
    for (var i = 0; i < d.frameX.length; i++) {
      final b = f(d.frameX[i], -0.6);
      dashedLine(c, b, f(d.frameX[i], zMax), Paint()..color = const Color(0x44607D8B), dash: 12, gap: 3);
      drawAxisBubble(c, b + const Offset(0, 14), '${i + 1}');
    }
    for (var i = 0; i < d.frameX.length - 1; i++) {
      drawDim(c, f(d.frameX[i], 0), f(d.frameX[i + 1], 0), 26, fmt(d.frameX[i + 1] - d.frameX[i]));
    }
    drawDim(c, f(0, 0), f(xMax, 0), 44, fmt(xMax));
    drawDim(c, f(0, 0), f(0, d.spec.height), -28, fmt(d.spec.height));
    _legend(c, area, sc);
  }

  void _plan(Canvas c, Rect area) {
    final xMax = d.frameX.last;
    final yMax = d.gridY.last;
    final (sc, f) = _fit(area, -1.5, xMax + 1.5, -1.5, yMax + 1.5);
    Offset p(Vec3 v) => f(v.x, v.y);
    final axisPen = Paint()..color = const Color(0x55607D8B);
    for (var i = 0; i < d.frameX.length; i++) {
      dashedLine(c, f(d.frameX[i], -1.1), f(d.frameX[i], yMax + 0.6), axisPen, dash: 12, gap: 3);
      drawAxisBubble(c, f(d.frameX[i], -1.3), '${i + 1}');
    }
    for (var j = 0; j < d.gridY.length; j++) {
      dashedLine(c, f(-1.1, d.gridY[j]), f(xMax + 0.6, d.gridY[j]), axisPen, dash: 12, gap: 3);
      drawAxisBubble(c, f(-1.3, d.gridY[j]), axisLetter(j));
    }
    bool vertical(Member m) => _near(m.a.x, m.b.x) && _near(m.a.y, m.b.y);
    final ms = d.members.where((m) => !vertical(m) && m.role != MemberRole.baluster).toList()
      ..sort((a, b) => (a.a.z + a.b.z).compareTo(b.a.z + b.b.z));
    _members(c, ms, p, sc * 0.6);
    // pilares, postes y montantes en planta
    final seen = <String>{};
    for (final m in d.members.where((m) => vertical(m) && m.role != MemberRole.baluster)) {
      final key = '${m.a.x.toStringAsFixed(2)}|${m.a.y.toStringAsFixed(2)}';
      if (!seen.add(key)) continue;
      final s = math.max(5.0, m.profile.h / 1000 * sc);
      final w = math.max(5.0, m.profile.b / 1000 * sc);
      final horiz = m.webDir.y.abs() > 0.5;
      c.drawRect(Rect.fromCenter(center: p(m.a), width: horiz ? w : s, height: horiz ? s : w),
          Paint()..color = roleColor(m.role));
    }
    for (var i = 0; i < d.frameX.length - 1; i++) {
      drawDim(c, f(d.frameX[i], yMax), f(d.frameX[i + 1], yMax), -22, fmt(d.frameX[i + 1] - d.frameX[i]));
    }
    drawDim(c, f(0, yMax), f(xMax, yMax), -40, fmt(xMax));
    if (yMax > 0.3) drawDim(c, f(xMax, 0), f(xMax, yMax), 24, fmt(yMax));
    _legend(c, area, sc);
  }

  void _detail(Canvas c, Rect area) {
    if (d.plates.isEmpty) {
      drawText(c, 'Sin placas de anclaje: ver uniones y soldaduras en la memoria.', area.center, size: 11);
      return;
    }
    final pa = d.plates.firstWhere((p) => p.mark == 'PA1', orElse: () => d.plates.first);
    final col = d.members
        .firstWhere((m) => m.role == MemberRole.column || m.role == MemberRole.post || m.role == MemberRole.frame,
            orElse: () => d.members.first)
        .profile;
    final w = pa.w, h = pa.h;
    final half = Rect.fromLTRB(area.left, area.top, area.center.dx - 10, area.bottom);
    final sc = math.min(half.width / (w + 160), half.height / (h + 160));
    final ctr = half.center;
    Offset q(double x, double y) => ctr + Offset(x * sc, -y * sc);
    final plate = Rect.fromCenter(center: ctr, width: w * sc, height: h * sc);
    c.drawRect(plate, Paint()..color = const Color(0xFFCFD8DC));
    c.drawRect(plate, Paint()..color = _ink..style = PaintingStyle.stroke..strokeWidth = 1.2);
    final colPaint = Paint()..color = const Color(0xFF1565C0);
    if (col.family == ProfileFamily.shs || col.family == ProfileFamily.rhs) {
      c.drawRect(Rect.fromCenter(center: ctr, width: col.b * sc, height: col.h * sc), colPaint);
      c.drawRect(Rect.fromCenter(center: ctr, width: (col.b - 2 * col.tw) * sc, height: (col.h - 2 * col.tw) * sc),
          Paint()..color = const Color(0xFFCFD8DC));
    } else {
      // I: alas paralelas a x
      c.drawRect(Rect.fromCenter(center: q(0, col.h / 2 - col.tf / 2), width: col.b * sc, height: col.tf * sc), colPaint);
      c.drawRect(Rect.fromCenter(center: q(0, -col.h / 2 + col.tf / 2), width: col.b * sc, height: col.tf * sc), colPaint);
      c.drawRect(Rect.fromCenter(center: ctr, width: col.tw * sc, height: (col.h - 2 * col.tf) * sc), colPaint);
    }
    final bx = w / 2 - 50, by = h / 2 - 50;
    final boltNote = d.bolts.isNotEmpty ? d.bolts.first.spec : '';
    for (final sx in [-1, 1]) {
      for (final sy in [-1, 1]) {
        final o = q(sx * bx, sy * by);
        c.drawCircle(o, math.max(3.0, 12 * sc), Paint()..color = const Color(0xFF263238));
        c.drawCircle(o, math.max(1.5, 7 * sc), Paint()..color = const Color(0xFFFFFFFF));
      }
    }
    drawDim(c, q(-w / 2, -h / 2), q(w / 2, -h / 2), 26, '${pa.w.toStringAsFixed(0)}');
    drawDim(c, q(w / 2, -h / 2), q(w / 2, h / 2), -26, '${pa.h.toStringAsFixed(0)}');
    drawDim(c, q(-bx, h / 2), q(bx, h / 2), -18, '${(2 * bx).toStringAsFixed(0)}', textSize: 9);
    drawText(c, 'PLANTA ${pa.mark}', Offset(half.center.dx, half.top + 4), size: 10, bold: true);

    // Alzado lateral
    final right = Rect.fromLTRB(area.center.dx + 10, area.top, area.right, area.bottom);
    final sc2 = math.min(right.width / (w + 200), right.height / 900);
    final base = Offset(right.center.dx, right.top + right.height * 0.55);
    Offset r(double x, double z) => base + Offset(x * sc2, -z * sc2);
    _ground(c, r(-w / 2 - 80, -30), r(w / 2 + 80, -30));
    c.drawRect(Rect.fromPoints(r(-w / 2, 0), r(w / 2, pa.t)), Paint()..color = const Color(0xFF607D8B));
    c.drawRect(Rect.fromPoints(r(-w / 2 + 10, -30), r(w / 2 - 10, 0)), Paint()..color = const Color(0xFFBDBDBD));
    c.drawRect(Rect.fromPoints(r(-col.b / 2, pa.t), r(col.b / 2, 350)), colPaint);
    for (final sx in [-1, 1]) {
      final x = sx * bx;
      c.drawLine(r(x, pa.t + 40), r(x, -420), Paint()..color = const Color(0xFF37474F)..strokeWidth = 3);
      c.drawLine(r(x, -420), r(x + sx * 80, -420), Paint()..color = const Color(0xFF37474F)..strokeWidth = 3);
      c.drawRect(Rect.fromCenter(center: r(x, pa.t + 14), width: 26 * sc2 + 6, height: 14 * sc2 + 4),
          Paint()..color = const Color(0xFF263238));
    }
    drawText(c, 'Mortero sin retracción e = 30 mm', r(w / 2 + 20, -15),
        size: 8, align: Alignment.centerLeft);
    drawText(c, 'Pernos: $boltNote', r(0, -480), size: 8);
    final weld = d.welds.isNotEmpty ? d.welds.first : null;
    if (weld != null) {
      final at = r(col.b / 2, pa.t + 4);
      c.drawLine(at, at + const Offset(40, -40), Paint()..color = _ink);
      c.drawLine(at + const Offset(40, -40), at + const Offset(110, -40), Paint()..color = _ink);
      final tri = Path()
        ..moveTo(at.dx + 60, at.dy - 40)
        ..lineTo(at.dx + 60, at.dy - 52)
        ..lineTo(at.dx + 72, at.dy - 40)
        ..close();
      c.drawPath(tri, Paint()..color = _ink);
      drawText(c, 'a${weld.throat.toStringAsFixed(0)}', at + const Offset(52, -50), size: 9, bold: true);
      drawText(c, 'perimetral', at + const Offset(86, -50), size: 8);
    }
    drawText(c, 'ALZADO', Offset(right.center.dx, right.top + 4), size: 10, bold: true);
    drawText(c, '${pa.description}  ${pa.w.toStringAsFixed(0)}x${pa.h.toStringAsFixed(0)}x${pa.t.toStringAsFixed(0)} mm · ${pa.notes}',
        Offset(area.center.dx, area.bottom + 14), size: 9);
  }

  void _ground(Canvas c, Offset a, Offset b) {
    c.drawLine(a, b, Paint()..color = const Color(0xFF795548)..strokeWidth = 1.5);
    for (double x = a.dx; x < b.dx; x += 9) {
      c.drawLine(Offset(x, a.dy), Offset(x - 6, a.dy + 6),
          Paint()..color = const Color(0x88795548)..strokeWidth = 0.7);
    }
  }

  void _legend(Canvas c, Rect area, double sc) {
    // Escala gráfica
    final m = sc; // px por metro
    final step = m > 60 ? 1.0 : (m > 15 ? 5.0 : 10.0);
    final o = Offset(area.left - 30, area.bottom + 40);
    for (var i = 0; i < 4; i++) {
      c.drawRect(Rect.fromLTWH(o.dx + i * step * m / 2, o.dy, step * m / 2, 4),
          Paint()..color = i.isEven ? _ink : const Color(0xFFFFFFFF));
    }
    c.drawRect(Rect.fromLTWH(o.dx, o.dy, step * m * 2, 4),
        Paint()..color = _ink..style = PaintingStyle.stroke..strokeWidth = 0.6);
    drawText(c, '0', o + const Offset(0, 12), size: 8);
    drawText(c, '${(step * 2).toStringAsFixed(0)} m', o + Offset(step * m * 2, 12), size: 8);
    drawText(c, 'Cotas en m', o + Offset(step * m * 2 + 40, 2), size: 8);
  }

  @override
  bool shouldRepaint(covariant SheetPainter old) => old.d != d || old.view != view;
}
