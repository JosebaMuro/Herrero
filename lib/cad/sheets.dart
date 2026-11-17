import 'dart:math' as math;

import '../engine/model.dart';
import '../engine/profiles.dart';
import 'cad.dart';

/// Genera el juego de planos tipo CAD (láminas A3) de un diseño.
List<CadSheet> buildSheets(Design d) {
  final out = <CadSheet>[
    _foundationPlan(d),
    _structurePlan(d),
    _elevation(d, front: true),
    _elevation(d, front: false),
    _details(d),
    ..._schedules(d),
  ];
  for (var i = 0; i < out.length; i++) {
    _frame(out[i], d, i + 1, out.length);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Formato: A3 horizontal, margen de encuadernación 20 mm, cajetín ISO 7200
// ---------------------------------------------------------------------------

const double _fx0 = 20, _fy0 = 10, _fx1 = 410, _fy1 = 287; // recuadro
const double _tbW = 180, _tbH = 56; // cajetín
// zona de dibujo principal
const double _ax0 = 28, _ay0 = _fy0 + _tbH + 8, _ax1 = 402, _ay1 = 278;

String _mm(double m) => (m * 1000).round().toString();
String _m2(double m) => m.toStringAsFixed(2).replaceAll('.', ',');

void _frame(CadSheet s, Design d, int n, int total) {
  // recuadro y marcas de centrado
  s.rect(_fx0, _fy0, _fx1, _fy1, CadLayer.marco);
  s.line(5, s.height / 2, _fx0, s.height / 2, CadLayer.marco);
  s.line(s.width / 2, _fy1, s.width / 2, s.height - 2, CadLayer.marco);
  s.line(s.width / 2, 2, s.width / 2, _fy0, CadLayer.marco);
  s.line(_fx1, s.height / 2, s.width - 2, s.height / 2, CadLayer.marco);

  // cajetín
  final x0 = _fx1 - _tbW, y0 = _fy0, x1 = _fx1, y1 = _fy0 + _tbH;
  s.rect(x0, y0, x1, y1, CadLayer.marco);
  final rows = [y1 - 8, y1 - 24, y1 - 34, y1 - 44]; // líneas horizontales
  for (final y in rows) {
    s.line(x0, y, x1, y, CadLayer.cajetin);
  }
  final spec = d.spec;
  // fila 1: empresa
  s.text(x0 + 2, y1 - 5.6, 'HERRERO · OFICINA TÉCNICA', 3, bold: true);
  s.text(x1 - 2, y1 - 5.6, 'Predimensionado orientativo', 2.2, hAlign: 1);
  // fila 2: título del proyecto y de la lámina
  final dims = '${_m2(spec.length)} x ${_m2(spec.width)} x ${_m2(spec.height)} m';
  s.text(x0 + 2, y1 - 14.5, '${spec.type.label.toUpperCase()}  $dims', 4, bold: true);
  s.text(x0 + 2, y1 - 21, s.title, 3);
  // fila 3: material / acabado / norma
  s.line(x0 + 60, rows[1], x0 + 60, rows[2], CadLayer.cajetin);
  s.line(x0 + 120, rows[1], x0 + 120, rows[2], CadLayer.cajetin);
  _cell(s, x0, rows[2], 'MATERIAL', spec.grade.name);
  _cell(s, x0 + 60, rows[2], 'ACABADO', _short(spec.finish, 26));
  _cell(s, x0 + 120, rows[2], 'EJECUCIÓN', 'EN 1090-2 EXC2');
  // fila 4: escala / formato / fecha / hoja
  for (final dx in [45.0, 90.0, 135.0]) {
    s.line(x0 + dx, rows[2], x0 + dx, rows[3], CadLayer.cajetin);
  }
  final now = DateTime.now();
  _cell(s, x0, rows[3], 'ESCALA', s.scaleText);
  _cell(s, x0 + 45, rows[3], 'FORMATO', 'A3');
  _cell(s, x0 + 90, rows[3], 'FECHA', '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}');
  _cell(s, x0 + 135, rows[3], 'HOJA', '$n / $total');
  // fila 5: dibujado / revisado / número
  s.line(x0 + 55, y0, x0 + 55, rows[3], CadLayer.cajetin);
  s.line(x1 - 40, y0, x1 - 40, rows[3], CadLayer.cajetin);
  _cell(s, x0, y0, 'DIBUJADO', 'Herrero (app)');
  s.text(x0 + 57, y0 + 8, 'REVISADO Y FIRMADO (técnico competente)', 1.8);
  s.text(x1 - 38, y0 + 9.4, 'Nº PLANO', 1.8);
  s.text(x1 - 20, y0 + 2.2, s.number, 4.8, bold: true, hAlign: 0);

  // aviso
  s.text(_fx0 + 3, _fy0 + 2.5, 'PREDIMENSIONADO ORIENTATIVO (CTE DB-SE-A / EN 1993). DEBE SER REVISADO Y FIRMADO POR UN TÉCNICO COMPETENTE.', 2,
      layer: CadLayer.texto);
}

void _cell(CadSheet s, double x, double y, String label, String value) {
  s.text(x + 2, y + 6.8, label, 1.8);
  s.text(x + 2, y + 1.8, value, 2.8, bold: true);
}

String _short(String t, int n) => t.length <= n ? t : '${t.substring(0, n - 1)}…';

/// Título de vista subrayado con su escala.
void _viewTitle(CadSheet s, double x, double y, String t, {int? scale}) {
  final txt = t.toUpperCase();
  s.text(x, y, txt, 3.5, bold: true);
  final w = txt.length * 3.5 * 0.78;
  s.line(x, y - 1.2, x + w, y - 1.2, CadLayer.contorno);
  s.line(x, y - 2.2, x + w, y - 2.2, CadLayer.fino);
  final sc = scale ?? s.scale;
  if (sc > 0) s.text(x + w + 5, y, 'E 1:$sc', 3);
}

/// Notas generales en la zona libre a la izquierda del cajetín.
void _notes(CadSheet s, Design d, List<String> extra) {
  final g = d.spec.grade;
  final lines = [
    'NOTAS',
    '1. Cotas en mm; niveles en m.',
    '2. Material: ${g.name} (${g.norm}). Tornillería: ${_short(g.bolts, 48)}.',
    '3. Soldadura: ${_short(d.welds.isNotEmpty ? d.welds.first.process : g.weld, 62)}.',
    '4. Acabado: ${_short(d.spec.finish, 60)}.',
    ...extra,
  ];
  var y = _fy0 + _tbH - 4;
  for (var i = 0; i < lines.length && y > _fy0 + 6; i++) {
    s.text(_fx0 + 4, y, lines[i], i == 0 ? 2.5 : 2, bold: i == 0);
    y -= i == 0 ? 4 : 3.4;
  }
}

// ---------------------------------------------------------------------------
// Vista 2D genérica
// ---------------------------------------------------------------------------

class _V {
  final CadSheet s;
  final int sc;
  final double ox, oy, u0, v0;
  _V(this.s, this.sc, this.ox, this.oy, this.u0, this.v0);
  double x(double u) => ox + (u - u0) * 1000 / sc;
  double y(double v) => oy + (v - v0) * 1000 / sc;
  double p(double mm) => mm / sc; // mm reales -> mm papel
}

/// Coloca una vista de [u0..u1] x [v0..v1] metros en el área, con márgenes de
/// anotación (mm de papel), eligiendo una escala normalizada.
_V _place(CadSheet s, double u0, double u1, double v0, double v1,
    {double left = 26, double right = 26, double bottom = 30, double top = 12, int? scale}) {
  final aw = (_ax1 - _ax0) - left - right, ah = (_ay1 - _ay0) - bottom - top;
  final sc = scale ?? fitScale(math.max(0.2, u1 - u0), math.max(0.2, v1 - v0), aw, ah);
  final w = (u1 - u0) * 1000 / sc, h = (v1 - v0) * 1000 / sc;
  final ox = _ax0 + left + (aw - w) / 2, oy = _ay0 + bottom + (ah - h) / 2;
  return _V(s, sc, ox, oy, u0, v0);
}

bool _near(double a, double b, [double tol = 0.03]) => (a - b).abs() < tol;

/// Ejes locales del perfil de una barra: (eje, alma, ala).
(Vec3, Vec3, Vec3) _frameOf(Member m) {
  final dd = m.b - m.a;
  final len = dd.length;
  final ax = len < 1e-9 ? const Vec3(0, 0, 1) : dd * (1 / len);
  var w = m.webDir - ax * m.webDir.dot(ax);
  if (w.length < 1e-6) {
    w = ax.cross(const Vec3(0, 0, 1));
    if (w.length < 1e-6) w = const Vec3(1, 0, 0);
  }
  w = w.normalized;
  return (ax, w, ax.cross(w).normalized);
}

/// Rectángulos (centro alma, centro ala, tamaño alma, tamaño ala) en mm que
/// forman la sección del perfil.
List<(double, double, double, double)> _sectionRects(SteelProfile p) {
  final h = p.h, b = p.b, tw = p.tw, tf = p.tf;
  switch (p.family) {
    case ProfileFamily.ipe:
    case ProfileFamily.heb:
      return [((h - tf) / 2, 0, tf, b), (-(h - tf) / 2, 0, tf, b), (0, 0, h - 2 * tf, tw)];
    case ProfileFamily.upn:
      return [((h - tf) / 2, 0, tf, b), (-(h - tf) / 2, 0, tf, b), (0, -(b - tw) / 2, h - 2 * tf, tw)];
    case ProfileFamily.shs:
    case ProfileFamily.rhs:
      return [((h - tw) / 2, 0, tw, b), (-(h - tw) / 2, 0, tw, b), (0, (b - tw) / 2, h - 2 * tw, tw), (0, -(b - tw) / 2, h - 2 * tw, tw)];
    case ProfileFamily.angle:
      return [(0, (b - tw) / 2, b, tw), ((b - tw) / 2, 0, tw, b)];
    case ProfileFamily.round:
    case ProfileFamily.chs:
      return const [];
    case ProfileFamily.flat:
      return [(0, 0, h, b)];
  }
}

/// Dibuja la sección de una barra perpendicular a la vista en (cx, cy) papel.
/// [wu,wv] y [fu,fv]: direcciones del alma y del ala en la vista.
void _section(CadSheet s, _V v, SteelProfile p, double cx, double cy, double wu, double wv, double fu, double fv) {
  if (p.family == ProfileFamily.round) {
    s.circle(cx, cy, math.max(0.35, v.p(p.h) / 2), CadLayer.secciones, fill: true);
    return;
  }
  if (p.family == ProfileFamily.chs) {
    final r = math.max(0.35, v.p(p.h) / 2);
    s.circle(cx, cy, r, CadLayer.secciones);
    if (r - v.p(p.tw) > 0.3) s.circle(cx, cy, r - v.p(p.tw), CadLayer.secciones);
    return;
  }
  final rects = _sectionRects(p);
  final minDim = math.min(v.p(p.h), v.p(p.b));
  if (minDim < 1.2) {
    // muy pequeña: rectángulo macizo
    _orientedRect(s, cx, cy, wu, wv, fu, fv, v.p(p.h), v.p(p.b), CadLayer.secciones, fill: true);
    return;
  }
  for (final (cw, cf, sw, sf) in rects) {
    final px = cx + (wu * cw + fu * cf) / v.sc, py = cy + (wv * cw + fv * cf) / v.sc;
    _orientedRect(s, px, py, wu, wv, fu, fv, math.max(0.25, v.p(sw)), math.max(0.25, v.p(sf)), CadLayer.secciones,
        fill: true);
  }
}

void _orientedRect(CadSheet s, double cx, double cy, double au, double av, double bu, double bv, double la, double lb,
    CadLayer l,
    {bool fill = false}) {
  final ha = la / 2, hb = lb / 2;
  s.poly([
    cx - au * ha - bu * hb, cy - av * ha - bv * hb,
    cx + au * ha - bu * hb, cy + av * ha - bv * hb,
    cx + au * ha + bu * hb, cy + av * ha + bv * hb,
    cx - au * ha + bu * hb, cy - av * ha + bv * hb,
  ], l, closed: true, fill: fill);
}

/// Dibuja barras en una vista ortogonal.
/// [uv] proyecta a (u, v) en metros; [view] es la dirección de la vista.
void _members(CadSheet s, _V v, Iterable<Member> ms, (double, double) Function(Vec3) uv, Vec3 view,
    {bool singleLine = false, Set<String>? tagged}) {
  for (final m in ms) {
    final (pa0, pa1) = uv(m.a);
    final (pb0, pb1) = uv(m.b);
    final x0 = v.x(pa0), y0 = v.y(pa1), x1 = v.x(pb0), y1 = v.y(pb1);
    final l2 = math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
    final (ax, wd, fd) = _frameOf(m);
    if (l2 < 0.4) {
      // perpendicular a la vista: sección
      final w2 = uv(m.a + wd) , o2 = uv(m.a), f2 = uv(m.a + fd);
      _section(s, v, m.profile, x0, y0, w2.$1 - o2.$1, w2.$2 - o2.$2, f2.$1 - o2.$1, f2.$2 - o2.$2);
      continue;
    }
    final ux = (x1 - x0) / l2, uy = (y1 - y0) / l2;
    final nx = -uy, ny = ux;
    final light = m.role == MemberRole.brace || m.role == MemberRole.baluster;
    // ancho visible: componente del perfil perpendicular al eje dentro de la vista
    final p3 = view.cross(ax);
    final p3l = p3.length;
    double wVis = m.profile.b;
    double webFace = 0;
    if (p3l > 1e-6) {
      final pn = p3 * (1 / p3l);
      webFace = wd.dot(pn).abs();
      wVis = webFace * m.profile.h + fd.dot(pn).abs() * m.profile.b;
    }
    final wp = v.p(wVis);
    if (m.role == MemberRole.haunch && !singleLine && wp >= 0.7) {
      // cartela: canto completo junto al pilar (extremo más bajo), nulo en el otro
      final upx = ny >= 0 ? nx : -nx, upy = ny >= 0 ? ny : -ny;
      final h = wp / 2;
      final deepA = y0 <= y1;
      final dx = deepA ? x0 : x1, dy = deepA ? y0 : y1;
      s.poly([x0 + upx * h, y0 + upy * h, x1 + upx * h, y1 + upy * h, dx - upx * h, dy - upy * h], CadLayer.contorno,
          closed: true);
      continue;
    }
    if (singleLine || wp < 0.7 || light) {
      const main = {
        MemberRole.column, MemberRole.rafter, MemberRole.beam, MemberRole.chordTop, MemberRole.chordBottom,
        MemberRole.stringer, MemberRole.frame, MemberRole.haunch,
      };
      s.line(x0, y0, x1, y1, light || !main.contains(m.role) ? CadLayer.fino : CadLayer.contorno);
    } else {
      final h = wp / 2;
      s.poly([x0 + nx * h, y0 + ny * h, x1 + nx * h, y1 + ny * h, x1 - nx * h, y1 - ny * h, x0 - nx * h, y0 - ny * h],
          CadLayer.contorno,
          closed: true);
      // alas vistas de canto (perfiles abiertos con el alma en la vista)
      final open = m.profile.family == ProfileFamily.ipe ||
          m.profile.family == ProfileFamily.heb ||
          m.profile.family == ProfileFamily.upn;
      final tfp = v.p(m.profile.tf);
      if (open && webFace > 0.7 && h - tfp > 0.4) {
        final k = h - tfp;
        s.line(x0 + nx * k, y0 + ny * k, x1 + nx * k, y1 + ny * k, CadLayer.fino);
        s.line(x0 - nx * k, y0 - ny * k, x1 - nx * k, y1 - ny * k, CadLayer.fino);
      }
      // tubos: líneas ocultas del espesor
      if ((m.profile.family == ProfileFamily.shs || m.profile.family == ProfileFamily.rhs) && h - v.p(m.profile.tw) > 0.6) {
        final k = h - v.p(m.profile.tw);
        s.line(x0 + nx * k, y0 + ny * k, x1 + nx * k, y1 + ny * k, CadLayer.ocultas);
        s.line(x0 - nx * k, y0 - ny * k, x1 - nx * k, y1 - ny * k, CadLayer.ocultas);
      }
    }
    // marca de pieza (una vez por marca y vista)
    if (tagged != null && m.mark.isNotEmpty && m.role != MemberRole.baluster && l2 > 14 && tagged.add(m.mark)) {
      var ang = math.atan2(uy, ux) * 180 / math.pi;
      var sx = nx, sy = ny;
      if (ang > 90.01 || ang <= -90) {
        ang += ang > 0 ? -180 : 180;
        sx = -nx;
        sy = -ny;
      }
      final off = math.max(wp / 2, 0.5) + 2.6;
      final mx = (x0 + x1) / 2 + sx * off, my = (y0 + y1) / 2 + sy * off;
      if (ang.abs() < 1) {
        s.tag(mx, my, m.mark);
      } else {
        s.text(mx, my, m.mark, 2.5, layer: CadLayer.marcas, angle: ang, hAlign: 0, vAlign: 0, bold: true);
      }
    }
  }
}

void _ground(CadSheet s, double x0, double x1, double y) {
  s.line(x0, y, x1, y, CadLayer.terreno);
  for (var x = x0 + 2; x < x1; x += 3) {
    s.line(x, y, x - 2, y - 2, CadLayer.fino);
  }
}

void _axisV(CadSheet s, double x, double yTop, double yBot, String name, {bool bubbleBottom = true}) {
  s.line(x, yTop, x, yBot, CadLayer.ejes);
  s.axisBubble(x, bubbleBottom ? yBot - 4 : yTop + 4, name);
}

void _axisH(CadSheet s, double y, double xLeft, double xRight, String name) {
  s.line(xLeft, y, xRight, y, CadLayer.ejes);
  s.axisBubble(xLeft - 4, y, name);
}

String _axisLetter(int i) => String.fromCharCode(65 + i);

bool _vertical(Member m) => _near(m.a.x, m.b.x, 0.01) && _near(m.a.y, m.b.y, 0.01);

/// Pilares (barras verticales) que arrancan del suelo, sin repetir posición.
List<Member> _columns(Design d) {
  final seen = <String>{};
  final out = <Member>[];
  for (final m in d.members) {
    if (!_vertical(m) || m.role == MemberRole.baluster || m.role == MemberRole.post) continue;
    if (math.min(m.a.z, m.b.z) > 0.3) continue;
    if (seen.add('${m.a.x.toStringAsFixed(2)}|${m.a.y.toStringAsFixed(2)}')) out.add(m);
  }
  return out;
}

(double, double, double, double) _extXY(Design d) {
  var x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
  for (final m in d.members) {
    for (final p in [m.a, m.b]) {
      x0 = math.min(x0, p.x);
      y0 = math.min(y0, p.y);
      x1 = math.max(x1, p.x);
      y1 = math.max(y1, p.y);
    }
  }
  return (x0, y0, x1, y1);
}

// ---------------------------------------------------------------------------
// E-01 Replanteo y cimentación
// ---------------------------------------------------------------------------

CadSheet _foundationPlan(Design d) {
  final s = CadSheet('E-01', 'Planta de replanteo y cimentación', 0);
  final (x0e, y0e, x1e, y1e) = _extXY(d);
  final fs = d.footingSize;
  final pad = math.max(0.4, fs / 2 + 0.2);
  final v = _place(s, x0e - pad, x1e + pad, y0e - pad, y1e + pad, left: 34, bottom: 36, top: 26, right: 34);
  final sh = CadSheet('E-01', s.title, v.sc);
  final v2 = _V(sh, v.sc, v.ox, v.oy, v.u0, v.v0);
  final fx = d.frameX, gy = d.gridY;
  final top = v2.y(y1e + pad) + 8, bot = v2.y(y0e - pad) - 8;
  final left = v2.x(x0e - pad) - 8, right = v2.x(x1e + pad) + 8;
  for (var i = 0; i < fx.length; i++) {
    _axisV(sh, v2.x(fx[i]), top, bot - 16, '${i + 1}');
  }
  for (var j = 0; j < gy.length; j++) {
    _axisH(sh, v2.y(gy[j]), left, right, _axisLetter(j));
  }
  // zapatas, placas y pilares
  final cols = _columns(d);
  final pa = d.plates.isNotEmpty ? d.plates.first : null;
  for (final f in d.footings) {
    final cx = v2.x(f.x), cy = v2.y(f.y);
    if (fs > 0) {
      final h = v2.p(fs * 1000) / 2;
      sh.rect(cx - h, cy - h, cx + h, cy + h, CadLayer.cimentacion);
    }
    if (pa != null) {
      sh.rect(cx - v2.p(pa.w) / 2, cy - v2.p(pa.h) / 2, cx + v2.p(pa.w) / 2, cy + v2.p(pa.h) / 2, CadLayer.fino);
    }
  }
  _members(sh, v2, cols, (p) => (p.x, p.y), const Vec3(0, 0, 1));
  // cotas entre ejes (cadena + total) abajo y a la derecha
  final yd = v2.y(y0e - pad) - 2;
  for (var i = 0; i + 1 < fx.length; i++) {
    sh.dim(v2.x(fx[i]), yd, v2.x(fx[i + 1]), yd, -6, _mm(fx[i + 1] - fx[i]));
  }
  if (fx.length > 2) sh.dim(v2.x(fx.first), yd, v2.x(fx.last), yd, -13, _mm(fx.last - fx.first));
  final xd = v2.x(x1e + pad) + 2;
  for (var j = 0; j + 1 < gy.length; j++) {
    sh.dim(xd, v2.y(gy[j]), xd, v2.y(gy[j + 1]), -6, _mm(gy[j + 1] - gy[j]));
  }
  if (gy.length > 2) sh.dim(xd, v2.y(gy.first), xd, v2.y(gy.last), -13, _mm(gy.last - gy.first));
  // marcas de placa
  if (pa != null && d.footings.isNotEmpty) {
    final f = d.footings.first;
    final cx = v2.x(f.x), cy = v2.y(f.y);
    final off = (fs > 0 ? v2.p(fs * 1000) / 2 : v2.p(pa.w) / 2) + 3;
    sh.line(cx + v2.p(pa.w) / 2, cy + v2.p(pa.h) / 2, cx + off + 2, cy + off + 2, CadLayer.marcas);
    sh.tag(cx + off + 6, cy + off + 3, pa.mark);
  }
  _viewTitle(sh, _ax0, _ay1, 'Planta de replanteo y cimentación');
  final extra = <String>[
    if (fs > 0) '5. Zapatas aisladas ${_mm(fs)}x${_mm(fs)} mm (predimensionado; ver estudio geotécnico).',
    if (pa != null) '6. Placas ${pa.mark}: ${pa.w.round()}x${pa.h.round()}x${pa.t.round()} mm. Mortero sin retracción e = 30 mm.',
  ];
  _notes(sh, d, extra);
  sh.scaleBar(_fx1 - _tbW - 70, _fy0 + 4);
  return sh;
}

// ---------------------------------------------------------------------------
// E-02 Planta de estructura
// ---------------------------------------------------------------------------

CadSheet _structurePlan(Design d) {
  final (x0e, y0e, x1e, y1e) = _extXY(d);
  final tmp = CadSheet('E-02', '', 0);
  final v0 = _place(tmp, x0e - 0.3, x1e + 0.3, y0e - 0.3, y1e + 0.3, left: 34, bottom: 30, top: 26, right: 34);
  final s = CadSheet('E-02', 'Planta de estructura', v0.sc);
  final v = _V(s, v0.sc, v0.ox, v0.oy, v0.u0, v0.v0);
  final fx = d.frameX, gy = d.gridY;
  final top = v.y(y1e + 0.3) + 6, bot = v.y(y0e - 0.3) - 6;
  final left = v.x(x0e - 0.3) - 6, right = v.x(x1e + 0.3) + 6;
  for (var i = 0; i < fx.length; i++) {
    _axisV(s, v.x(fx[i]), top + 10, bot, '${i + 1}', bubbleBottom: false);
  }
  for (var j = 0; j < gy.length; j++) {
    _axisH(s, v.y(gy[j]), left, right, _axisLetter(j));
  }
  // barras horizontales/inclinadas, de abajo arriba
  final ms = d.members.where((m) => !_vertical(m) && m.role != MemberRole.baluster).toList()
    ..sort((a, b) => (a.a.z + a.b.z).compareTo(b.a.z + b.b.z));
  final tagged = <String>{};
  _members(s, v, ms, (p) => (p.x, p.y), const Vec3(0, 0, 1), singleLine: true, tagged: tagged);
  _members(s, v, _columns(d), (p) => (p.x, p.y), const Vec3(0, 0, 1), tagged: tagged);
  // cotas generales
  final yd = v.y(y0e - 0.3) - 2;
  for (var i = 0; i + 1 < fx.length; i++) {
    s.dim(v.x(fx[i]), yd, v.x(fx[i + 1]), yd, -6, _mm(fx[i + 1] - fx[i]));
  }
  if (fx.length > 2) s.dim(v.x(fx.first), yd, v.x(fx.last), yd, -13, _mm(fx.last - fx.first));
  final xd = v.x(x1e + 0.3) + 2;
  if (gy.length > 1) s.dim(xd, v.y(gy.first), xd, v.y(gy.last), -6, _mm(gy.last - gy.first));
  _viewTitle(s, _ax0, _ay1, 'Planta de estructura');
  _legendMarks(s, d);
  s.scaleBar(_fx1 - _tbW - 75, _fy0 + 9);
  return s;
}

/// Leyenda de marcas (marca → descripción y perfil) a la izquierda del cajetín.
void _legendMarks(CadSheet s, Design d) {
  final seen = <String, String>{};
  for (final p in d.pieces) {
    seen.putIfAbsent(p.mark, () => '${p.description} · ${p.profile.name}');
  }
  var y = _fy0 + _tbH - 4;
  s.text(_fx0 + 4, y, 'MARCAS', 2.5, bold: true);
  y -= 4;
  var col = 0;
  for (final e in seen.entries) {
    if (y < _fy0 + 7) {
      col++;
      y = _fy0 + _tbH - 8;
      if (col > 1) break;
    }
    final x = _fx0 + 4 + col * 105;
    s.text(x, y, e.key, 2.2, layer: CadLayer.marcas, bold: true);
    s.text(x + 10, y, _short(e.value, 44), 2.0);
    y -= 3.3;
  }
}

// ---------------------------------------------------------------------------
// E-03 / E-04 Alzados
// ---------------------------------------------------------------------------

CadSheet _elevation(Design d, {required bool front}) {
  final fx = d.frameX, gy = d.gridY;
  // plano de la vista
  final plane = front ? (fx.length > 2 ? fx[1] : fx.first) : (gy.isNotEmpty ? gy.first : 0.0);
  double depth(Vec3 p) => front ? p.x : p.y;
  (double, double) uv(Vec3 p) => front ? (p.y, p.z) : (p.x, p.z);
  final view = front ? const Vec3(1, 0, 0) : const Vec3(0, 1, 0);
  var inPlane = d.members.where((m) => _near(depth(m.a), plane) && _near(depth(m.b), plane)).toList();
  final crossing = d.members.where((m) {
    final da = depth(m.a) - plane, db = depth(m.b) - plane;
    if (_near(da, 0) && _near(db, 0)) return false;
    if (da * db > 0.0004) return false; // no corta el plano
    final (ax, _, _) = _frameOf(m);
    return ax.dot(view).abs() > 0.7;
  }).map((m) {
    // punto de corte
    final da = depth(m.a) - plane, db = depth(m.b) - plane;
    final t = (da - db).abs() < 1e-9 ? 0.0 : da / (da - db);
    final p = m.a + (m.b - m.a) * t.clamp(0.0, 1.0);
    return Member(role: m.role, profile: m.profile, a: p, b: p + view * 0.001, webDir: m.webDir)..mark = m.mark;
  }).toList();
  var fallback = false;
  const framed = {StructureType.nave, StructureType.marquesina, StructureType.entreplanta, StructureType.portico,
    StructureType.estanteria, StructureType.torre};
  if (!framed.contains(d.spec.type)) {
    inPlane = d.members.toList();
    crossing.clear();
    fallback = true;
  } else if (inPlane.length < 2) {
    inPlane = d.members.toList();
    fallback = true;
  }
  var u0 = 1e9, u1 = -1e9, v1 = 0.0;
  for (final m in [...inPlane, ...crossing]) {
    for (final p in [m.a, m.b]) {
      final (u, w) = uv(p);
      u0 = math.min(u0, u);
      u1 = math.max(u1, u);
      v1 = math.max(v1, w);
    }
  }
  v1 = math.max(v1, math.max(d.spec.height, front ? d.ridgeHeight : 0));
  for (final a in front ? gy : fx) {
    u0 = math.min(u0, a);
    u1 = math.max(u1, a);
  }
  final pad = 0.6;
  final title = front
      ? (fallback ? 'Alzado frontal' : 'Alzado frontal – pórtico tipo (eje ${fx.length > 2 ? 2 : 1})')
      : (fallback ? 'Alzado lateral' : 'Alzado lateral – fachada (eje A)');
  final tmp = CadSheet(front ? 'E-03' : 'E-04', title, 0);
  final v0 = _place(tmp, u0 - pad, u1 + pad, -0.3, v1 + 0.3, left: 30, bottom: 34, right: 40);
  final s = CadSheet(tmp.number, title, v0.sc);
  final v = _V(s, v0.sc, v0.ox, v0.oy, v0.u0, v0.v0);
  _ground(s, v.x(u0 - pad), v.x(u1 + pad), v.y(0));
  // ejes
  final axes = front ? gy : fx;
  for (var i = 0; i < axes.length; i++) {
    _axisV(s, v.x(axes[i]), v.y(v1 + 0.2), v.y(0) - 22, front ? _axisLetter(i) : '${i + 1}');
  }
  final tagged = <String>{};
  _members(s, v, crossing, uv, view);
  _members(s, v, inPlane, uv, view, tagged: tagged, singleLine: fallback && inPlane.length > 60);
  // placas de anclaje en alzado
  if (d.plates.isNotEmpty) {
    final pa = d.plates.first;
    for (final c in _columns(d)) {
      if (!fallback && !_near(depth(c.a), plane)) continue;
      final (u, _) = uv(c.a);
      final hw = v.p(pa.w) / 2;
      s.rect(v.x(u) - hw, v.y(0), v.x(u) + hw, v.y(0) + math.max(0.3, v.p(pa.t)), CadLayer.contorno, fill: true);
    }
  }
  // cotas horizontales entre ejes
  final yd = v.y(0) - 3;
  for (var i = 0; i + 1 < axes.length; i++) {
    s.dim(v.x(axes[i]), yd, v.x(axes[i + 1]), yd, -6, _mm(axes[i + 1] - axes[i]));
  }
  if (axes.length > 2) s.dim(v.x(axes.first), yd, v.x(axes.last), yd, -13, _mm(axes.last - axes.first));
  // alturas y niveles
  final H = d.spec.height;
  final xl = v.x(u0 - pad) + 2;
  if (H > 0.05) s.dim(xl, v.y(0), xl, v.y(H), 4, _mm(H));
  final xr = v.x(u1 + pad) + 2;
  s.level(xr, v.y(0), 0);
  if (H > 0.05) s.level(xr, v.y(H), H);
  if (d.ridgeHeight > H + 0.05 && front) s.level(xr, v.y(d.ridgeHeight), d.ridgeHeight);
  if (front && d.spec.slopePct > 0.1 && d.ridgeHeight > H + 0.05) {
    s.text(v.x((u0 + u1) / 4), v.y((H + d.ridgeHeight) / 2) + 10, 'Pte. ${d.spec.slopePct.toStringAsFixed(1).replaceAll('.', ',')} %',
        2.5);
  }
  _viewTitle(s, _ax0, _ay1, title);
  _legendMarks(s, d);
  s.scaleBar(_fx1 - _tbW - 75, _fy0 + 9);
  return s;
}

// ---------------------------------------------------------------------------
// E-05 Detalles de uniones
// ---------------------------------------------------------------------------

CadSheet _details(Design d) {
  final s = CadSheet('E-05', 'Detalles de uniones y soldaduras', 10);
  final weld = d.welds.isNotEmpty ? d.welds.first : null;
  final proc = (weld?.process ?? d.spec.grade.weld).contains('141')
      ? '141'
      : ((weld?.process ?? '').contains('111') && !(weld?.process ?? '').contains('135') ? '111' : '135');
  final col = d.members
      .firstWhere((m) => m.role == MemberRole.column || m.role == MemberRole.post || m.role == MemberRole.frame,
          orElse: () => d.members.first)
      .profile;
  if (d.plates.isNotEmpty) {
    final pa = d.plates.first;
    final boltD0 = _boltDiameter(d);
    final anchorL0 = boltD0 * 25;
    const colH = 250.0;
    final nW = math.min(12, d.welds.length);
    final tableBottom = _ay1 - 8 - 5.0 * (nW + 1);
    // escala común que encaje la planta (izquierda) y el alzado (derecha, bajo el cuadro)
    final scPlan = fitScale((pa.w + 120) / 1000, (pa.h + 120) / 1000, 150, 165);
    final scElev = fitScale((pa.w + 260) / 1000, (anchorL0 + 30 + pa.t + colH + 60) / 1000, 170, tableBottom - _ay0 - 30);
    final sc = math.max(scPlan, scElev);
    final s2 = CadSheet('E-05', s.title, sc);
    // --- Planta de placa ---
    final cx = _ax0 + 85, cy = _ay0 + (_ay1 - _ay0) / 2 - 6;
    double p(double mm) => mm / sc;
    s2.rect(cx - p(pa.w) / 2, cy - p(pa.h) / 2, cx + p(pa.w) / 2, cy + p(pa.h) / 2, CadLayer.contorno);
    _section(s2, _V(s2, sc, 0, 0, 0, 0), col, cx, cy, 0, 1, 1, 0);
    // ejes de la placa
    s2.line(cx - p(pa.w) / 2 - 6, cy, cx + p(pa.w) / 2 + 6, cy, CadLayer.ejes);
    s2.line(cx, cy - p(pa.h) / 2 - 6, cx, cy + p(pa.h) / 2 + 6, CadLayer.ejes);
    final edge = math.min(50.0, math.min(pa.w, pa.h) * 0.18);
    final bx = pa.w / 2 - edge, by = pa.h / 2 - edge;
    final boltD = boltD0;
    for (final sx in [-1, 1]) {
      for (final sy in [-1, 1]) {
        s2.circle(cx + sx * p(bx), cy + sy * p(by), math.max(0.6, p(boltD + 6) / 2), CadLayer.contorno);
        s2.line(cx + sx * p(bx) - 2, cy + sy * p(by), cx + sx * p(bx) + 2, cy + sy * p(by), CadLayer.ejes);
        s2.line(cx + sx * p(bx), cy + sy * p(by) - 2, cx + sx * p(bx), cy + sy * p(by) + 2, CadLayer.ejes);
      }
    }
    final yb = cy - p(pa.h) / 2 - 3;
    s2.dim(cx - p(pa.w) / 2, yb, cx + p(pa.w) / 2, yb, -8, pa.w.round().toString());
    s2.dim(cx - p(bx), yb, cx + p(bx), yb, -3, (2 * bx).round().toString());
    final xb = cx + p(pa.w) / 2 + 3;
    s2.dim(xb, cy - p(pa.h) / 2, xb, cy + p(pa.h) / 2, -8, pa.h.round().toString());
    s2.dim(xb, cy - p(by), xb, cy + p(by), -3, (2 * by).round().toString());
    // soldadura pilar-placa: todo alrededor
    if (weld != null) {
      s2.weldSymbol(cx + p(col.b) / 2, cy + p(col.h) / 2, 14, 18, 'a${weld.throat.toStringAsFixed(0)}',
          process: proc, allAround: true);
    }
    _viewTitle(s2, cx - 70, math.min(_ay1 - 4, cy + p(pa.h) / 2 + 22), 'Placa ${pa.mark} – planta', scale: sc);
    // --- Alzado de placa ---
    final ex = _ax0 + 265, ey = _ay0 + 14 + p(anchorL0);
    s2.rect(ex - p(pa.w) / 2, ey, ex + p(pa.w) / 2, ey + math.max(0.4, p(pa.t)), CadLayer.contorno, fill: true);
    // mortero y hormigón
    s2.rect(ex - p(pa.w) / 2 + 2, ey - p(30), ex + p(pa.w) / 2 - 2, ey, CadLayer.fino);
    s2.line(ex - p(pa.w) / 2 - 20, ey - p(30), ex + p(pa.w) / 2 + 20, ey - p(30), CadLayer.terreno);
    // pilar
    s2.rect(ex - p(col.b) / 2, ey + p(pa.t), ex + p(col.b) / 2, ey + p(pa.t) + p(colH) + 20, CadLayer.contorno);
    // pernos
    final anchorL = anchorL0;
    for (final sx in [-1, 1]) {
      final x = ex + sx * p(bx);
      final r = math.max(0.4, p(boltD) / 2);
      s2.rect(x - r, ey - p(anchorL), x + r, ey + p(pa.t) + p(boltD * 1.5), CadLayer.ocultas);
      s2.line(x, ey - p(anchorL), x + sx * p(boltD * 4), ey - p(anchorL), CadLayer.ocultas);
      // tuerca y contratuerca
      s2.rect(x - p(boltD * 0.9), ey + p(pa.t), x + p(boltD * 0.9), ey + p(pa.t) + p(boltD * 0.8), CadLayer.contorno,
          fill: true);
    }
    s2.dim(ex - p(pa.w) / 2 - 4, ey, ex - p(pa.w) / 2 - 4, ey - p(anchorL), 6, anchorL.round().toString());
    s2.text(ex + p(pa.w) / 2 + 6, ey - p(30) - 3, 'Mortero sin retracción e = 30', 2.2);
    s2.text(ex + p(pa.w) / 2 + 6, ey + p(pa.t) + 1.5, 'Placa ${pa.w.round()}x${pa.h.round()}x${pa.t.round()}', 2.2);
    if (d.bolts.isNotEmpty) s2.text(ex + p(pa.w) / 2 + 6, ey - p(anchorL) / 2, _short(d.bolts.first.spec, 40), 2.2);
    if (weld != null) {
      s2.weldSymbol(ex + p(col.b) / 2, ey + p(pa.t), 16, 14, 'a${weld.throat.toStringAsFixed(0)}',
          process: proc, allAround: true);
    }
    _viewTitle(s2, ex - 70, math.min(tableBottom - 6, ey + p(pa.t) + p(colH) + 30), 'Placa ${pa.mark} – alzado', scale: sc);
    _weldTable(s2, d, proc);
    _notes(s2, d, ['5. Soldaduras en ángulo según EN ISO 2553 (garganta a en mm). Inspección visual 100 % (EN ISO 17637).']);
    return s2;
  }
  // sin placas: solo tabla de soldaduras y unión tipo
  final s2 = CadSheet('E-05', s.title, 0);
  _weldTable(s2, d, proc);
  final jx = _ax0 + 70, jy = _ay0 + 120;
  s2.rect(jx - 4, jy - 60, jx + 4, jy, CadLayer.contorno);
  s2.rect(jx + 4, jy - 8, jx + 80, jy, CadLayer.contorno);
  if (weld != null) {
    s2.weldSymbol(jx + 4, jy - 4, 16, 22, 'a${weld.throat.toStringAsFixed(0)}', process: proc, allAround: true);
  }
  _viewTitle(s2, jx - 10, jy + 30, 'Unión soldada tipo (esquema)');
  _notes(s2, d, ['5. Soldaduras en ángulo según EN ISO 2553 (garganta a en mm).']);
  return s2;
}

double _boltDiameter(Design d) {
  if (d.bolts.isEmpty) return 16;
  final m = RegExp(r'M\s?(\d{2})').firstMatch(d.bolts.first.spec);
  return m == null ? 16 : double.parse(m[1]!);
}

void _weldTable(CadSheet s, Design d, String proc) {
  final x0 = _ax0 + 140.0;
  var y = _ay1 - 6;
  final cols = <double>[0, 64, 104, 116, 134, 144, 232];
  s.text(x0, y + 3, 'CUADRO DE SOLDADURAS', 3, bold: true);
  y -= 2;
  final head = ['Unión', 'Tipo', 'a (mm)', 'Long. (mm)', 'Nº', 'Proceso / posición'];
  _tableRow(s, x0, y, cols, head, bold: true);
  y -= 5;
  for (final w in d.welds.take(12)) {
    _tableRow(s, x0, y, cols, [
      _short(w.joint, 34),
      _short(w.type, 22),
      w.throat.toStringAsFixed(0),
      w.lengthPerJoint.toStringAsFixed(0),
      '${w.count}',
      _short('$proc · ${w.position}', 46),
    ]);
    y -= 5;
  }
  s.line(x0, y, x0 + cols.last, y, CadLayer.fino);
}

void _tableRow(CadSheet s, double x0, double y, List<double> cols, List<String> cells, {bool bold = false}) {
  s.line(x0, y, x0 + cols.last, y, CadLayer.fino);
  for (var i = 0; i < cols.length; i++) {
    s.line(x0 + cols[i], y, x0 + cols[i], y - 5, CadLayer.fino);
  }
  for (var i = 0; i < cells.length && i + 1 < cols.length; i++) {
    s.text(x0 + cols[i] + 1.2, y - 3.6, cells[i], 2.1, bold: bold);
  }
}

// ---------------------------------------------------------------------------
// E-06… Despiece
// ---------------------------------------------------------------------------

List<CadSheet> _schedules(Design d) {
  final rows = <List<String>>[
    for (final p in d.pieces)
      [
        p.mark,
        _short(p.description, 30),
        p.profile.name,
        p.lengthMm.round().toString(),
        '${p.qty}',
        _short(p.cut, 16),
        p.unitKg.toStringAsFixed(1).replaceAll('.', ','),
        p.totalKg.toStringAsFixed(1).replaceAll('.', ','),
      ],
    for (final p in d.plates)
      [
        p.mark,
        _short(p.description, 30),
        'Chapa ${p.t.round()}',
        '${p.w.round()}x${p.h.round()}',
        '${p.qty}',
        'Oxicorte/plasma',
        p.unitKg.toStringAsFixed(1).replaceAll('.', ','),
        (p.unitKg * p.qty).toStringAsFixed(1).replaceAll('.', ','),
      ],
  ];
  const perSheet = 34;
  final sheets = <CadSheet>[];
  final cols = <double>[0, 18, 88, 128, 158, 172, 212, 240, 272];
  final head = ['Marca', 'Descripción', 'Perfil', 'Long. (mm)', 'Ud.', 'Corte', 'kg/ud', 'kg total'];
  for (var start = 0; start < math.max(1, rows.length); start += perSheet) {
    final s = CadSheet('E-${(6 + sheets.length).toString().padLeft(2, '0')}', 'Despiece y lista de materiales', 0);
    final x0 = _ax0 + 4;
    var y = _ay1 - 6;
    s.text(x0, y + 3, 'LISTA DE PIEZAS${start > 0 ? ' (cont.)' : ''}', 3, bold: true);
    y -= 2;
    _tableRow(s, x0, y, cols, head, bold: true);
    y -= 5;
    for (final r in rows.skip(start).take(perSheet)) {
      _tableRow(s, x0, y, cols, r);
      y -= 5;
    }
    s.line(x0, y, x0 + cols.last, y, CadLayer.fino);
    if (start + perSheet >= rows.length) {
      // resumen
      final sx = x0 + cols.last + 10;
      var sy = _ay1 - 6;
      s.text(sx, sy + 3, 'RESUMEN', 3, bold: true);
      final lines = [
        'Perfiles: ${d.profilesKg.toStringAsFixed(0)} kg',
        'Chapas: ${d.platesKg.toStringAsFixed(0)} kg',
        'Total: ${d.steelKg.toStringAsFixed(0)} kg',
        'Soldadura: ${d.weldMeters.toStringAsFixed(1).replaceAll('.', ',')} m',
        'Consumible: ${d.consumableKg.toStringAsFixed(1).replaceAll('.', ',')} kg',
        'Pintura/galv.: ${d.paintM2.toStringAsFixed(0)} m²',
        '',
        'TORNILLERÍA',
        for (final b in d.bolts.take(6)) '${b.qty} ud ${_short(b.spec, 30)}',
      ];
      for (final l in lines) {
        sy -= 4.2;
        s.text(sx, sy, l, 2.3, bold: l == 'TORNILLERÍA');
      }
    }
    _notes(s, d, const []);
    sheets.add(s);
  }
  return sheets;
}
