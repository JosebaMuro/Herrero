import 'dart:math' as math;

/// Familia de perfil comercial.
enum ProfileFamily { ipe, heb, shs, angle }

/// Perfil de acero laminado o conformado con sus propiedades mecánicas.
/// Unidades: mm para dimensiones, cm² / cm⁴ / cm³ / cm para propiedades
/// estáticas (como en los prontuarios), kg/m para el peso.
class SteelProfile {
  final String name;
  final ProfileFamily family;
  final double h; // canto (mm)
  final double b; // ancho de ala (mm)
  final double tw; // espesor de alma (mm)
  final double tf; // espesor de ala (mm)
  final double area; // cm²
  final double iy; // inercia eje fuerte cm⁴
  final double wply; // módulo plástico eje fuerte cm³
  final double iz; // inercia eje débil cm⁴
  final double kgm; // kg/m

  const SteelProfile({
    required this.name,
    required this.family,
    required this.h,
    required this.b,
    required this.tw,
    required this.tf,
    required this.area,
    required this.iy,
    required this.wply,
    required this.iz,
    required this.kgm,
  });

  /// Radio de giro eje fuerte (cm)
  double get ry => math.sqrt(iy / area);

  /// Radio de giro eje débil (cm)
  double get rz => math.sqrt(iz / area);

  /// Superficie a pintar por metro lineal (m²/m), aproximada.
  double get paintAreaPerM {
    switch (family) {
      case ProfileFamily.ipe:
      case ProfileFamily.heb:
        return (2 * h + 4 * b - 2 * tw) / 1000;
      case ProfileFamily.shs:
        return 4 * b / 1000;
      case ProfileFamily.angle:
        return 4 * b / 1000;
    }
  }

  /// Espesor mínimo de las chapas que forman el perfil (para soldadura).
  double get tMin => math.min(tw, tf);

  bool get isHollow => family == ProfileFamily.shs;

  @override
  String toString() => name;
}

SteelProfile _ipe(String n, double h, double b, double tw, double tf, double a,
        double iy, double wpl, double iz, double kg) =>
    SteelProfile(
        name: n,
        family: ProfileFamily.ipe,
        h: h,
        b: b,
        tw: tw,
        tf: tf,
        area: a,
        iy: iy,
        wply: wpl,
        iz: iz,
        kgm: kg);

SteelProfile _heb(String n, double h, double b, double tw, double tf, double a,
        double iy, double wpl, double iz, double kg) =>
    SteelProfile(
        name: n,
        family: ProfileFamily.heb,
        h: h,
        b: b,
        tw: tw,
        tf: tf,
        area: a,
        iy: iy,
        wply: wpl,
        iz: iz,
        kgm: kg);

/// Tubo cuadrado (SHS) — propiedades calculadas a partir de la geometría
/// (esquinas vivas, ligeramente conservador en inercia).
SteelProfile _shs(double b, double t) {
  final bi = b - 2 * t;
  final areaMm2 = b * b - bi * bi;
  final iMm4 = (math.pow(b, 4) - math.pow(bi, 4)) / 12;
  final wplMm3 = (math.pow(b, 3) - math.pow(bi, 3)) / 4;
  return SteelProfile(
    name: 'SHS ${b.toStringAsFixed(0)}x${t.toStringAsFixed(t % 1 == 0 ? 0 : 1)}',
    family: ProfileFamily.shs,
    h: b,
    b: b,
    tw: t,
    tf: t,
    area: areaMm2 / 100,
    iy: iMm4 / 1e4,
    wply: wplMm3 / 1e3,
    iz: iMm4 / 1e4,
    kgm: areaMm2 * 7850 / 1e6,
  );
}

/// Angular de lados iguales (L).
SteelProfile _l(double b, double t) {
  final areaMm2 = t * (2 * b - t);
  // Inercia respecto a eje débil (v) aproximada: A·(0.195·b)²
  final iv = areaMm2 * math.pow(0.195 * b, 2);
  return SteelProfile(
    name: 'L ${b.toStringAsFixed(0)}x${t.toStringAsFixed(0)}',
    family: ProfileFamily.angle,
    h: b,
    b: b,
    tw: t,
    tf: t,
    area: areaMm2 / 100,
    iy: iv * 2.5 / 1e4,
    wply: 0,
    iz: iv / 1e4,
    kgm: areaMm2 * 7850 / 1e6,
  );
}

/// Catálogo IPE (UNE-EN 10365 / prontuario).
final List<SteelProfile> ipeTable = [
  _ipe('IPE 80', 80, 46, 3.8, 5.2, 7.64, 80.1, 23.2, 8.49, 6.0),
  _ipe('IPE 100', 100, 55, 4.1, 5.7, 10.3, 171, 39.4, 15.9, 8.1),
  _ipe('IPE 120', 120, 64, 4.4, 6.3, 13.2, 318, 60.7, 27.7, 10.4),
  _ipe('IPE 140', 140, 73, 4.7, 6.9, 16.4, 541, 88.3, 44.9, 12.9),
  _ipe('IPE 160', 160, 82, 5.0, 7.4, 20.1, 869, 124, 68.3, 15.8),
  _ipe('IPE 180', 180, 91, 5.3, 8.0, 23.9, 1317, 166, 101, 18.8),
  _ipe('IPE 200', 200, 100, 5.6, 8.5, 28.5, 1943, 221, 142, 22.4),
  _ipe('IPE 220', 220, 110, 5.9, 9.2, 33.4, 2772, 285, 205, 26.2),
  _ipe('IPE 240', 240, 120, 6.2, 9.8, 39.1, 3892, 367, 284, 30.7),
  _ipe('IPE 270', 270, 135, 6.6, 10.2, 45.9, 5790, 484, 420, 36.1),
  _ipe('IPE 300', 300, 150, 7.1, 10.7, 53.8, 8356, 628, 604, 42.2),
  _ipe('IPE 330', 330, 160, 7.5, 11.5, 62.6, 11770, 804, 788, 49.1),
  _ipe('IPE 360', 360, 170, 8.0, 12.7, 72.7, 16270, 1019, 1043, 57.1),
  _ipe('IPE 400', 400, 180, 8.6, 13.5, 84.5, 23130, 1307, 1318, 66.3),
  _ipe('IPE 450', 450, 190, 9.4, 14.6, 98.8, 33740, 1702, 1676, 77.6),
  _ipe('IPE 500', 500, 200, 10.2, 16.0, 116, 48200, 2194, 2142, 90.7),
  _ipe('IPE 550', 550, 210, 11.1, 17.2, 134, 67120, 2787, 2668, 106),
  _ipe('IPE 600', 600, 220, 12.0, 19.0, 156, 92080, 3512, 3387, 122),
];

/// Catálogo HEB.
final List<SteelProfile> hebTable = [
  _heb('HEB 100', 100, 100, 6, 10, 26.0, 450, 104, 167, 20.4),
  _heb('HEB 120', 120, 120, 6.5, 11, 34.0, 864, 165, 318, 26.7),
  _heb('HEB 140', 140, 140, 7, 12, 43.0, 1509, 245, 550, 33.7),
  _heb('HEB 160', 160, 160, 8, 13, 54.3, 2492, 354, 889, 42.6),
  _heb('HEB 180', 180, 180, 8.5, 14, 65.3, 3831, 481, 1363, 51.2),
  _heb('HEB 200', 200, 200, 9, 15, 78.1, 5696, 643, 2003, 61.3),
  _heb('HEB 220', 220, 220, 9.5, 16, 91.0, 8091, 827, 2843, 71.5),
  _heb('HEB 240', 240, 240, 10, 17, 106, 11260, 1053, 3923, 83.2),
  _heb('HEB 260', 260, 260, 10, 17.5, 118, 14920, 1283, 5135, 93.0),
  _heb('HEB 280', 280, 280, 10.5, 18, 131, 19270, 1534, 6595, 103),
  _heb('HEB 300', 300, 300, 11, 19, 149, 25170, 1869, 8563, 117),
  _heb('HEB 340', 340, 300, 12, 21.5, 171, 36660, 2408, 9690, 134),
  _heb('HEB 400', 400, 300, 13.5, 24, 198, 57680, 3232, 10820, 155),
];

/// Catálogo de tubo cuadrado.
final List<SteelProfile> shsTable = [
  _shs(20, 1.5),
  _shs(30, 2),
  _shs(40, 2),
  _shs(40, 3),
  _shs(50, 3),
  _shs(60, 3),
  _shs(60, 4),
  _shs(70, 4),
  _shs(80, 4),
  _shs(90, 4),
  _shs(100, 4),
  _shs(100, 5),
  _shs(120, 5),
  _shs(120, 6),
  _shs(140, 6),
  _shs(150, 6),
  _shs(160, 8),
  _shs(180, 8),
  _shs(200, 8),
  _shs(200, 10),
];

/// Catálogo de angulares.
final List<SteelProfile> angleTable = [
  _l(40, 4),
  _l(50, 5),
  _l(60, 6),
  _l(70, 7),
  _l(80, 8),
  _l(90, 9),
  _l(100, 10),
];

List<SteelProfile> tableFor(ProfileFamily f) {
  switch (f) {
    case ProfileFamily.ipe:
      return ipeTable;
    case ProfileFamily.heb:
      return hebTable;
    case ProfileFamily.shs:
      return shsTable;
    case ProfileFamily.angle:
      return angleTable;
  }
}

/// Acero estructural.
class SteelGrade {
  final String name;
  final double fy; // N/mm²
  final double fu; // N/mm²
  final double betaW; // factor de correlación soldadura (EN 1993-1-8 tabla 4.1)
  const SteelGrade(this.name, this.fy, this.fu, this.betaW);
}

const s235 = SteelGrade('S235JR', 235, 360, 0.80);
const s275 = SteelGrade('S275JR', 275, 430, 0.85);
const s355 = SteelGrade('S355J2', 355, 490, 0.90);

/// Módulo de elasticidad del acero (N/mm²).
const double steelE = 210000;
const double gammaM0 = 1.05; // CTE DB-SE-A
const double gammaM1 = 1.05;
const double gammaM2 = 1.25;
