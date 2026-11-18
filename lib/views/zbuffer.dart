import 'dart:math' as math;
import 'dart:typed_data';

/// Rasterizador por software con z-buffer por píxel, mapa de sombras y
/// sombreado diferido. Sustituye al "algoritmo del pintor" (ordenar
/// triángulos), que producía superposiciones incorrectas.
///
/// Todo trabaja con listas tipadas para poder ejecutarse en un isolate.

/// Datos por triángulo en [ZScene.data].
const int zStride = 20;
// 0..8  vértices a, b, c
// 9..11 normal (unitaria)
// 12..14 albedo (lineal)
// 15 especular, 16 alfa (1 = opaco), 17 patrón, 18 proyecta sombra (0/1), 19 libre

/// Patrones procedurales de superficie.
abstract final class ZPattern {
  static const int none = 0;
  static const int grating = 1; // tramex
  static const int ribbed = 2; // chapa grecada / ondulada
  static const int sandwich = 3; // panel sándwich
  static const int tile = 4; // teja
  static const int solar = 5; // paneles fotovoltaicos
  static const int checker = 6; // chapa lagrimada
  static const int wood = 7; // tablero / madera
  static const int concrete = 8; // hormigón
}

class ZScene {
  final Float32List data;
  final int count;
  final double cx, cy, cz, radius;
  final bool tall;
  const ZScene(this.data, this.count, this.cx, this.cy, this.cz, this.radius, this.tall);
}

class ZView {
  final int width, height;
  final int ss; // supermuestreo (1 = sin antialias, 2 = 4 muestras/píxel)
  final double yaw, pitch, distance, sunAzimuth;
  final int shadowRes;
  final bool softShadows;
  final bool vignette;
  const ZView({
    required this.width,
    required this.height,
    this.ss = 1,
    this.yaw = -0.85,
    this.pitch = 0.32,
    this.distance = 2.3,
    this.sunAzimuth = 0.9,
    this.shadowRes = 1536,
    this.softShadows = true,
    this.vignette = true,
  });
}

double _frac(double x) => x - x.floorToDouble();

/// Hash 2D barato y determinista en [0, 1).
double _hash(int a, int b) {
  var h = (a * 374761393 + b * 668265263) & 0x7fffffff;
  h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff;
  return (h & 0xffff) / 65536.0;
}

/// Ruido de valor suave (interpolación bilineal con smoothstep) en [0, 1).
double _vnoise(double x, double y) {
  final ix = x.floor(), iy = y.floor();
  var fx = x - ix, fy = y - iy;
  fx = fx * fx * (3 - 2 * fx);
  fy = fy * fy * (3 - 2 * fy);
  final a = _hash(ix, iy), b = _hash(ix + 1, iy), c = _hash(ix, iy + 1), d = _hash(ix + 1, iy + 1);
  return (a + (b - a) * fx) * (1 - fy) + (c + (d - c) * fx) * fy;
}

/// Renderiza la escena y devuelve una imagen RGBA de width x height.
Uint8List renderZ(ZScene s, ZView v) {
  final ss = v.ss.clamp(1, 3);
  final W = v.width * ss, H = v.height * ss;
  final d = s.data;
  final n = s.count;
  final r = s.radius <= 0 ? 1.0 : s.radius;

  // ---------------- Cámara ----------------
  final tx = s.cx, ty = s.cy, tz = s.cz + (s.tall ? 0 : -r * 0.08);
  final dist = r * v.distance * (s.tall ? 1.2 : 1.0);
  final cp = math.cos(v.pitch);
  final ex = tx + cp * math.cos(v.yaw) * dist;
  final ey = ty + cp * math.sin(v.yaw) * dist;
  final ez = tz + math.sin(v.pitch) * dist;
  var fx = tx - ex, fy = ty - ey, fz = tz - ez;
  var l = math.sqrt(fx * fx + fy * fy + fz * fz);
  fx /= l;
  fy /= l;
  fz /= l;
  // right = fwd x Z
  var rx = fy, ry = -fx, rz = 0.0;
  l = math.sqrt(rx * rx + ry * ry);
  if (l < 1e-9) {
    rx = 1;
    ry = 0;
    l = 1;
  }
  rx /= l;
  ry /= l;
  // up = right x fwd
  final ux = ry * fz - rz * fy, uy = rz * fx - rx * fz, uz = rx * fy - ry * fx;
  final focal = H / (2 * math.tan(25 * math.pi / 180));
  final cxs = W / 2, cys = H / 2;
  const near = 0.05;

  // ---------------- Sol y mapa de sombras ----------------
  var sx = math.cos(v.sunAzimuth) * 0.55, sy = math.sin(v.sunAzimuth) * 0.55, sz = 0.78;
  l = math.sqrt(sx * sx + sy * sy + sz * sz);
  sx /= l;
  sy /= l;
  sz /= l;
  // base ortonormal del sol: su (horizontal), sv
  var aux = sy, auy = -sx, auz = 0.0;
  l = math.sqrt(aux * aux + auy * auy);
  if (l < 1e-6) {
    aux = 1;
    auy = 0;
    l = 1;
  }
  aux /= l;
  auy /= l;
  final avx = auy * sz - auz * sy, avy = auz * sx - aux * sz, avz = aux * sy - auy * sx;
  final sr = v.shadowRes;
  final ext = r * 1.35;
  final suC = s.cx * aux + s.cy * auy + s.cz * auz;
  final svC = s.cx * avx + s.cy * avy + s.cz * avz;
  final sScale = sr / (2 * ext);
  final sm = Float32List(sr * sr)..fillRange(0, sr * sr, -1e30);

  void shadowTri(double x0, double y0, double z0, double x1, double y1, double z1, double x2, double y2,
      double z2) {
    final area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0);
    if (area.abs() < 1e-12) return;
    final inv = 1 / area;
    final minX = math.max(0, math.min(x0, math.min(x1, x2)).floor());
    final maxX = math.min(sr - 1, math.max(x0, math.max(x1, x2)).ceil());
    final minY = math.max(0, math.min(y0, math.min(y1, y2)).floor());
    final maxY = math.min(sr - 1, math.max(y0, math.max(y1, y2)).ceil());
    for (var y = minY; y <= maxY; y++) {
      final py = y + 0.5;
      for (var x = minX; x <= maxX; x++) {
        final px = x + 0.5;
        final w0 = ((x1 - px) * (y2 - py) - (x2 - px) * (y1 - py)) * inv;
        final w1 = ((x2 - px) * (y0 - py) - (x0 - px) * (y2 - py)) * inv;
        final w2 = 1 - w0 - w1;
        if (w0 < -1e-4 || w1 < -1e-4 || w2 < -1e-4) continue;
        final z = w0 * z0 + w1 * z1 + w2 * z2;
        final k = y * sr + x;
        if (z > sm[k]) sm[k] = z;
      }
    }
  }

  for (var t = 0; t < n; t++) {
    final o = t * zStride;
    if (d[o + 18] < 0.5 || d[o + 16] < 0.99) continue;
    final p = <double>[];
    for (var k = 0; k < 3; k++) {
      final px = d[o + k * 3], py = d[o + k * 3 + 1], pz = d[o + k * 3 + 2];
      p
        ..add(((px * aux + py * auy + pz * auz) - suC + ext) * sScale)
        ..add((ext - ((px * avx + py * avy + pz * avz) - svC)) * sScale)
        ..add(px * sx + py * sy + pz * sz);
    }
    shadowTri(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8]);
  }

  /// Visibilidad del sol en un punto (0 = sombra, 1 = sol).
  double sunVis(double px, double py, double pz, bool soft) {
    final u = (((px * aux + py * auy + pz * auz) - suC + ext) * sScale);
    final w = ((ext - ((px * avx + py * avy + pz * avz) - svC)) * sScale);
    final dd = px * sx + py * sy + pz * sz;
    final bias = 0.02 + 1.5 / sScale;
    if (!soft) {
      final iu = u.floor(), iv = w.floor();
      if (iu < 0 || iv < 0 || iu >= sr || iv >= sr) return 1;
      return sm[iv * sr + iu] > dd + bias ? 0 : 1;
    }
    var lit = 0.0;
    for (var j = -1; j <= 1; j++) {
      for (var i = -1; i <= 1; i++) {
        final iu = (u + i * 0.9).floor(), iv = (w + j * 0.9).floor();
        if (iu < 0 || iv < 0 || iu >= sr || iv >= sr) {
          lit += 1;
        } else if (sm[iv * sr + iu] <= dd + bias) {
          lit += 1;
        }
      }
    }
    return lit / 9;
  }

  // ---------------- Pasada opaca: z-buffer + id ----------------
  final npx = W * H;
  final depth = Float32List(npx); // 1/z (0 = vacío)
  final ids = Int32List(npx)..fillRange(0, npx, -1);

  // Transforma un vértice a coordenadas de cámara.
  final cam = Float64List(12);
  // Rasteriza un triángulo ya en pantalla (x, y, 1/z).
  void rasterTri(double x0, double y0, double w0, double x1, double y1, double w1, double x2, double y2, double w2,
      int id) {
    final area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0);
    if (area.abs() < 1e-12) return;
    final inv = 1 / area;
    final minX = math.max(0, math.min(x0, math.min(x1, x2)).floor());
    final maxX = math.min(W - 1, math.max(x0, math.max(x1, x2)).ceil());
    final minY = math.max(0, math.min(y0, math.min(y1, y2)).floor());
    final maxY = math.min(H - 1, math.max(y0, math.max(y1, y2)).ceil());
    if (minX > maxX || minY > maxY) return;
    for (var y = minY; y <= maxY; y++) {
      final py = y + 0.5;
      // pesos en x = minX y paso por píxel
      var b0 = ((x1 - (minX + 0.5)) * (y2 - py) - (x2 - (minX + 0.5)) * (y1 - py)) * inv;
      var b1 = ((x2 - (minX + 0.5)) * (y0 - py) - (x0 - (minX + 0.5)) * (y2 - py)) * inv;
      final db0 = -(y2 - y1) * inv;
      final db1 = -(y0 - y2) * inv;
      final row = y * W;
      for (var x = minX; x <= maxX; x++) {
        final b2 = 1 - b0 - b1;
        if (b0 >= -1e-7 && b1 >= -1e-7 && b2 >= -1e-7) {
          final iz = b0 * w0 + b1 * w1 + b2 * w2;
          final k = row + x;
          if (iz > depth[k]) {
            depth[k] = iz;
            ids[k] = id;
          }
        }
        b0 += db0;
        b1 += db1;
      }
    }
  }

  /// Recorta contra el plano cercano y proyecta; llama a [emit] por triángulo.
  void clipProject(int t, void Function(double, double, double, double, double, double, double, double, double) emit) {
    final o = t * zStride;
    for (var k = 0; k < 3; k++) {
      final vx = d[o + k * 3] - ex, vy = d[o + k * 3 + 1] - ey, vz = d[o + k * 3 + 2] - ez;
      cam[k * 3] = vx * rx + vy * ry + vz * rz;
      cam[k * 3 + 1] = vx * ux + vy * uy + vz * uz;
      cam[k * 3 + 2] = vx * fx + vy * fy + vz * fz;
    }
    final z0 = cam[2], z1 = cam[5], z2 = cam[8];
    if (z0 < near && z1 < near && z2 < near) return;
    // polígono recortado (hasta 4 vértices)
    final poly = <double>[];
    for (var k = 0; k < 3; k++) {
      final a = k, b = (k + 1) % 3;
      final ax = cam[a * 3], ay = cam[a * 3 + 1], az = cam[a * 3 + 2];
      final bx = cam[b * 3], by = cam[b * 3 + 1], bz = cam[b * 3 + 2];
      if (az >= near) poly.addAll([ax, ay, az]);
      if ((az >= near) != (bz >= near)) {
        final tt = (near - az) / (bz - az);
        poly.addAll([ax + (bx - ax) * tt, ay + (by - ay) * tt, near]);
      }
    }
    final m = poly.length ~/ 3;
    if (m < 3) return;
    final scr = Float64List(m * 3);
    for (var k = 0; k < m; k++) {
      final z = poly[k * 3 + 2];
      scr[k * 3] = cxs + poly[k * 3] * focal / z;
      scr[k * 3 + 1] = cys - poly[k * 3 + 1] * focal / z;
      scr[k * 3 + 2] = 1 / z;
    }
    for (var k = 1; k + 1 < m; k++) {
      emit(scr[0], scr[1], scr[2], scr[k * 3], scr[k * 3 + 1], scr[k * 3 + 2], scr[k * 3 + 3], scr[k * 3 + 4],
          scr[k * 3 + 5]);
    }
  }

  final transparent = <int>[];
  for (var t = 0; t < n; t++) {
    if (d[t * zStride + 16] < 0.99) {
      transparent.add(t);
      continue;
    }
    clipProject(t, (a, b, c, e, f, g, h, i, j) => rasterTri(a, b, c, e, f, g, h, i, j, t));
  }

  // ---------------- Sombreado ----------------
  const sunR = 1.0, sunG = 0.95, sunB = 0.86;
  const skyR = 0.55, skyG = 0.65, skyB = 0.78;
  const gndR = 0.42, gndG = 0.40, gndB = 0.36;
  const fogR = 0.85, fogG = 0.89, fogB = 0.93;
  final col = Float32List(npx * 3);
  final slab = r * 1.25;
  final jointStep = math.max(2.0, (slab / 6).roundToDouble());
  final soft = v.softShadows;

  /// Color de una superficie en el punto p (devuelve en out[0..2]).
  final out = Float64List(3);
  void shade(int t, double px, double py, double pz, double zc, double dx, double dy, double dz) {
    final o = t * zStride;
    var nx = d[o + 9], ny = d[o + 10], nz = d[o + 11];
    // caras de doble cara: la normal mira al observador
    if (nx * dx + ny * dy + nz * dz > 0) {
      nx = -nx;
      ny = -ny;
      nz = -nz;
    }
    var ar = d[o + 12], ag = d[o + 13], ab = d[o + 14];
    final spc = d[o + 15];
    final pat = d[o + 17].round();
    if (pat != ZPattern.none) {
      final fp = zc / focal * 2.5; // tamaño del píxel en metros (aprox.)
      // coordenada a lo largo de la superficie, horizontal (nervios / juntas)
      var tx2 = ny, ty2 = -nx; // n x Z
      final tl = math.sqrt(tx2 * tx2 + ty2 * ty2);
      double uC, vC;
      if (tl < 0.25) {
        // superficie casi horizontal: ejes del mundo
        uC = px;
        vC = py;
      } else {
        tx2 /= tl;
        ty2 /= tl;
        uC = px * tx2 + py * ty2;
        vC = pz;
      }
      double k = 1;
      switch (pat) {
        case ZPattern.grating:
          final cell = 0.034;
          if (fp > cell * 0.7) {
            k = 0.62;
          } else {
            final a = _frac(uC / cell), b = _frac(vC / cell);
            k = (a < 0.18 || b < 0.10) ? 1.0 : 0.30;
          }
          break;
        case ZPattern.ribbed:
          final pr = 0.25;
          if (fp < pr * 0.6) {
            final a = _frac(uC / pr);
            k = a < 0.22 ? 0.84 + 0.3 * (a / 0.22 - 0.5).abs() : (a < 0.3 ? 1.06 : 1.0);
          } else {
            k = 0.97;
          }
          break;
        case ZPattern.sandwich:
          final a = _frac(uC / 0.333);
          if (fp < 0.2) {
            k = a < 0.12 ? 0.88 : 1.0;
            if (_frac(uC / 1.0) < 0.012) k = 0.7;
          }
          break;
        case ZPattern.tile:
          final row = (vC / 0.33).floor();
          final a = _frac(vC / 0.33), b = _frac(uC / 0.2 + (row.isOdd ? 0.5 : 0));
          k = (a < 0.08 ? 0.55 : 1.0) * (0.85 + 0.25 * math.sin(b * math.pi));
          k *= 0.9 + 0.2 * _hash(row, (uC / 0.2).floor());
          break;
        case ZPattern.solar:
          final a = _frac(uC / 1.134), b = _frac(vC / 1.722);
          if (a < 0.02 || b < 0.015) {
            ar = 0.55;
            ag = 0.57;
            ab = 0.60;
          } else if (fp < 0.05 && (_frac(uC / 0.1815) < 0.04 || _frac(vC / 0.1815) < 0.04)) {
            k = 1.6;
          }
          break;
        case ZPattern.checker:
          if (fp < 0.02) {
            final a = _frac(uC / 0.03 + vC / 0.03), b = _frac(uC / 0.03 - vC / 0.03);
            k = (a < 0.18 && b < 0.5) ? 1.15 : 0.96;
          }
          break;
        case ZPattern.wood:
          final plank = (vC / 0.145).floor();
          k = 0.85 + 0.3 * _hash(plank, 7);
          if (_frac(vC / 0.145) < 0.05) k *= 0.6;
          break;
        case ZPattern.concrete:
          k = 0.93 + 0.1 * _vnoise(px * 3 + pz * 2, py * 3 + pz * 2);
          break;
      }
      ar *= k;
      ag *= k;
      ab *= k;
    }
    final ndl = math.max(0.0, nx * sx + ny * sy + nz * sz);
    final vis = ndl > 0 ? sunVis(px + nx * 0.01, py + ny * 0.01, pz + nz * 0.01, soft) : 0.0;
    // vector al ojo
    final vx = -dx, vy = -dy, vz = -dz;
    var hx = sx + vx, hy = sy + vy, hz = sz + vz;
    final hl = math.sqrt(hx * hx + hy * hy + hz * hz);
    hx /= hl;
    hy /= hl;
    hz /= hl;
    final spec = math.pow(math.max(0.0, nx * hx + ny * hy + nz * hz), 40) * spc * vis;
    final hemi = 0.5 + 0.5 * nz;
    final amr = skyR * hemi + gndR * (1 - hemi);
    final amg = skyG * hemi + gndG * (1 - hemi);
    final amb = skyB * hemi + gndB * (1 - hemi);
    final ao = 0.75 + 0.25 * math.min(1.0, pz / 1.5);
    final fres = math.pow(1 - math.max(0.0, nx * vx + ny * vy + nz * vz), 4) * 0.25;
    final dl = ndl * vis * 1.05;
    // reflejo del entorno (cielo arriba, suelo abajo) en metales pulidos o
    // satinados: da el brillo del inox y el aluminio aunque estén a la sombra
    final ndv = nx * vx + ny * vy + nz * vz;
    final rz = 2 * ndv * nz - vz;
    final hr = 0.5 + 0.5 * rz;
    final env = spc * spc * 0.45 * ao;
    var cr = ar * (sunR * dl + amr * 0.55 * ao) + spec + fres * skyR + env * (skyR * hr + gndR * (1 - hr) * 1.4);
    var cg = ag * (sunG * dl + amg * 0.55 * ao) + spec + fres * skyG + env * (skyG * hr + gndG * (1 - hr) * 1.4);
    var cb = ab * (sunB * dl + amb * 0.55 * ao) + spec + fres * skyB + env * (skyB * hr + gndB * (1 - hr) * 1.4);
    final fog = (1 - math.exp(-zc / (r * 9))).clamp(0.0, 0.5);
    out[0] = cr * (1 - fog) + fogR * fog;
    out[1] = cg * (1 - fog) + fogG * fog;
    out[2] = cb * (1 - fog) + fogB * fog;
  }

  for (var y = 0; y < H; y++) {
    for (var x = 0; x < W; x++) {
      final k = y * W + x;
      // dirección del rayo (componente fwd = 1)
      final a = (x + 0.5 - cxs) / focal, b = (cys - (y + 0.5)) / focal;
      final dx = fx + rx * a + ux * b, dy = fy + ry * a + uy * b, dz = fz + rz * a + uz * b;
      final id = ids[k];
      if (id >= 0) {
        final zc = 1 / depth[k];
        final dl = math.sqrt(dx * dx + dy * dy + dz * dz);
        shade(id, ex + dx * zc, ey + dy * zc, ez + dz * zc, zc, dx / dl, dy / dl, dz / dl);
        col[k * 3] = out[0];
        col[k * 3 + 1] = out[1];
        col[k * 3 + 2] = out[2];
        continue;
      }
      // fondo: suelo o cielo
      final dl = math.sqrt(dx * dx + dy * dy + dz * dz);
      final el = dz / dl;
      if (dz < 0 && ez > 0) {
        final tg = -ez / dz;
        final gx = ex + dx * tg, gy = ey + dy * tg;
        final zc = tg; // distancia a lo largo de fwd (componente 1)
        double cr, cg, cb;
        final inSlab = (gx - s.cx).abs() <= slab && (gy - s.cy).abs() <= slab;
        if (inSlab) {
          cr = 0.655;
          cg = 0.643;
          cb = 0.612;
          final fp = zc / focal * 2;
          if (fp < 0.05) {
            final ja = _frac((gx - s.cx + slab) / jointStep), jb = _frac((gy - s.cy + slab) / jointStep);
            final jw = 0.012 / jointStep;
            if (ja < jw || jb < jw) {
              cr *= 0.86;
              cg *= 0.86;
              cb *= 0.86;
            }
          }
          final nse = 0.97 + 0.05 * _vnoise(gx * 1.3, gy * 1.3) + 0.02 * _vnoise(gx * 7, gy * 7);
          cr *= nse;
          cg *= nse;
          cb *= nse;
        } else {
          final nse = 0.88 + 0.14 * _vnoise(gx * 0.6, gy * 0.6) + 0.06 * _vnoise(gx * 4, gy * 4);
          cr = 0.56 * nse;
          cg = 0.53 * nse;
          cb = 0.46 * nse;
        }
        final vis = (gx - s.cx).abs() < ext * 1.2 && (gy - s.cy).abs() < ext * 1.2 ? sunVis(gx, gy, 0.001, soft) : 1.0;
        final sh = 0.62 + 0.38 * vis;
        cr *= sh;
        cg *= sh;
        cb *= sh;
        // niebla hacia el horizonte
        final fog = (1 - math.exp(-zc / (r * 7))).clamp(0.0, 1.0);
        col[k * 3] = cr * (1 - fog) + fogR * fog;
        col[k * 3 + 1] = cg * (1 - fog) + fogG * fog;
        col[k * 3 + 2] = cb * (1 - fog) + fogB * fog;
      } else {
        // cielo: degradado por elevación
        final e = el.clamp(0.0, 1.0);
        double cr, cg, cb;
        if (e < 0.18) {
          final q = e / 0.18;
          cr = 0.910 + (0.725 - 0.910) * q;
          cg = 0.933 + (0.827 - 0.933) * q;
          cb = 0.949 + (0.918 - 0.949) * q;
        } else {
          final q = math.min(1.0, (e - 0.18) / 0.45);
          cr = 0.725 + (0.357 - 0.725) * q;
          cg = 0.827 + (0.561 - 0.827) * q;
          cb = 0.918 + (0.780 - 0.918) * q;
        }
        // valores ya en sRGB: se guardan como "lineal" invirtiendo el tonemapping aproximado
        col[k * 3] = -cr;
        col[k * 3 + 1] = cg;
        col[k * 3 + 2] = cb;
      }
    }
  }

  // ---------------- Pasada transparente (policarbonato, vidrio, malla) ----------------
  if (transparent.isNotEmpty) {
    // de atrás hacia delante
    final keyed = <(double, int)>[];
    for (final t in transparent) {
      final o = t * zStride;
      final mx = (d[o] + d[o + 3] + d[o + 6]) / 3 - ex;
      final my = (d[o + 1] + d[o + 4] + d[o + 7]) / 3 - ey;
      final mz = (d[o + 2] + d[o + 5] + d[o + 8]) / 3 - ez;
      keyed.add((mx * fx + my * fy + mz * fz, t));
    }
    keyed.sort((a, b) => b.$1.compareTo(a.$1));
    for (final (_, t) in keyed) {
      final alpha = d[t * zStride + 16];
      clipProject(t, (x0, y0, w0, x1, y1, w1, x2, y2, w2) {
        final area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0);
        if (area.abs() < 1e-12) return;
        final inv = 1 / area;
        final minX = math.max(0, math.min(x0, math.min(x1, x2)).floor());
        final maxX = math.min(W - 1, math.max(x0, math.max(x1, x2)).ceil());
        final minY = math.max(0, math.min(y0, math.min(y1, y2)).floor());
        final maxY = math.min(H - 1, math.max(y0, math.max(y1, y2)).ceil());
        for (var y = minY; y <= maxY; y++) {
          final py = y + 0.5;
          for (var x = minX; x <= maxX; x++) {
            final px = x + 0.5;
            final b0 = ((x1 - px) * (y2 - py) - (x2 - px) * (y1 - py)) * inv;
            final b1 = ((x2 - px) * (y0 - py) - (x0 - px) * (y2 - py)) * inv;
            final b2 = 1 - b0 - b1;
            if (b0 < -1e-7 || b1 < -1e-7 || b2 < -1e-7) continue;
            final iz = b0 * w0 + b1 * w1 + b2 * w2;
            final k = y * W + x;
            if (iz <= depth[k]) continue; // detrás de algo opaco
            final zc = 1 / iz;
            final a = (px - cxs) / focal, b = (cys - py) / focal;
            final dx = fx + rx * a + ux * b, dy = fy + ry * a + uy * b, dz = fz + rz * a + uz * b;
            final dl = math.sqrt(dx * dx + dy * dy + dz * dz);
            shade(t, ex + dx * zc, ey + dy * zc, ez + dz * zc, zc, dx / dl, dy / dl, dz / dl);
            var br = col[k * 3], bg = col[k * 3 + 1], bb = col[k * 3 + 2];
            if (br < 0) {
              // el fondo era cielo en sRGB: se pasa a "lineal" aproximado
              br = _untone(-br);
              bg = _untone(bg);
              bb = _untone(bb);
            }
            col[k * 3] = out[0] * alpha + br * (1 - alpha);
            col[k * 3 + 1] = out[1] * alpha + bg * (1 - alpha);
            col[k * 3 + 2] = out[2] * alpha + bb * (1 - alpha);
          }
        }
      });
    }
  }

  // ---------------- Tonemapping, viñeteado y reducción ----------------
  final res = Uint8List(v.width * v.height * 4);
  final inv = 1 / (ss * ss);
  final lc = Int32List(4096);
  for (var i = 0; i < 4096; i++) {
    final m = (i / 1024.0);
    final t = m / (1 + m * 0.35);
    lc[i] = (math.pow(t.clamp(0.0, 1.0), 1 / 1.15) * 255).round();
  }
  int tone(double x) {
    if (x <= 0) return 0;
    final i = (x * 1024).round();
    return i >= 4096 ? lc[4095] : lc[i];
  }

  final vcx = v.width / 2, vcy = v.height / 2;
  final vr = math.max(v.width, v.height) * 0.75;
  for (var y = 0; y < v.height; y++) {
    for (var x = 0; x < v.width; x++) {
      var r8 = 0.0, g8 = 0.0, b8 = 0.0;
      for (var j = 0; j < ss; j++) {
        for (var i = 0; i < ss; i++) {
          final k = ((y * ss + j) * W + (x * ss + i)) * 3;
          final cr = col[k];
          if (cr < 0) {
            r8 += -cr * 255;
            g8 += col[k + 1] * 255;
            b8 += col[k + 2] * 255;
          } else {
            r8 += tone(cr);
            g8 += tone(col[k + 1]);
            b8 += tone(col[k + 2]);
          }
        }
      }
      var f = inv;
      if (v.vignette) {
        final dd = math.sqrt((x - vcx) * (x - vcx) + (y - vcy) * (y - vcy)) / vr;
        if (dd > 0.6) f *= 1 - 0.25 * math.min(1.0, (dd - 0.6) / 0.4);
      }
      final o = (y * v.width + x) * 4;
      res[o] = (r8 * f).round().clamp(0, 255);
      res[o + 1] = (g8 * f).round().clamp(0, 255);
      res[o + 2] = (b8 * f).round().clamp(0, 255);
      res[o + 3] = 255;
    }
  }
  return res;
}

/// Inversa aproximada del tonemapping (sRGB 0..1 → valor "lineal").
double _untone(double s) {
  final t = math.pow(s.clamp(0.0, 0.999), 1.15).toDouble();
  return t / (1 - t * 0.35);
}
