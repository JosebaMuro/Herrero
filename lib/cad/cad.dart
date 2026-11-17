import 'dart:math' as math;

/// Modelo de dibujo tipo CAD: entidades en milímetros de papel (origen abajo
/// a la izquierda, y hacia arriba) sobre láminas normalizadas. El mismo modelo
/// se dibuja en pantalla, en PDF vectorial y en DXF (multiplicado por la
/// escala de la lámina para tener el modelo a tamaño real).

/// Capas con su estilo (ISO 128 / ISO 129).
enum CadLayer {
  contorno('CONTORNO', 7, CadLinetype.continuous, 0.50, 0xFF111111),
  fino('LINEA_FINA', 7, CadLinetype.continuous, 0.25, 0xFF263238),
  ejes('EJES', 1, CadLinetype.center, 0.18, 0xFFC62828),
  ocultas('OCULTAS', 8, CadLinetype.dashed, 0.25, 0xFF607D8B),
  cotas('COTAS', 3, CadLinetype.continuous, 0.18, 0xFF2E7D32),
  texto('TEXTO', 7, CadLinetype.continuous, 0.25, 0xFF111111),
  secciones('SECCIONES', 5, CadLinetype.continuous, 0.35, 0xFF1A237E),
  soldadura('SOLDADURA', 6, CadLinetype.continuous, 0.25, 0xFF6A1B9A),
  marcas('MARCAS', 4, CadLinetype.continuous, 0.25, 0xFF00695C),
  cimentacion('CIMENTACION', 8, CadLinetype.dashed, 0.35, 0xFF795548),
  terreno('TERRENO', 33, CadLinetype.continuous, 0.35, 0xFF795548),
  cajetin('CAJETIN', 7, CadLinetype.continuous, 0.35, 0xFF111111),
  marco('MARCO', 7, CadLinetype.continuous, 0.70, 0xFF111111);

  final String dxf;
  final int aci; // color AutoCAD
  final CadLinetype linetype;
  final double weight; // mm (grosor de línea impreso)
  final int argb; // color en pantalla / PDF
  const CadLayer(this.dxf, this.aci, this.linetype, this.weight, this.argb);
}

/// Tipos de línea (patrones en mm de papel; + trazo, - hueco, 0 punto).
enum CadLinetype {
  continuous('CONTINUOUS', 'Continua', []),
  center('EJE', 'Eje ____ . ____ . ____', [12, -2, 0.5, -2]),
  dashed('TRAZOS', 'Oculta _ _ _ _', [4, -2]);

  final String dxf;
  final String description;
  final List<double> pattern;
  const CadLinetype(this.dxf, this.description, this.pattern);
}

sealed class CadEntity {
  final CadLayer layer;
  const CadEntity(this.layer);
}

class CLine extends CadEntity {
  final double x1, y1, x2, y2;
  const CLine(this.x1, this.y1, this.x2, this.y2, super.layer);
}

/// Polilínea (cerrada opcionalmente) o polígono relleno.
class CPoly extends CadEntity {
  final List<double> pts; // x0, y0, x1, y1…
  final bool closed;
  final bool fill;
  const CPoly(this.pts, super.layer, {this.closed = false, this.fill = false});
}

class CCircle extends CadEntity {
  final double cx, cy, r;
  final bool fill;
  const CCircle(this.cx, this.cy, this.r, super.layer, {this.fill = false});
}

/// Alineación del texto: horizontal (-1 izq, 0 centro, 1 der) y vertical
/// (-1 base, 0 centro, 1 arriba).
class CText extends CadEntity {
  final double x, y, h;
  final String text;
  final double angle; // grados
  final int hAlign, vAlign;
  final bool bold;
  const CText(this.x, this.y, this.text, this.h, super.layer,
      {this.angle = 0, this.hAlign = -1, this.vAlign = -1, this.bold = false});
}

/// Lámina normalizada.
class CadSheet {
  final String number; // E-01
  final String title; // Alzado frontal…
  final int scale; // 100 = 1:100 (0 = sin escala)
  final double width, height; // mm de papel
  final List<CadEntity> ents = [];
  CadSheet(this.number, this.title, this.scale, {this.width = 420, this.height = 297});

  String get scaleText => scale <= 0 ? 'S/E' : '1:$scale';

  // ---- Utilidades de dibujo ----
  void line(double x1, double y1, double x2, double y2, CadLayer l) => ents.add(CLine(x1, y1, x2, y2, l));
  void rect(double x0, double y0, double x1, double y1, CadLayer l, {bool fill = false}) =>
      ents.add(CPoly([x0, y0, x1, y0, x1, y1, x0, y1], l, closed: true, fill: fill));
  void poly(List<double> pts, CadLayer l, {bool closed = false, bool fill = false}) =>
      ents.add(CPoly(pts, l, closed: closed, fill: fill));
  void circle(double cx, double cy, double r, CadLayer l, {bool fill = false}) =>
      ents.add(CCircle(cx, cy, r, l, fill: fill));
  void text(double x, double y, String t, double h,
          {CadLayer layer = CadLayer.texto, double angle = 0, int hAlign = -1, int vAlign = -1, bool bold = false}) =>
      ents.add(CText(x, y, t, h, layer, angle: angle, hAlign: hAlign, vAlign: vAlign, bold: bold));

  /// Cota alineada ISO 129 con trazos oblicuos y texto sobre la línea.
  /// [off] desplaza la línea de cota a la izquierda del vector p1→p2 (mm papel).
  void dim(double x1, double y1, double x2, double y2, double off, String label, {double th = 2.5}) {
    final dx = x2 - x1, dy = y2 - y1;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 0.5) return;
    final ux = dx / len, uy = dy / len;
    final nx = -uy, ny = ux; // normal a la izquierda
    final ax = x1 + nx * off, ay = y1 + ny * off, bx = x2 + nx * off, by = y2 + ny * off;
    final s = off.sign == 0 ? 1.0 : off.sign;
    // líneas de referencia: separadas 1 mm de la pieza, 2 mm más allá de la cota
    line(x1 + nx * s * 1, y1 + ny * s * 1, ax + nx * s * 2, ay + ny * s * 2, CadLayer.cotas);
    line(x2 + nx * s * 1, y2 + ny * s * 1, bx + nx * s * 2, by + ny * s * 2, CadLayer.cotas);
    line(ax - ux * 1.5, ay - uy * 1.5, bx + ux * 1.5, by + uy * 1.5, CadLayer.cotas);
    // trazos oblicuos a 45°
    final tx = (ux + nx) * 1.25, ty = (uy + ny) * 1.25;
    line(ax - tx, ay - ty, ax + tx, ay + ty, CadLayer.contorno);
    line(bx - tx, by - ty, bx + tx, by + ty, CadLayer.contorno);
    var ang = math.atan2(uy, ux) * 180 / math.pi;
    var px = nx, py = ny;
    if (ang > 90.01 || ang <= -90) {
      ang += ang > 0 ? -180 : 180;
      px = -nx;
      py = -ny;
    }
    // el texto va siempre "encima" de la línea según su lectura
    final tOff = 0.8;
    final mx = (ax + bx) / 2, my = (ay + by) / 2;
    final textW = label.length * th * 0.62;
    if (textW > len - 2) {
      // no cabe: fuera, a continuación del extremo
      text(bx + ux * 2 + px * tOff, by + uy * 2 + py * tOff, label, th, layer: CadLayer.cotas, angle: ang);
    } else {
      text(mx + px * tOff, my + py * tOff, label, th, layer: CadLayer.cotas, angle: ang, hAlign: 0);
    }
  }

  /// Burbuja de eje (ISO): círculo con nombre.
  void axisBubble(double x, double y, String name, {double r = 4}) {
    circle(x, y, r, CadLayer.fino);
    text(x, y, name, r * 0.9, hAlign: 0, vAlign: 0, bold: true);
  }

  /// Marca de nivel: triángulo y cota de altura en m (+6,500).
  void level(double x, double y, double z, {bool right = true}) {
    final s = right ? 1.0 : -1.0;
    poly([x, y, x - 1.8, y + 2.6, x + 1.8, y + 2.6], CadLayer.cotas, closed: true);
    line(x, y + 2.6, x + s * 16, y + 2.6, CadLayer.cotas);
    final t = '${z >= 0 ? '+' : '−'}${z.abs().toStringAsFixed(3).replaceAll('.', ',')}';
    text(x + s * 2.5, y + 3.3, t, 2.5, layer: CadLayer.cotas, hAlign: right ? -1 : 1);
  }

  /// Etiqueta de marca de pieza (texto en caja).
  void tag(double x, double y, String t, {double h = 2.5, double angle = 0}) {
    final w = t.length * h * 0.62 + 1.6;
    if (angle == 0) {
      rect(x - w / 2, y - h / 2 - 0.9, x + w / 2, y + h / 2 + 0.9, CadLayer.marcas);
    }
    text(x, y, t, h, layer: CadLayer.marcas, hAlign: 0, vAlign: 0, angle: angle, bold: true);
  }

  /// Símbolo de soldadura ISO 2553 (sistema A): flecha, línea de referencia
  /// continua + línea de identificación de trazos, triángulo de soldadura en
  /// ángulo, garganta "a", longitud, círculo de "todo alrededor" y proceso en la cola.
  void weldSymbol(double jx, double jy, double dx, double dy, String throat,
      {String length = '', bool allAround = true, String process = '', bool bothSides = false}) {
    final kx = jx + dx, ky = jy + dy; // codo
    line(jx, jy, kx, ky, CadLayer.soldadura);
    // punta de flecha
    final l = math.sqrt(dx * dx + dy * dy);
    final ux = dx / l, uy = dy / l;
    final hx = ux * 2.5, hy = uy * 2.5;
    poly([jx, jy, jx + hx - uy * 0.9, jy + hy + ux * 0.9, jx + hx + uy * 0.9, jy + hy - ux * 0.9], CadLayer.soldadura,
        closed: true, fill: true);
    final dir = dx >= 0 ? 1.0 : -1.0;
    const refLen = 26.0;
    final rx = kx + dir * refLen;
    line(kx, ky, rx, ky, CadLayer.soldadura);
    // línea de identificación (trazos) bajo la de referencia
    for (var t = 0.0; t < refLen; t += 3) {
      line(kx + dir * t, ky - 1.2, kx + dir * math.min(t + 1.8, refLen), ky - 1.2, CadLayer.soldadura);
    }
    if (allAround) circle(kx, ky, 1.4, CadLayer.soldadura);
    // triángulo de soldadura en ángulo (lado de la flecha: bajo la línea)
    final sx = kx + dir * 9;
    poly([sx, ky, sx, ky - 3.2, sx + 3.2, ky], CadLayer.soldadura, closed: true);
    if (bothSides) poly([sx, ky, sx, ky + 3.2, sx + 3.2, ky], CadLayer.soldadura, closed: true);
    text(sx - 1, ky - 1.6, throat, 2.5, layer: CadLayer.soldadura, hAlign: 1, vAlign: 0);
    if (length.isNotEmpty) text(sx + 4.2, ky - 1.6, length, 2.5, layer: CadLayer.soldadura, vAlign: 0);
    if (process.isNotEmpty) {
      // cola
      line(rx, ky, rx + dir * 3, ky + 3, CadLayer.soldadura);
      line(rx, ky, rx + dir * 3, ky - 3, CadLayer.soldadura);
      text(rx + dir * 4, ky, process, 2.5, layer: CadLayer.soldadura, vAlign: 0, hAlign: dir > 0 ? -1 : 1);
    }
  }

  /// Escala gráfica en metros.
  void scaleBar(double x, double y) {
    if (scale <= 0) return;
    // longitud redonda de unos 40–80 mm de papel
    final mPerMm = scale / 1000.0;
    final steps = [0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0];
    var seg = steps.first;
    for (final s in steps) {
      if (s / mPerMm >= 10) {
        seg = s;
        break;
      }
      seg = s;
    }
    final segMm = seg / mPerMm;
    for (var i = 0; i < 4; i++) {
      rect(x + i * segMm, y, x + (i + 1) * segMm, y + 1.5, CadLayer.fino, fill: i.isEven);
    }
    for (var i = 0; i <= 4; i += 2) {
      final v = seg * i;
      text(x + i * segMm, y + 2.5, '${v == v.roundToDouble() ? v.round() : v.toStringAsFixed(1).replaceAll('.', ',')}',
          2, hAlign: 0);
    }
    text(x + 4 * segMm + 3, y + 0.2, 'm', 2.2);
  }

  /// Caja envolvente de las entidades (mm de papel).
  (double, double, double, double) get bounds {
    var x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
    void add(double x, double y) {
      x0 = math.min(x0, x);
      y0 = math.min(y0, y);
      x1 = math.max(x1, x);
      y1 = math.max(y1, y);
    }

    for (final e in ents) {
      switch (e) {
        case CLine():
          add(e.x1, e.y1);
          add(e.x2, e.y2);
        case CPoly():
          for (var i = 0; i + 1 < e.pts.length; i += 2) {
            add(e.pts[i], e.pts[i + 1]);
          }
        case CCircle():
          add(e.cx - e.r, e.cy - e.r);
          add(e.cx + e.r, e.cy + e.r);
        case CText():
          add(e.x, e.y);
      }
    }
    return (x0, y0, x1, y1);
  }
}

/// Escalas normalizadas (UNE-EN ISO 5455).
const List<int> standardScales = [1, 2, 5, 10, 15, 20, 25, 50, 75, 100, 125, 150, 200, 250, 300, 400, 500, 750, 1000];

/// Escala normalizada mínima para que un objeto de [wM] x [hM] metros quepa
/// en [wMm] x [hMm] mm de papel.
int fitScale(double wM, double hM, double wMm, double hMm) {
  for (final s in standardScales) {
    if (wM * 1000 / s <= wMm && hM * 1000 / s <= hMm) return s;
  }
  return standardScales.last;
}
