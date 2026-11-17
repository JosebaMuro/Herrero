import 'dart:math' as math;
import 'dart:typed_data';

import 'cad.dart';

/// Escritor DXF R12 (AC1009), el formato más compatible: AutoCAD, BricsCAD,
/// DraftSight, LibreCAD, QCAD y SketchUp Pro lo abren directamente.
///
/// - [sheetsDxf]: láminas 2D a tamaño real en mm (cada lámina se dibuja en el
///   espacio modelo multiplicada por su escala, una al lado de otra).
/// - [modelDxf]: modelo 3D con caras 3DFACE por capas (en mm).
class DxfWriter {
  double _x0 = 1e18, _y0 = 1e18, _z0 = 1e18, _x1 = -1e18, _y1 = -1e18, _z1 = -1e18;
  final _ents = StringBuffer();
  final Set<String> _linetypes = {};
  final Map<String, (int, String)> _layers = {}; // nombre -> (color, tipo de línea)

  void _g(StringBuffer b, int code, Object v) {
    b
      ..write(code)
      ..write('\r\n')
      ..write(v is double ? _num(v) : v)
      ..write('\r\n');
  }

  static String _num(double v) {
    if (v.isNaN || v.isInfinite) return '0.0';
    final s = v.toStringAsFixed(4);
    return s.contains('.') ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '.0') : s;
  }

  void _ext(double x, double y, [double z = 0]) {
    _x0 = math.min(_x0, x);
    _y0 = math.min(_y0, y);
    _z0 = math.min(_z0, z);
    _x1 = math.max(_x1, x);
    _y1 = math.max(_y1, y);
    _z1 = math.max(_z1, z);
  }

  void layer(String name, int color, [String lt = 'CONTINUOUS']) {
    _layers.putIfAbsent(name, () => (color, lt));
    _linetypes.add(lt);
  }

  void _common(String type, String layer, {String? lt}) {
    _g(_ents, 0, type);
    _g(_ents, 8, layer);
    if (lt != null) {
      _g(_ents, 6, lt);
      _linetypes.add(lt);
    }
  }

  void line(double x1, double y1, double x2, double y2, String layer, {String? lt, double z1 = 0, double z2 = 0}) {
    _common('LINE', layer, lt: lt);
    _g(_ents, 10, x1);
    _g(_ents, 20, y1);
    _g(_ents, 30, z1);
    _g(_ents, 11, x2);
    _g(_ents, 21, y2);
    _g(_ents, 31, z2);
    _ext(x1, y1, z1);
    _ext(x2, y2, z2);
  }

  void circle(double cx, double cy, double r, String layer) {
    _common('CIRCLE', layer);
    _g(_ents, 10, cx);
    _g(_ents, 20, cy);
    _g(_ents, 30, 0.0);
    _g(_ents, 40, r);
    _ext(cx - r, cy - r);
    _ext(cx + r, cy + r);
  }

  /// SOLID (relleno de 3 o 4 vértices). DXF ordena 1, 2, 4, 3.
  void solid(List<double> p, String layer) {
    _common('SOLID', layer);
    final n = p.length ~/ 2;
    final idx = n == 3 ? [0, 1, 2, 2] : [0, 1, 3, 2];
    for (var i = 0; i < 4; i++) {
      final k = idx[i];
      _g(_ents, 10 + i, p[k * 2]);
      _g(_ents, 20 + i, p[k * 2 + 1]);
      _g(_ents, 30 + i, 0.0);
      _ext(p[k * 2], p[k * 2 + 1]);
    }
  }

  void polyline(List<double> p, String layer, {bool closed = false, String? lt}) {
    _common('POLYLINE', layer, lt: lt);
    _g(_ents, 66, 1);
    _g(_ents, 10, 0.0);
    _g(_ents, 20, 0.0);
    _g(_ents, 30, 0.0);
    _g(_ents, 70, closed ? 1 : 0);
    for (var i = 0; i + 1 < p.length; i += 2) {
      _g(_ents, 0, 'VERTEX');
      _g(_ents, 8, layer);
      _g(_ents, 10, p[i]);
      _g(_ents, 20, p[i + 1]);
      _g(_ents, 30, 0.0);
      _ext(p[i], p[i + 1]);
    }
    _g(_ents, 0, 'SEQEND');
    _g(_ents, 8, layer);
  }

  /// Texto. [h] altura; alineación h: -1/0/1, v: -1 (base) / 0 (medio) / 1 (arriba).
  void text(double x, double y, String t, double h, String layer, {double angle = 0, int hAlign = -1, int vAlign = -1}) {
    _common('TEXT', layer);
    _g(_ents, 10, x);
    _g(_ents, 20, y);
    _g(_ents, 30, 0.0);
    _g(_ents, 40, h);
    _g(_ents, 1, _enc(t));
    if (angle != 0) _g(_ents, 50, angle);
    _g(_ents, 7, 'HERRERO');
    final ha = hAlign + 1, va = vAlign == -1 ? 0 : (vAlign == 0 ? 2 : 3);
    if (ha != 0) _g(_ents, 72, ha);
    if (ha != 0 || va != 0) {
      _g(_ents, 11, x);
      _g(_ents, 21, y);
      _g(_ents, 31, 0.0);
    }
    if (va != 0) _g(_ents, 73, va);
    _ext(x, y);
  }

  void face3d(double ax, double ay, double az, double bx, double by, double bz, double cx, double cy, double cz,
      String layer, {int? color}) {
    _common('3DFACE', layer);
    if (color != null) _g(_ents, 62, color);
    final pts = [ax, ay, az, bx, by, bz, cx, cy, cz, cx, cy, cz];
    for (var i = 0; i < 4; i++) {
      _g(_ents, 10 + i, pts[i * 3]);
      _g(_ents, 20 + i, pts[i * 3 + 1]);
      _g(_ents, 30 + i, pts[i * 3 + 2]);
      _ext(pts[i * 3], pts[i * 3 + 1], pts[i * 3 + 2]);
    }
  }

  /// Texto en página de códigos Windows-1252 ($DWGCODEPAGE ANSI_1252);
  /// lo que no cabe se escribe con la secuencia \U+XXXX de AutoCAD.
  static String _enc(String t) {
    final sb = StringBuffer();
    for (final r in t.runes) {
      if (r < 128 || (r >= 0xA0 && r <= 0xFF)) {
        sb.writeCharCode(r);
      } else if (r == 0x2013 || r == 0x2014 || r == 0x2212) {
        sb.write('-');
      } else if (r == 0x2026) {
        sb.write('...');
      } else {
        sb.write('\\U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')}');
      }
    }
    return sb.toString();
  }

  /// Documento completo en bytes (Windows-1252).
  Uint8List build({double ltScale = 1}) {
    final h = StringBuffer();
    if (_x0 > _x1) _ext(0, 0);
    _g(h, 0, 'SECTION');
    _g(h, 2, 'HEADER');
    _g(h, 9, r'$ACADVER');
    _g(h, 1, 'AC1009');
    _g(h, 9, r'$DWGCODEPAGE');
    _g(h, 3, 'ANSI_1252');
    _g(h, 9, r'$INSBASE');
    _g(h, 10, 0.0);
    _g(h, 20, 0.0);
    _g(h, 30, 0.0);
    _g(h, 9, r'$EXTMIN');
    _g(h, 10, _x0);
    _g(h, 20, _y0);
    _g(h, 30, _z0);
    _g(h, 9, r'$EXTMAX');
    _g(h, 10, _x1);
    _g(h, 20, _y1);
    _g(h, 30, _z1);
    _g(h, 9, r'$LIMMIN');
    _g(h, 10, _x0);
    _g(h, 20, _y0);
    _g(h, 9, r'$LIMMAX');
    _g(h, 10, _x1);
    _g(h, 20, _y1);
    _g(h, 9, r'$LTSCALE');
    _g(h, 40, ltScale);
    _g(h, 9, r'$MEASUREMENT');
    _g(h, 70, 1);
    _g(h, 9, r'$TEXTSTYLE');
    _g(h, 7, 'HERRERO');
    _g(h, 0, 'ENDSEC');

    // ---- Tablas ----
    _g(h, 0, 'SECTION');
    _g(h, 2, 'TABLES');
    // VPORT activo encuadrando el dibujo
    _g(h, 0, 'TABLE');
    _g(h, 2, 'VPORT');
    _g(h, 70, 1);
    _g(h, 0, 'VPORT');
    _g(h, 2, '*ACTIVE');
    _g(h, 70, 0);
    _g(h, 10, 0.0);
    _g(h, 20, 0.0);
    _g(h, 11, 1.0);
    _g(h, 21, 1.0);
    _g(h, 12, (_x0 + _x1) / 2);
    _g(h, 22, (_y0 + _y1) / 2);
    _g(h, 40, math.max(_y1 - _y0, (_x1 - _x0) / 1.6) * 1.05);
    _g(h, 41, 1.6);
    _g(h, 0, 'ENDTAB');
    // tipos de línea
    final lts = {'CONTINUOUS', ..._linetypes};
    _g(h, 0, 'TABLE');
    _g(h, 2, 'LTYPE');
    _g(h, 70, lts.length);
    for (final name in lts) {
      final (desc, pat) = _ltPattern(name);
      _g(h, 0, 'LTYPE');
      _g(h, 2, name);
      _g(h, 70, 0);
      _g(h, 3, desc);
      _g(h, 72, 65);
      _g(h, 73, pat.length);
      _g(h, 40, pat.fold<double>(0, (a, b) => a + b.abs()));
      for (final e in pat) {
        _g(h, 49, e);
      }
    }
    _g(h, 0, 'ENDTAB');
    // capas
    _g(h, 0, 'TABLE');
    _g(h, 2, 'LAYER');
    _g(h, 70, _layers.length + 1);
    _g(h, 0, 'LAYER');
    _g(h, 2, '0');
    _g(h, 70, 0);
    _g(h, 62, 7);
    _g(h, 6, 'CONTINUOUS');
    for (final e in _layers.entries) {
      _g(h, 0, 'LAYER');
      _g(h, 2, e.key);
      _g(h, 70, 0);
      _g(h, 62, e.value.$1);
      _g(h, 6, e.value.$2);
    }
    _g(h, 0, 'ENDTAB');
    // estilo de texto
    _g(h, 0, 'TABLE');
    _g(h, 2, 'STYLE');
    _g(h, 70, 1);
    _g(h, 0, 'STYLE');
    _g(h, 2, 'HERRERO');
    _g(h, 70, 0);
    _g(h, 40, 0.0);
    _g(h, 41, 0.9);
    _g(h, 50, 0.0);
    _g(h, 71, 0);
    _g(h, 42, 2.5);
    _g(h, 3, 'isocp.shx');
    _g(h, 4, '');
    _g(h, 0, 'ENDTAB');
    _g(h, 0, 'ENDSEC');

    _g(h, 0, 'SECTION');
    _g(h, 2, 'ENTITIES');
    h.write(_ents);
    _g(h, 0, 'ENDSEC');
    _g(h, 0, 'EOF');
    final s = h.toString();
    final out = Uint8List(s.length);
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      out[i] = c < 256 ? c : 63;
    }
    return out;
  }

  /// Patrón de un tipo de línea por nombre (EJE_100 = eje a escala 1:100).
  static (String, List<double>) _ltPattern(String name) {
    if (name == 'CONTINUOUS') return ('Solid line', const []);
    final m = RegExp(r'^(EJE|TRAZOS)_(\d+)$').firstMatch(name);
    final base = m?[1] ?? name;
    final sc = m == null ? 1.0 : double.parse(m[2]!);
    final lt = base == 'EJE' ? CadLinetype.center : CadLinetype.dashed;
    // en R12: positivo trazo, negativo hueco, 0 punto
    return (lt.description, [for (final v in lt.pattern) v * sc]);
  }
}

/// Exporta las láminas a un DXF 2D a tamaño real (mm).
Uint8List sheetsDxf(List<CadSheet> sheets) {
  final w = DxfWriter();
  for (final l in CadLayer.values) {
    w.layer(l.dxf, l.aci, l.linetype == CadLinetype.continuous ? 'CONTINUOUS' : '${l.linetype.dxf}_1');
  }
  var ox = 0.0;
  for (final s in sheets) {
    final k = s.scale <= 0 ? 1.0 : s.scale.toDouble();
    String? lt(CadLayer l) => l.linetype == CadLinetype.continuous ? null : '${l.linetype.dxf}_${k.round()}';
    double x(double v) => ox + v * k;
    double y(double v) => v * k;
    for (final e in s.ents) {
      switch (e) {
        case CLine():
          w.line(x(e.x1), y(e.y1), x(e.x2), y(e.y2), e.layer.dxf, lt: lt(e.layer));
        case CPoly():
          final pts = [for (var i = 0; i + 1 < e.pts.length; i += 2) ...[x(e.pts[i]), y(e.pts[i + 1])]];
          if (e.fill && (pts.length == 6 || pts.length == 8)) {
            w.solid(pts, e.layer.dxf);
          } else if (e.fill) {
            // abanico de triángulos
            for (var i = 2; i + 3 < pts.length; i += 2) {
              w.solid([pts[0], pts[1], pts[i], pts[i + 1], pts[i + 2], pts[i + 3]], e.layer.dxf);
            }
          } else {
            w.polyline(pts, e.layer.dxf, closed: e.closed, lt: lt(e.layer));
          }
        case CCircle():
          w.circle(x(e.cx), y(e.cy), e.r * k, e.layer.dxf);
          if (e.fill) {
            // relleno aproximado con un polígono de 12 lados
            for (var i = 0; i < 12; i++) {
              final a0 = i * math.pi / 6, a1 = (i + 1) * math.pi / 6;
              w.solid([
                x(e.cx), y(e.cy),
                x(e.cx + e.r * math.cos(a0)), y(e.cy + e.r * math.sin(a0)),
                x(e.cx + e.r * math.cos(a1)), y(e.cy + e.r * math.sin(a1)),
              ], e.layer.dxf);
            }
          }
        case CText():
          w.text(x(e.x), y(e.y), e.text, e.h * k, e.layer.dxf, angle: e.angle, hAlign: e.hAlign, vAlign: e.vAlign);
      }
    }
    // separación entre láminas: 10 % del ancho
    ox += s.width * k * 1.1;
  }
  return w.build();
}

/// Grupo de triángulos del modelo 3D (en metros) con su capa y color.
class MeshGroup {
  final String name; // p.ej. "P1 Pilar IPE 360"
  final String layer; // p.ej. "PILARES"
  final List<double> tris; // x,y,z × 3 por triángulo (m)
  final double r, g, b, alpha;
  const MeshGroup(this.name, this.layer, this.tris, this.r, this.g, this.b, {this.alpha = 1});
}

/// Exporta el modelo 3D a DXF (3DFACE en mm, una capa por tipo de pieza).
Uint8List modelDxf(List<MeshGroup> groups) {
  final w = DxfWriter();
  for (final g in groups) {
    w.layer(g.layer, _aci(g.r, g.g, g.b));
  }
  for (final g in groups) {
    final t = g.tris;
    for (var i = 0; i + 8 < t.length; i += 9) {
      w.face3d(t[i] * 1000, t[i + 1] * 1000, t[i + 2] * 1000, t[i + 3] * 1000, t[i + 4] * 1000, t[i + 5] * 1000,
          t[i + 6] * 1000, t[i + 7] * 1000, t[i + 8] * 1000, g.layer);
    }
  }
  return w.build();
}

/// Color AutoCAD (ACI) aproximado a un RGB.
int _aci(double r, double g, double b) {
  const pal = <int, List<double>>{
    1: [1, 0, 0], 2: [1, 1, 0], 3: [0, 1, 0], 4: [0, 1, 1], 5: [0, 0, 1], 6: [1, 0, 1], 7: [1, 1, 1],
    8: [0.5, 0.5, 0.5], 9: [0.75, 0.75, 0.75], 30: [1, 0.5, 0], 33: [0.5, 0.25, 0.1], 150: [0.3, 0.6, 1],
    251: [0.31, 0.31, 0.31], 253: [0.6, 0.6, 0.6],
  };
  var best = 7;
  var bd = 1e9;
  for (final e in pal.entries) {
    final d = math.pow(e.value[0] - r, 2) + math.pow(e.value[1] - g, 2) + math.pow(e.value[2] - b, 2);
    if (d < bd) {
      bd = d.toDouble();
      best = e.key;
    }
  }
  return best;
}
