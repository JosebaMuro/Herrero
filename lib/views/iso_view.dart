import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../engine/model.dart';
import 'drawing_utils.dart';

/// Vista isométrica de alambre con marcas de despiece y cotas generales.
class IsoPainter extends CustomPainter {
  final Design d;
  final double yawDeg;
  final int? highlight;
  final bool labels;
  IsoPainter(this.d, {this.yawDeg = -40, this.highlight, this.labels = true});

  static const double _elev = 35.264 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final yaw = yawDeg * math.pi / 180;
    final ca = math.cos(yaw), sa = math.sin(yaw);
    Offset proj0(Vec3 p) {
      final u = p.x * ca - p.y * sa;
      final v = p.x * sa + p.y * ca;
      return Offset(u, v * math.sin(_elev) - p.z * math.cos(_elev));
    }

    double depth(Vec3 p) {
      final v = p.x * sa + p.y * ca;
      return v * math.cos(_elev) + p.z * math.sin(_elev);
    }

    // Encaje en pantalla
    final pts = <Offset>[];
    for (final m in d.members) {
      pts
        ..add(proj0(m.a))
        ..add(proj0(m.b));
    }
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in pts) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    const margin = 46.0;
    final sc = math.min((size.width - 2 * margin) / (maxX - minX),
        (size.height - 2 * margin) / (maxY - minY));
    final ox = (size.width - (maxX - minX) * sc) / 2 - minX * sc;
    final oy = (size.height - (maxY - minY) * sc) / 2 - minY * sc;
    Offset proj(Vec3 p) {
      final o = proj0(p);
      return Offset(o.dx * sc + ox, o.dy * sc + oy);
    }

    // Suelo: rejilla de ejes y zapatas
    final axisPen = Paint()
      ..color = const Color(0x55607D8B)
      ..strokeWidth = 0.7;
    final (lo, hi) = bounds(d.members.expand((m) => [m.a, m.b]));
    for (final x in d.frameX) {
      dashedLine(canvas, proj(Vec3(x, lo.y - 1, 0)), proj(Vec3(x, hi.y + 1, 0)),
          axisPen);
    }
    for (final y in d.gridY) {
      dashedLine(canvas, proj(Vec3(lo.x - 1, y, 0)), proj(Vec3(hi.x + 1, y, 0)),
          axisPen);
    }
    final fs = d.footingSize > 0 ? d.footingSize : 0.3;
    final footPaint = Paint()..color = const Color(0x22546E7A);
    for (final f in d.footings) {
      final path = Path()
        ..moveTo(proj(f + Vec3(-fs / 2, -fs / 2, 0)).dx,
            proj(f + Vec3(-fs / 2, -fs / 2, 0)).dy);
      for (final c in [
        Vec3(fs / 2, -fs / 2, 0),
        Vec3(fs / 2, fs / 2, 0),
        Vec3(-fs / 2, fs / 2, 0)
      ]) {
        final p = proj(f + c);
        path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, footPaint);
    }
    for (var i = 0; i < d.frameX.length; i++) {
      drawAxisBubble(canvas, proj(Vec3(d.frameX[i], lo.y - 1.4, 0)), '${i + 1}',
          r: 8);
    }
    for (var j = 0; j < d.gridY.length; j++) {
      drawAxisBubble(canvas, proj(Vec3(lo.x - 1.4, d.gridY[j], 0)), axisLetter(j),
          r: 8);
    }

    // Barras ordenadas de atrás hacia delante
    final ms = [...d.members]..sort((a, b) =>
        depth((a.a + a.b) * 0.5).compareTo(depth((b.a + b.b) * 0.5)));
    final scaleW = sc / 40;
    for (final m in ms) {
      final hl = highlight != null && m.group == highlight;
      final dim = highlight != null && !hl;
      final w = math.max(1.0, math.min(7.0, m.profile.h / 1000 * sc * 0.8 + scaleW));
      final col = roleColor(m.role);
      canvas.drawLine(
          proj(m.a),
          proj(m.b),
          Paint()
            ..color = dim ? col.withValues(alpha: 0.18) : col
            ..strokeWidth = hl ? w + 3 : w
            ..strokeCap = StrokeCap.round);
    }

    // Etiquetas: una por marca (en la barra más cercana al observador)
    if (labels) {
      final seen = <String>{};
      for (final m in ms.reversed) {
        if (m.role == MemberRole.baluster) continue;
        if (seen.contains(m.mark)) continue;
        if (highlight != null && m.group != highlight) continue;
        seen.add(m.mark);
        final mid = proj((m.a + m.b) * 0.5);
        drawText(canvas, m.mark, mid,
            size: 10,
            bold: true,
            color: const Color(0xFFFFFFFF),
            background: roleColor(m.role));
      }
    }

    // Cotas generales
    final s = d.spec;
    final x1 = d.frameX.last;
    final yMax = d.gridY.last;
    drawDim(canvas, proj(Vec3(0, 0, 0)), proj(Vec3(x1, 0, 0)), 26,
        '${fmt(s.length)} m');
    drawDim(canvas, proj(Vec3(x1, 0, 0)), proj(Vec3(x1, yMax, 0)), 26,
        '${fmt(yMax)} m');
    final topZ = d.spec.type == StructureType.entreplanta ? s.height : s.height;
    drawDim(canvas, proj(Vec3(0, 0, 0)), proj(Vec3(0, 0, topZ)), -26,
        '${fmt(topZ)} m');
    if (d.ridgeHeight > topZ + 0.05) {
      drawDim(canvas, proj(Vec3(0, yMax / 2, 0)), proj(Vec3(0, yMax / 2, d.ridgeHeight)),
          -20, '${fmt(d.ridgeHeight)} m');
    }
  }

  @override
  bool shouldRepaint(covariant IsoPainter old) =>
      old.d != d ||
      old.yawDeg != yawDeg ||
      old.highlight != highlight ||
      old.labels != labels;
}
