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
    final cxm = (lo.x + hi.x) / 2, cym = (lo.y + hi.y) / 2;
    final yNear = depth(Vec3(cxm, lo.y, 0)) > depth(Vec3(cxm, hi.y, 0)) ? lo.y - 1.4 : hi.y + 1.4;
    final xNear = depth(Vec3(lo.x, cym, 0)) > depth(Vec3(hi.x, cym, 0)) ? lo.x - 1.4 : hi.x + 1.4;
    for (var i = 0; i < d.frameX.length; i++) {
      drawAxisBubble(canvas, proj(Vec3(d.frameX[i], yNear, 0)), '${i + 1}', r: 8);
    }
    for (var j = 0; j < d.gridY.length; j++) {
      drawAxisBubble(canvas, proj(Vec3(xNear, d.gridY[j], 0)), axisLetter(j), r: 8);
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

    // Cotas generales (en los lados más cercanos al observador)
    final sp = d.spec;
    final x1 = d.frameX.last;
    final yMax = d.gridY.last;
    final yN = yNear < cym ? 0.0 : yMax;
    final xN = xNear < cxm ? 0.0 : x1;
    void dim(Vec3 a, Vec3 b, String t) {
      final pa = proj(a), pb = proj(b);
      // desplazar hacia fuera del centro de la figura
      final mid = (pa + pb) / 2;
      final ctr = proj(Vec3(cxm, cym, 0));
      final u = pb - pa;
      final n = Offset(-u.dy, u.dx);
      final sign = ((mid - ctr).dx * n.dx + (mid - ctr).dy * n.dy) >= 0 ? 1.0 : -1.0;
      drawDim(canvas, pa, pb, 30 * sign, t);
    }

    dim(Vec3(0, yN, 0), Vec3(x1, yN, 0), '${fmt(sp.length)} m');
    dim(Vec3(xN, 0, 0), Vec3(xN, yMax, 0), '${fmt(yMax)} m');
    final pz0 = proj(Vec3(xN, yN, 0)), pz1 = proj(Vec3(xN, yN, sp.height));
    drawDim(canvas, pz0, pz1, pz0.dx < proj(Vec3(cxm, cym, 0)).dx ? 30 : -30, '${fmt(sp.height)} m');
  }

  @override
  bool shouldRepaint(covariant IsoPainter old) =>
      old.d != d ||
      old.yawDeg != yawDeg ||
      old.highlight != highlight ||
      old.labels != labels;
}
