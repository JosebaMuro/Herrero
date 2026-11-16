import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../engine/model.dart';
import '../engine/profiles.dart';

/// Acabado del acero en el render.
enum Finish { galvanizado, pintadoGris, pintadoRojo, corten, negro }

extension FinishLabel on Finish {
  String get label {
    switch (this) {
      case Finish.galvanizado:
        return 'Galvanizado';
      case Finish.pintadoGris:
        return 'Gris antracita';
      case Finish.pintadoRojo:
        return 'Imprimación roja';
      case Finish.corten:
        return 'Corten';
      case Finish.negro:
        return 'Lacado negro';
    }
  }

  Vec3 get albedo {
    switch (this) {
      case Finish.galvanizado:
        return const Vec3(0.66, 0.69, 0.72);
      case Finish.pintadoGris:
        return const Vec3(0.22, 0.24, 0.27);
      case Finish.pintadoRojo:
        return const Vec3(0.55, 0.16, 0.11);
      case Finish.corten:
        return const Vec3(0.48, 0.24, 0.12);
      case Finish.negro:
        return const Vec3(0.07, 0.07, 0.08);
    }
  }

  double get specular {
    switch (this) {
      case Finish.galvanizado:
        return 0.55;
      case Finish.pintadoGris:
        return 0.35;
      case Finish.pintadoRojo:
        return 0.2;
      case Finish.corten:
        return 0.05;
      case Finish.negro:
        return 0.45;
    }
  }
}

Finish finishFromSpec(String f) {
  if (f.contains('negro')) return Finish.negro;
  if (f.contains('galvan') || f.contains('inox')) return Finish.galvanizado;
  if (f.contains('corten') || f.contains('oxiron')) return Finish.corten;
  if (f.contains('rojo')) return Finish.pintadoRojo;
  return Finish.pintadoGris;
}

class _Tri {
  final Vec3 a, b, c;
  final Vec3 n;
  final Vec3 albedo;
  final double spec;
  final double alpha;
  final bool castsShadow;
  _Tri(this.a, this.b, this.c, this.albedo, this.spec,
      {this.alpha = 1, this.castsShadow = true})
      : n = (b - a).cross(c - a).normalized;
}

/// Malla 3D de la estructura (perfiles reales extruidos, placas, zapatas y
/// cubierta opcional).
class SceneMesh {
  final List<_Tri> tris = [];
  final Vec3 center;
  final double radius;
  /// Estructura esbelta (más alta que ancha): la cámara se aleja un poco.
  final bool tall;
  SceneMesh._(this.center, this.radius, this.tall);

  factory SceneMesh.build(Design d, Finish finish,
      {bool roof = true, bool detailed = true}) {
    var minV = const Vec3(1e9, 1e9, 1e9), maxV = const Vec3(-1e9, -1e9, -1e9);
    for (final m in d.members) {
      for (final p in [m.a, m.b]) {
        minV = Vec3(math.min(minV.x, p.x), math.min(minV.y, p.y), math.min(minV.z, p.z));
        maxV = Vec3(math.max(maxV.x, p.x), math.max(maxV.y, p.y), math.max(maxV.z, p.z));
      }
    }
    final center = (minV + maxV) * 0.5;
    final radius = (maxV - minV).length / 2;
    final ext = maxV - minV;
    final s = SceneMesh._(center, radius, ext.z > math.max(ext.x, ext.y) * 0.9);
    final alb = finish.albedo;
    final sp = finish.specular;
    for (final m in d.members) {
      s._member(m, alb, sp, detailed);
    }
    // Zapatas y placas
    final fs = d.footingSize > 0 ? d.footingSize : 0.0;
    final col = d.members
        .firstWhere((m) => m.role == MemberRole.column || m.role == MemberRole.post,
            orElse: () => d.members.first)
        .profile;
    final pw = d.plates.isNotEmpty ? d.plates.first.w / 1000 : 0.3;
    final ph = d.plates.isNotEmpty ? d.plates.first.h / 1000 : 0.3;
    for (final f in d.footings) {
      if (fs > 0) {
        s._box(f + Vec3(0, 0, -0.02), const Vec3(1, 0, 0), const Vec3(0, 1, 0),
            const Vec3(0, 0, 1), fs, fs, 0.08, const Vec3(0.62, 0.61, 0.58), 0.05);
      }
      final horiz = col.family != ProfileFamily.shs;
      s._box(f + const Vec3(0, 0, 0.06), const Vec3(1, 0, 0), const Vec3(0, 1, 0),
          const Vec3(0, 0, 1), horiz ? pw : pw, horiz ? ph : pw, 0.02, alb, sp);
    }
    if (roof) s._roof(d);
    for (final sf in d.surfaces) {
      if (!roof && sf.kind == SurfaceKind.roof) continue;
      final (c, sp2, a) = _surfaceLook(sf.kind, d.spec.roofing, alb);
      s._quad(sf.a, sf.b, sf.c, sf.d, c, sp2, alpha: a);
    }
    // Suelo de entreplanta
    if (d.spec.type == StructureType.entreplanta) {
      final x1 = d.frameX.last, y1 = d.gridY.last, z = d.spec.height;
      final tramex = d.spec.roofing.contains('tramex');
      s._quad(Vec3(0, 0, z + 0.01), Vec3(x1, 0, z + 0.01), Vec3(x1, y1, z + 0.01),
          Vec3(0, y1, z + 0.01),
          tramex ? const Vec3(0.55, 0.56, 0.58) : const Vec3(0.45, 0.43, 0.40), 0.2,
          alpha: tramex ? 0.55 : 0.92);
    }
    return s;
  }

  void _member(Member m, Vec3 alb, double sp, bool detailed) {
    final d = (m.b - m.a);
    final len = d.length;
    if (len < 1e-6) return;
    final ax = d * (1 / len);
    var w = m.webDir - ax * m.webDir.dot(ax);
    if (w.length < 1e-6) {
      w = ax.cross(const Vec3(0, 0, 1));
      if (w.length < 1e-6) w = const Vec3(1, 0, 0);
    }
    w = w.normalized;
    final f = ax.cross(w).normalized;
    final p = m.profile;
    final h = p.h / 1000, b = p.b / 1000, tw = p.tw / 1000, tf = p.tf / 1000;
    // segmentos cortos para un orden de pintado correcto
    final nseg = math.max(1, (len / 1.5).ceil());
    final seg = len / nseg;
    for (var i = 0; i < nseg; i++) {
      final mid = m.a + ax * (seg * (i + 0.5));
      _section(p, mid, ax, f, w, seg, h, b, tw, tf, alb, sp, detailed);
    }
  }

  void _section(SteelProfile p, Vec3 mid, Vec3 ax, Vec3 f, Vec3 w, double len, double h,
      double b, double tw, double tf, Vec3 alb, double sp, bool detailed) {
    switch (p.family) {
      case ProfileFamily.ipe:
      case ProfileFamily.heb:
        if (!detailed) {
          _box(mid, ax, f, w, len, b, h, alb, sp);
          break;
        }
        _box(mid + w * (h / 2 - tf / 2), ax, f, w, len, b, tf, alb, sp);
        _box(mid - w * (h / 2 - tf / 2), ax, f, w, len, b, tf, alb, sp);
        _box(mid, ax, f, w, len, tw, h - 2 * tf, alb, sp);
        break;
      case ProfileFamily.shs:
      case ProfileFamily.rhs:
        _box(mid, ax, f, w, len, b, h, alb, sp);
        break;
      case ProfileFamily.upn:
        if (!detailed) {
          _box(mid, ax, f, w, len, b, h, alb, sp);
          break;
        }
        // alma en un lado, alas hacia el otro
        _box(mid - f * (b / 2 - tw / 2), ax, f, w, len, tw, h, alb, sp);
        _box(mid + w * (h / 2 - tf / 2), ax, f, w, len, b, tf, alb, sp);
        _box(mid - w * (h / 2 - tf / 2), ax, f, w, len, b, tf, alb, sp);
        break;
      case ProfileFamily.angle:
        _box(mid + f * (b / 2 - tw / 2), ax, f, w, len, tw, b, alb, sp);
        _box(mid + w * (b / 2 - tw / 2), ax, f, w, len, b, tw, alb, sp);
        break;
    }
  }

  /// Caja centrada en c con ejes (u: largo, v: ancho, w: alto).
  void _box(Vec3 c, Vec3 u, Vec3 v, Vec3 w, double lu, double lv, double lw,
      Vec3 alb, double sp) {
    final hu = u * (lu / 2), hv = v * (lv / 2), hw = w * (lw / 2);
    Vec3 corner(int i, int j, int k) =>
        c + hu * (i * 2 - 1.0) + hv * (j * 2 - 1.0) + hw * (k * 2 - 1.0);
    final p = [
      for (var i = 0; i < 2; i++)
        for (var j = 0; j < 2; j++)
          for (var k = 0; k < 2; k++) corner(i, j, k)
    ];
    // índices: i*4 + j*2 + k
    void face(int a, int b, int c2, int d) {
      // orienta hacia fuera
      final n = (p[b] - p[a]).cross(p[c2] - p[a]);
      final fc = (p[a] + p[b] + p[c2] + p[d]) * 0.25;
      if (n.dot(fc - c) < 0) {
        tris.add(_Tri(p[a], p[c2], p[b], alb, sp));
        tris.add(_Tri(p[a], p[d], p[c2], alb, sp));
      } else {
        tris.add(_Tri(p[a], p[b], p[c2], alb, sp));
        tris.add(_Tri(p[a], p[c2], p[d], alb, sp));
      }
    }

    face(0, 1, 3, 2); // i=0
    face(4, 5, 7, 6); // i=1
    face(0, 1, 5, 4); // j=0
    face(2, 3, 7, 6); // j=1
    face(0, 2, 6, 4); // k=0
    face(1, 3, 7, 5); // k=1
  }

  void _quad(Vec3 a, Vec3 b, Vec3 c, Vec3 d, Vec3 alb, double sp,
      {double alpha = 1}) {
    // Subdivide en teselas de ~1 m para que el orden de pintado sea correcto
    final nu = math.max(1, ((b - a).length / 1.0).ceil());
    final nv = math.max(1, ((d - a).length / 1.0).ceil());
    Vec3 at(double u, double v) {
      final p1 = a + (b - a) * u;
      final p2 = d + (c - d) * u;
      return p1 + (p2 - p1) * v;
    }

    for (var i = 0; i < nu; i++) {
      for (var j = 0; j < nv; j++) {
        final p00 = at(i / nu, j / nv), p10 = at((i + 1) / nu, j / nv);
        final p11 = at((i + 1) / nu, (j + 1) / nv), p01 = at(i / nu, (j + 1) / nv);
        // ondulación de chapa: leve variación de tono por franjas
        final k = (i % 2 == 0) ? 1.0 : 0.96;
        final al = alb * k;
        tris.add(_Tri(p00, p10, p11, al, sp, alpha: alpha, castsShadow: alpha > 0.7));
        tris.add(_Tri(p00, p11, p01, al, sp, alpha: alpha, castsShadow: alpha > 0.7));
        tris.add(_Tri(p00, p11, p10, al, sp, alpha: alpha, castsShadow: false));
        tris.add(_Tri(p00, p01, p11, al, sp, alpha: alpha, castsShadow: false));
      }
    }
  }

  static (Vec3, double, double) _surfaceLook(SurfaceKind k, String roofing, Vec3 steel) {
    switch (k) {
      case SurfaceKind.roof:
        if (roofing.contains('policarbonato')) return (const Vec3(0.75, 0.82, 0.86), 0.4, 0.45);
        if (roofing.contains('teja')) return (const Vec3(0.55, 0.25, 0.17), 0.1, 1);
        if (roofing.contains('fotovolta')) return (const Vec3(0.08, 0.12, 0.25), 0.6, 1);
        return (const Vec3(0.78, 0.79, 0.80), 0.3, 1);
      case SurfaceKind.floor:
        return (const Vec3(0.45, 0.43, 0.40), 0.2, 0.95);
      case SurfaceKind.grating:
        return (const Vec3(0.58, 0.59, 0.60), 0.3, 0.55);
      case SurfaceKind.panel:
        return (steel * 0.92, 0.3, 1);
      case SurfaceKind.mesh:
        return (steel * 0.85, 0.2, 0.35);
      case SurfaceKind.glass:
        return (const Vec3(0.70, 0.85, 0.88), 0.8, 0.30);
      case SurfaceKind.wall:
        return (const Vec3(0.74, 0.68, 0.60), 0.05, 1);
      case SurfaceKind.wood:
        return (const Vec3(0.62, 0.46, 0.30), 0.05, 1);
    }
  }

  void _roof(Design d) {
    final r = d.spec.roofing;
    if (r.contains('sin cubierta') ||
        (d.spec.type != StructureType.nave && d.spec.type != StructureType.marquesina)) {
      return;
    }
    final x1 = d.frameX.last;
    // cubrir la mitad de la longitud para dejar ver la estructura
    final xr = d.frameX.length > 2 ? d.frameX[(d.frameX.length / 2).floor()] : x1;
    final purl = d.members.where((m) => m.role == MemberRole.purlin).toList();
    final ph = purl.isEmpty ? 0.1 : purl.first.profile.h / 1000;
    final color = r.contains('policarbonato')
        ? const Vec3(0.75, 0.82, 0.86)
        : (r.contains('teja')
            ? const Vec3(0.55, 0.25, 0.17)
            : (r.contains('fotovolta')
                ? const Vec3(0.08, 0.12, 0.25)
                : const Vec3(0.78, 0.79, 0.80)));
    final alpha = r.contains('policarbonato') ? 0.45 : 1.0;
    if (d.spec.type == StructureType.nave) {
      final L = d.gridY.last;
      final H = d.spec.height;
      final rz = d.ridgeHeight;
      final rafter = d.members.firstWhere((m) => m.role == MemberRole.rafter).profile;
      final off = rafter.h / 1000 + ph + 0.02;
      final up = Vec3(0, -(rz - H), L / 2).normalized * off;
      final upR = Vec3(0, (rz - H), L / 2).normalized * off;
      _quad(Vec3(-0.25, -0.3, H - 0.3 * (rz - H) / (L / 2)) + up, Vec3(xr, -0.3, H - 0.3 * (rz - H) / (L / 2)) + up,
          Vec3(xr, L / 2, rz) + up, Vec3(-0.25, L / 2, rz) + up, color, 0.3, alpha: alpha);
      _quad(Vec3(-0.25, L / 2, rz) + upR, Vec3(xr, L / 2, rz) + upR,
          Vec3(xr, L + 0.3, H - 0.3 * (rz - H) / (L / 2)) + upR,
          Vec3(-0.25, L + 0.3, H - 0.3 * (rz - H) / (L / 2)) + upR, color, 0.3, alpha: alpha);
    } else {
      final w = d.gridY.last;
      final H = d.spec.height;
      final drop = d.ridgeHeight - H;
      double z(double y) => H + drop * (1 - y / w) + ph + 0.03;
      _quad(Vec3(-0.15, -0.25, z(-0.25)), Vec3(x1 + 0.15, -0.25, z(-0.25)),
          Vec3(x1 + 0.15, w + 0.25, z(w + 0.25)), Vec3(-0.15, w + 0.25, z(w + 0.25)),
          color, 0.3, alpha: alpha);
    }
  }
}

/// Cámara orbital.
class OrbitCamera {
  double yaw; // rad
  double pitch; // rad
  double distance; // factor sobre el radio
  OrbitCamera({this.yaw = -0.85, this.pitch = 0.32, this.distance = 2.3});
}

/// Pintor del render 3D con iluminación tipo "sol + cielo", sombras
/// proyectadas, especular y niebla atmosférica.
class RenderPainter extends CustomPainter {
  final SceneMesh mesh;
  final OrbitCamera cam;
  final double sunAzimuth;
  final int version;
  RenderPainter(this.mesh, this.cam, {this.sunAzimuth = 0.9, this.version = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final r = mesh.radius;
    final target = mesh.center + Vec3(0, 0, mesh.tall ? 0 : -r * 0.08);
    final eye = target +
        Vec3(math.cos(cam.pitch) * math.cos(cam.yaw), math.cos(cam.pitch) * math.sin(cam.yaw),
                math.sin(cam.pitch)) *
            (r * cam.distance * (mesh.tall ? 1.2 : 1.0));
    final fwd = (target - eye).normalized;
    var right = fwd.cross(const Vec3(0, 0, 1)).normalized;
    final up = right.cross(fwd).normalized;
    final focal = size.height / (2 * math.tan(25 * math.pi / 180));
    final cx = size.width / 2, cy = size.height / 2;

    Offset? project(Vec3 p) {
      final v = p - eye;
      final z = v.dot(fwd);
      if (z < 0.05) return null;
      return Offset(cx + v.dot(right) * focal / z, cy - v.dot(up) * focal / z);
    }

    // Cielo
    final horizonP = project(Vec3(target.x + fwd.x * 1e4, target.y + fwd.y * 1e4, 0));
    final hy = (horizonP?.dy ?? size.height * 0.55).clamp(0.0, size.height);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, hy),
        Paint()
          ..shader = ui.Gradient.linear(Offset.zero, Offset(0, hy), [
            const Color(0xFF5B8FC7),
            const Color(0xFFB9D3EA),
            const Color(0xFFE8EEF2),
          ], [
            0,
            0.75,
            1
          ]));
    // Terreno
    canvas.drawRect(
        Rect.fromLTWH(0, hy, size.width, size.height - hy),
        Paint()
          ..shader = ui.Gradient.linear(Offset(0, hy), Offset(0, size.height), [
            const Color(0xFFBDB8AC),
            const Color(0xFF8E8A80),
          ]));

    final sun = Vec3(math.cos(sunAzimuth) * 0.55, math.sin(sunAzimuth) * 0.55, 0.78).normalized;
    final sunCol = const Vec3(1.0, 0.95, 0.86);
    final skyCol = const Vec3(0.55, 0.65, 0.78);
    final groundCol = const Vec3(0.42, 0.40, 0.36);

    // Solera (losa de hormigón) alrededor de la estructura
    final slab = r * 1.25;
    final sc = [
      Vec3(mesh.center.x - slab, mesh.center.y - slab, 0),
      Vec3(mesh.center.x + slab, mesh.center.y - slab, 0),
      Vec3(mesh.center.x + slab, mesh.center.y + slab, 0),
      Vec3(mesh.center.x - slab, mesh.center.y + slab, 0),
    ].map(project).toList();
    if (sc.every((e) => e != null)) {
      final path = Path()..moveTo(sc[0]!.dx, sc[0]!.dy);
      for (final p in sc.skip(1)) {
        path.lineTo(p!.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = const Color(0xFFA7A49C));
      // juntas de solera
      final jp = Paint()
        ..color = const Color(0x22000000)
        ..strokeWidth = 0.7;
      final step = math.max(2.0, (slab / 6).roundToDouble());
      for (var t = -slab; t <= slab; t += step) {
        final a = project(Vec3(mesh.center.x + t, mesh.center.y - slab, 0));
        final b = project(Vec3(mesh.center.x + t, mesh.center.y + slab, 0));
        final c = project(Vec3(mesh.center.x - slab, mesh.center.y + t, 0));
        final d2 = project(Vec3(mesh.center.x + slab, mesh.center.y + t, 0));
        if (a != null && b != null) canvas.drawLine(a, b, jp);
        if (c != null && d2 != null) canvas.drawLine(c, d2, jp);
      }
    }

    // Sombras proyectadas sobre el suelo (z = 0)
    final shadowPos = <Offset>[];
    for (final t in mesh.tris) {
      if (!t.castsShadow || t.n.dot(sun) <= 0) continue;
      final pts = <Offset>[];
      for (final p in [t.a, t.b, t.c]) {
        final k = p.z / sun.z;
        final g = Vec3(p.x - sun.x * k, p.y - sun.y * k, 0.001);
        final o = project(g);
        if (o == null) break;
        pts.add(o);
      }
      if (pts.length == 3) shadowPos.addAll(pts);
    }
    if (shadowPos.isNotEmpty) {
      canvas.saveLayer(null, Paint()..color = const Color(0x66000000));
      canvas.drawVertices(
          ui.Vertices(ui.VertexMode.triangles, shadowPos),
          BlendMode.srcOver,
          Paint()..color = const Color(0xFF1B1A18));
      canvas.restore();
    }

    // Triángulos visibles ordenados por profundidad (algoritmo del pintor)
    final visible = <(double, _Tri)>[];
    for (final t in mesh.tris) {
      final cen = (t.a + t.b + t.c) * (1 / 3);
      if (t.n.dot(eye - cen) <= 0) continue;
      final z = (cen - eye).dot(fwd);
      if (z < 0.1) continue;
      visible.add((z, t));
    }
    visible.sort((a, b) => b.$1.compareTo(a.$1));

    final pos = <Offset>[];
    final cols = <Color>[];
    final pos2 = <Offset>[];
    final cols2 = <Color>[];
    void flush() {
      if (pos.isEmpty) return;
      canvas.drawVertices(ui.Vertices(ui.VertexMode.triangles, List.of(pos), colors: List.of(cols)),
          BlendMode.dst, Paint());
      pos.clear();
      cols.clear();
    }

    for (final (z, t) in visible) {
      final pa = project(t.a), pb = project(t.b), pc = project(t.c);
      if (pa == null || pb == null || pc == null) continue;
      final n = t.n;
      final ndl = math.max(0.0, n.dot(sun));
      final cen = (t.a + t.b + t.c) * (1 / 3);
      final vdir = (eye - cen).normalized;
      final hlf = (sun + vdir).normalized;
      final spec = math.pow(math.max(0.0, n.dot(hlf)), 40) * t.spec;
      final hemi = 0.5 + 0.5 * n.z;
      final amb = skyCol * hemi + groundCol * (1 - hemi);
      // ambient occlusion aproximada cerca del suelo
      final ao = 0.75 + 0.25 * math.min(1.0, cen.z / 1.5);
      final fres = math.pow(1 - math.max(0.0, n.dot(vdir)), 4) * 0.25;
      var c = Vec3(
          t.albedo.x * (sunCol.x * ndl * 1.05 + amb.x * 0.55 * ao) + spec + fres * skyCol.x,
          t.albedo.y * (sunCol.y * ndl * 1.05 + amb.y * 0.55 * ao) + spec + fres * skyCol.y,
          t.albedo.z * (sunCol.z * ndl * 1.05 + amb.z * 0.55 * ao) + spec + fres * skyCol.z);
      // niebla atmosférica
      final fog = (1 - math.exp(-z / (r * 9))).clamp(0.0, 0.5);
      c = c * (1 - fog) + const Vec3(0.85, 0.89, 0.93) * fog;
      // tonemapping suave + gamma
      Color toColor(Vec3 v, double a) {
        int ch(double x) {
          final m = x / (1 + x * 0.35);
          return (math.pow(m.clamp(0.0, 1.0), 1 / 1.15) * 255).round();
        }

        return Color.fromARGB((a * 255).round(), ch(v.x), ch(v.y), ch(v.z));
      }

      final col = toColor(c, t.alpha);
      if (t.alpha < 1) {
        pos2.addAll([pa, pb, pc]);
        cols2.addAll([col, col, col]);
        continue;
      }
      pos.addAll([pa, pb, pc]);
      cols.addAll([col, col, col]);
      if (pos.length > 30000) flush();
    }
    flush();
    if (pos2.isNotEmpty) {
      canvas.drawVertices(ui.Vertices(ui.VertexMode.triangles, pos2, colors: cols2),
          BlendMode.dst, Paint());
    }
    // viñeteado
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = ui.Gradient.radial(Offset(cx, cy), size.longestSide * 0.75,
              [const Color(0x00000000), const Color(0x40000000)], [0.6, 1]));
  }

  @override
  bool shouldRepaint(covariant RenderPainter old) => true;
}

/// Convierte una imagen a bytes RGBA.
Future<Uint8List?> imageRgba(ui.Image img) async {
  final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  return bd?.buffer.asUint8List();
}
