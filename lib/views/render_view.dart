import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../engine/model.dart';
import '../engine/profiles.dart';
import '../cad/dxf.dart' show MeshGroup;
import 'zbuffer.dart';

export 'zbuffer.dart' show ZScene, ZView, renderZ;

/// Acabado del acero en el render.
enum Finish { galvanizado, pintadoGris, pintadoRojo, corten, negro, blanco, inox, aluminio }

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
      case Finish.blanco:
        return 'Lacado blanco';
      case Finish.inox:
        return 'Inox satinado';
      case Finish.aluminio:
        return 'Aluminio anodizado';
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
      case Finish.blanco:
        return const Vec3(0.86, 0.86, 0.84);
      case Finish.inox:
        return const Vec3(0.74, 0.75, 0.76);
      case Finish.aluminio:
        return const Vec3(0.80, 0.81, 0.83);
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
      case Finish.blanco:
        return 0.35;
      case Finish.inox:
        return 0.8;
      case Finish.aluminio:
        return 0.6;
    }
  }
}

Finish finishFromSpec(String f) {
  f = f.toLowerCase();
  if (f.contains('negro')) return Finish.negro;
  if (f.contains('blanco')) return Finish.blanco;
  if (f.contains('inox')) return Finish.inox;
  if (f.contains('alumin') || f.contains('anodiz')) return Finish.aluminio;
  if (f.contains('galvan')) return Finish.galvanizado;
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
  final int pattern;
  _Tri(this.a, this.b, this.c, this.albedo, this.spec,
      {this.alpha = 1, this.castsShadow = true, this.pattern = ZPattern.none})
      : n = (b - a).cross(c - a).normalized;
}

/// Malla 3D de la estructura (perfiles reales extruidos, placas, zapatas y
/// cubierta opcional).
class SceneMesh {
  final List<_Tri> _tris = [];
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
    s._footings(d, alb, sp, concrete: true, plates: true);
    s._envelope(d, alb, roof);
    return s;
  }

  void _footings(Design d, Vec3 alb, double sp, {bool concrete = true, bool plates = true}) {
      // Zapatas y placas
      final fs = d.footingSize > 0 ? d.footingSize : 0.0;
      final col = d.members
          .firstWhere((m) => m.role == MemberRole.column || m.role == MemberRole.post,
              orElse: () => d.members.first)
          .profile;
      final pw = d.plates.isNotEmpty ? d.plates.first.w / 1000 : 0.3;
      final ph = d.plates.isNotEmpty ? d.plates.first.h / 1000 : 0.3;
      for (final f in d.footings) {
        if (fs > 0 && concrete) {
          _box(f + Vec3(0, 0, -0.02), const Vec3(1, 0, 0), const Vec3(0, 1, 0),
              const Vec3(0, 0, 1), fs, fs, 0.08, const Vec3(0.62, 0.61, 0.58), 0.05);
        }
        if (!plates) continue;
        final horiz = col.family != ProfileFamily.shs;
        _box(f + const Vec3(0, 0, 0.06), const Vec3(1, 0, 0), const Vec3(0, 1, 0),
            const Vec3(0, 0, 1), horiz ? pw : pw, horiz ? ph : pw, 0.02, alb, sp);
      }
  }

  /// Cubierta, suelos y cerramientos. [full] cubre toda la planta (para
  /// exportar); en pantalla se deja media cubierta para ver la estructura.
  /// [flush] recibe el nombre de cada bloque al terminarlo.
  void _envelope(Design d, Vec3 alb, bool roof,
      {bool full = false, void Function(String name, String layer)? flush}) {
      if (roof) _roof(d, full: full);
      flush?.call('Cubierta', 'CUBIERTA');
      for (final k in SurfaceKind.values) {
        for (final sf in d.surfaces) {
          if (sf.kind != k || (!roof && sf.kind == SurfaceKind.roof)) continue;
          final (c, sp2, a, pat) = _surfaceLook(sf.kind, d.spec.roofing, alb);
          _quad(sf.a, sf.b, sf.c, sf.d, c, sp2, alpha: a, pattern: pat);
        }
        flush?.call(_surfaceName[k]!, _surfaceLayer[k]!);
      }
      // Suelo de entreplanta
      if (d.spec.type == StructureType.entreplanta) {
        final x1 = d.frameX.last, y1 = d.gridY.last, z = d.spec.height;
        final (c, sp2, a, pat) = _surfaceLook(SurfaceKind.floor, d.spec.roofing, alb);
        _quad(Vec3(0, 0, z + 0.01), Vec3(x1, 0, z + 0.01), Vec3(x1, y1, z + 0.01), Vec3(0, y1, z + 0.01), c, sp2,
            alpha: a, pattern: pat);
        flush?.call('Forjado', 'FORJADO');
      }
      // Cerramiento lateral de la nave: fachada trasera y hastial izquierdo
      // (el resto se deja abierto para ver la estructura).
      if (d.spec.cladding.isNotEmpty && d.spec.type == StructureType.nave && d.gridY.length > 1) {
        final x1 = d.frameX.last, L = d.gridY.last, H = d.spec.height, rz = d.ridgeHeight;
        final cl = d.spec.cladding;
        final (Vec3 c, int pat) = cl.contains('bloque') || cl.contains('ladrillo')
            ? (cl.contains('ladrillo') ? const Vec3(0.62, 0.36, 0.25) : const Vec3(0.70, 0.69, 0.66), ZPattern.concrete)
            : (cl.contains('policarbonato')
                ? (const Vec3(0.75, 0.82, 0.86), ZPattern.none)
                : (cl.contains('sándwich') ? (const Vec3(0.84, 0.85, 0.86), ZPattern.sandwich) : (const Vec3(0.78, 0.79, 0.80), ZPattern.ribbed)));
        final a = cl.contains('policarbonato') ? 0.45 : 1.0;
        final off = 0.12;
        _quad(Vec3(0, L + off, 0), Vec3(x1, L + off, 0), Vec3(x1, L + off, H), Vec3(0, L + off, H), c, 0.25,
            alpha: a, pattern: pat);
        _quad(Vec3(-off, 0, 0), Vec3(-off, L, 0), Vec3(-off, L, H), Vec3(-off, 0, H), c, 0.25, alpha: a, pattern: pat);
        // piñón del hastial
        _tri(Vec3(-off, 0, H), Vec3(-off, L, H), Vec3(-off, L / 2, rz), c, 0.25, alpha: a, pattern: pat);
        flush?.call('Cerramiento', 'CERRAMIENTO');
      }
  }

  static const _surfaceName = {
    SurfaceKind.roof: 'Cubierta',
    SurfaceKind.floor: 'Suelo',
    SurfaceKind.grating: 'Rejilla tramex',
    SurfaceKind.panel: 'Panel',
    SurfaceKind.mesh: 'Malla',
    SurfaceKind.glass: 'Vidrio',
    SurfaceKind.wall: 'Muro',
    SurfaceKind.wood: 'Madera',
  };
  static const _surfaceLayer = {
    SurfaceKind.roof: 'CUBIERTA',
    SurfaceKind.floor: 'SUELO',
    SurfaceKind.grating: 'TRAMEX',
    SurfaceKind.panel: 'PANELES',
    SurfaceKind.mesh: 'MALLA',
    SurfaceKind.glass: 'VIDRIO',
    SurfaceKind.wall: 'MUROS',
    SurfaceKind.wood: 'MADERA',
  };

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
    _section(p, m.a + ax * (len / 2), ax, f, w, len, h, b, tw, tf, alb, sp, detailed);
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
      case ProfileFamily.round:
      case ProfileFamily.chs:
      case ProfileFamily.flat:
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
        _tris.add(_Tri(p[a], p[c2], p[b], alb, sp));
        _tris.add(_Tri(p[a], p[d], p[c2], alb, sp));
      } else {
        _tris.add(_Tri(p[a], p[b], p[c2], alb, sp));
        _tris.add(_Tri(p[a], p[c2], p[d], alb, sp));
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
      {double alpha = 1, int pattern = ZPattern.none}) {
    _tris.add(_Tri(a, b, c, alb, sp, alpha: alpha, castsShadow: alpha > 0.7, pattern: pattern));
    _tris.add(_Tri(a, c, d, alb, sp, alpha: alpha, castsShadow: alpha > 0.7, pattern: pattern));
  }

  void _tri(Vec3 a, Vec3 b, Vec3 c, Vec3 alb, double sp, {double alpha = 1, int pattern = ZPattern.none}) {
    _tris.add(_Tri(a, b, c, alb, sp, alpha: alpha, castsShadow: alpha > 0.7, pattern: pattern));
  }

  /// Modelo por piezas para exportar (DXF 3D y SketchUp): un grupo por
  /// barra, placas, zapatas y cada tipo de cerramiento, en metros.
  static List<MeshGroup> groups(Design d, Finish finish) {
    final s = SceneMesh._(const Vec3(0, 0, 0), 1, false);
    final out = <MeshGroup>[];
    void flush(String name, String layer) {
      if (s._tris.isEmpty) return;
      final t0 = s._tris.first;
      final xyz = <double>[];
      for (final t in s._tris) {
        xyz.addAll([t.a.x, t.a.y, t.a.z, t.b.x, t.b.y, t.b.z, t.c.x, t.c.y, t.c.z]);
      }
      out.add(MeshGroup(name, layer, xyz, t0.albedo.x, t0.albedo.y, t0.albedo.z,
          alpha: t0.alpha));
      s._tris.clear();
    }

    final alb = finish.albedo, sp = finish.specular;
    for (final m in d.members) {
      s._member(m, alb, sp, true);
      final mk = m.mark.isEmpty ? '' : '${m.mark} ';
      flush('$mk${m.role.label} ${m.profile.name}', _roleLayer(m.role));
    }
    s._footings(d, alb, sp, concrete: false, plates: true);
    flush('Placas de anclaje', 'PLACAS');
    s._footings(d, alb, sp, concrete: true, plates: false);
    flush('Cimentación', 'CIMENTACION');
    s._envelope(d, alb, true, full: true, flush: flush);
    flush('Otros', 'OTROS');
    return out;
  }

  static String _roleLayer(MemberRole r) => switch (r) {
        MemberRole.column => 'PILARES',
        MemberRole.rafter => 'DINTELES',
        MemberRole.purlin => 'CORREAS',
        MemberRole.beam => 'VIGAS',
        MemberRole.joist => 'VIGUETAS',
        MemberRole.tie => 'ATADOS',
        MemberRole.brace => 'ARRIOSTRAMIENTO',
        MemberRole.post => 'MONTANTES',
        MemberRole.handrail => 'PASAMANOS',
        MemberRole.gablePost => 'PILARILLOS',
        MemberRole.haunch => 'CARTELAS',
        MemberRole.baluster => 'BARROTES',
        MemberRole.stringer => 'ZANCAS',
        MemberRole.tread => 'PELDANOS',
        MemberRole.chordTop || MemberRole.chordBottom => 'CORDONES',
        MemberRole.diagonal => 'DIAGONALES',
        MemberRole.strut => 'MONTANTES_CERCHA',
        MemberRole.frame => 'BASTIDOR',
        MemberRole.rail => 'LARGUEROS',
        MemberRole.bracket => 'SOPORTES',
      };

  /// Empaqueta la malla para el rasterizador (listas tipadas, apto para isolate).
  ZScene pack() {
    final data = Float32List(_tris.length * zStride);
    var o = 0;
    for (final t in _tris) {
      data
        ..[o] = t.a.x
        ..[o + 1] = t.a.y
        ..[o + 2] = t.a.z
        ..[o + 3] = t.b.x
        ..[o + 4] = t.b.y
        ..[o + 5] = t.b.z
        ..[o + 6] = t.c.x
        ..[o + 7] = t.c.y
        ..[o + 8] = t.c.z
        ..[o + 9] = t.n.x
        ..[o + 10] = t.n.y
        ..[o + 11] = t.n.z
        ..[o + 12] = t.albedo.x
        ..[o + 13] = t.albedo.y
        ..[o + 14] = t.albedo.z
        ..[o + 15] = t.spec
        ..[o + 16] = t.alpha
        ..[o + 17] = t.pattern.toDouble()
        ..[o + 18] = t.castsShadow ? 1 : 0;
      o += zStride;
    }
    return ZScene(data, _tris.length, center.x, center.y, center.z, radius, tall);
  }

  /// Color, especular, alfa y patrón de cada tipo de superficie. Solo el
  /// policarbonato, el vidrio y la malla dejan ver a través.
  static (Vec3, double, double, int) _surfaceLook(SurfaceKind k, String roofing, Vec3 steel) {
    switch (k) {
      case SurfaceKind.roof:
        return _roofLook(roofing);
      case SurfaceKind.floor:
        if (roofing.contains('tramex')) return (const Vec3(0.58, 0.59, 0.60), 0.3, 1, ZPattern.grating);
        if (roofing.contains('lagrimada')) return (steel * 0.95, 0.35, 1, ZPattern.checker);
        if (roofing.contains('tablero') || roofing.contains('madera')) {
          return (const Vec3(0.62, 0.46, 0.30), 0.05, 1, ZPattern.wood);
        }
        if (roofing.contains('colaborante') || roofing.contains('hormig')) {
          return (const Vec3(0.66, 0.65, 0.62), 0.05, 1, ZPattern.concrete);
        }
        return (const Vec3(0.45, 0.43, 0.40), 0.2, 1, ZPattern.none);
      case SurfaceKind.grating:
        return (const Vec3(0.58, 0.59, 0.60), 0.3, 1, ZPattern.grating);
      case SurfaceKind.panel:
        return (steel * 0.92, 0.3, 1, ZPattern.none);
      case SurfaceKind.mesh:
        return (steel * 0.85, 0.2, 0.35, ZPattern.none);
      case SurfaceKind.glass:
        return (const Vec3(0.70, 0.85, 0.88), 0.8, 0.30, ZPattern.none);
      case SurfaceKind.wall:
        return (const Vec3(0.74, 0.68, 0.60), 0.05, 1, ZPattern.concrete);
      case SurfaceKind.wood:
        return (const Vec3(0.62, 0.46, 0.30), 0.05, 1, ZPattern.wood);
    }
  }

  static (Vec3, double, double, int) _roofLook(String r) {
    if (r.contains('policarbonato')) return (const Vec3(0.75, 0.82, 0.86), 0.4, 0.45, ZPattern.none);
    if (r.contains('vidrio')) return (const Vec3(0.70, 0.85, 0.88), 0.8, 0.30, ZPattern.none);
    if (r.contains('teja')) return (const Vec3(0.55, 0.25, 0.17), 0.1, 1, ZPattern.tile);
    if (r.contains('fotovolta')) return (const Vec3(0.08, 0.12, 0.25), 0.6, 1, ZPattern.solar);
    if (r.contains('sándwich') || r.contains('sandwich')) return (const Vec3(0.84, 0.85, 0.86), 0.3, 1, ZPattern.sandwich);
    if (r.contains('fibrocemento')) return (const Vec3(0.70, 0.70, 0.68), 0.05, 1, ZPattern.ribbed);
    return (const Vec3(0.78, 0.79, 0.80), 0.3, 1, ZPattern.ribbed);
  }

  void _roof(Design d, {bool full = false}) {
    final r = d.spec.roofing;
    if (r.contains('sin cubierta') ||
        (d.spec.type != StructureType.nave && d.spec.type != StructureType.marquesina)) {
      return;
    }
    final x1 = d.frameX.last;
    // cubrir la mitad de la longitud para dejar ver la estructura
    final xr = full ? x1 + 0.25 : (d.frameX.length > 2 ? d.frameX[(d.frameX.length / 2).floor()] : x1);
    final purl = d.members.where((m) => m.role == MemberRole.purlin).toList();
    final ph = purl.isEmpty ? 0.1 : purl.first.profile.h / 1000;
    final (color, _, alpha, pat) = _roofLook(r);
    if (d.spec.type == StructureType.nave) {
      final L = d.gridY.last;
      final H = d.spec.height;
      final rz = d.ridgeHeight;
      final rafter = d.members.firstWhere((m) => m.role == MemberRole.rafter).profile;
      final off = rafter.h / 1000 + ph + 0.02;
      final up = Vec3(0, -(rz - H), L / 2).normalized * off;
      final upR = Vec3(0, (rz - H), L / 2).normalized * off;
      _quad(Vec3(-0.25, -0.3, H - 0.3 * (rz - H) / (L / 2)) + up, Vec3(xr, -0.3, H - 0.3 * (rz - H) / (L / 2)) + up,
          Vec3(xr, L / 2, rz) + up, Vec3(-0.25, L / 2, rz) + up, color, 0.3, alpha: alpha, pattern: pat);
      _quad(Vec3(-0.25, L / 2, rz) + upR, Vec3(xr, L / 2, rz) + upR,
          Vec3(xr, L + 0.3, H - 0.3 * (rz - H) / (L / 2)) + upR,
          Vec3(-0.25, L + 0.3, H - 0.3 * (rz - H) / (L / 2)) + upR, color, 0.3, alpha: alpha, pattern: pat);
    } else {
      final w = d.gridY.last;
      final H = d.spec.height;
      final drop = d.ridgeHeight - H;
      double z(double y) => H + drop * (1 - y / w) + ph + 0.03;
      _quad(Vec3(-0.15, -0.25, z(-0.25)), Vec3(x1 + 0.15, -0.25, z(-0.25)),
          Vec3(x1 + 0.15, w + 0.25, z(w + 0.25)), Vec3(-0.15, w + 0.25, z(w + 0.25)),
          color, 0.3, alpha: alpha, pattern: pat);
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

/// Convierte una imagen a bytes RGBA.
Future<Uint8List?> imageRgba(ui.Image img) async {
  final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  return bd?.buffer.asUint8List();
}

/// Parámetros de vista del rasterizador a partir de la cámara orbital.
ZView zViewFor(OrbitCamera cam, int w, int h, {double sun = 0.9, int ss = 1, bool fast = false}) => ZView(
      width: w,
      height: h,
      ss: ss,
      yaw: cam.yaw,
      pitch: cam.pitch,
      distance: cam.distance,
      sunAzimuth: sun,
      shadowRes: fast ? 768 : 1536,
      softShadows: !fast,
    );

/// Convierte píxeles RGBA en una imagen.
Future<ui.Image> rgbaToImage(Uint8List px, int w, int h) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

/// Renderiza la escena con z-buffer en un isolate (no bloquea la interfaz).
Future<Uint8List> renderRgba(ZScene scene, ZView view) => Isolate.run(() => renderZ(scene, view));

/// Render de alta calidad listo para PDF o IA: devuelve (RGBA, imagen).
Future<(Uint8List, ui.Image)> renderHq(Design d, Finish finish, OrbitCamera cam,
    {int width = 1200, int height = 800, int ss = 2, double sun = 0.9, bool roof = true}) async {
  final scene = SceneMesh.build(d, finish, roof: roof).pack();
  final px = await renderRgba(scene, zViewFor(cam, width, height, sun: sun, ss: ss));
  return (px, await rgbaToImage(px, width, height));
}
