import 'dart:math' as math;

/// Familia de perfil comercial.
enum ProfileFamily { ipe, heb, shs, angle, upn, rhs, round, chs, flat }

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
      case ProfileFamily.upn:
        return (2 * h + 4 * b - 2 * tw) / 1000;
      case ProfileFamily.rhs:
        return (2 * h + 2 * b) / 1000;
      case ProfileFamily.round:
      case ProfileFamily.chs:
        return math.pi * h / 1000;
      case ProfileFamily.flat:
        return 2 * (h + b) / 1000;
    }
  }

  /// Espesor mínimo de las chapas que forman el perfil (para soldadura).
  double get tMin => math.min(tw, tf);

  bool get isHollow => family == ProfileFamily.shs || family == ProfileFamily.rhs || family == ProfileFamily.chs;

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

/// Tubo rectangular (RHS), canto h vertical — propiedades geométricas.
SteelProfile _rhs(double h, double b, double t) {
  final hi = h - 2 * t, bi = b - 2 * t;
  final areaMm2 = h * b - hi * bi;
  final iy = (b * math.pow(h, 3) - bi * math.pow(hi, 3)) / 12;
  final iz = (h * math.pow(b, 3) - hi * math.pow(bi, 3)) / 12;
  final wpl = (b * h * h - bi * hi * hi) / 4;
  String n(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 1);
  return SteelProfile(
    name: 'RHS ${n(h)}x${n(b)}x${n(t)}',
    family: ProfileFamily.rhs,
    h: h,
    b: b,
    tw: t,
    tf: t,
    area: areaMm2 / 100,
    iy: iy / 1e4,
    wply: wpl / 1e3,
    iz: iz / 1e4,
    kgm: areaMm2 * 7850 / 1e6,
  );
}

SteelProfile _upn(String n, double h, double b, double tw, double tf, double a, double iy, double wpl, double iz,
        double kg) =>
    SteelProfile(
        name: n, family: ProfileFamily.upn, h: h, b: b, tw: tw, tf: tf, area: a, iy: iy, wply: wpl, iz: iz, kgm: kg);

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

/// Catálogo UPN (prontuario).
final List<SteelProfile> upnTable = [
  _upn('UPN 80', 80, 45, 6, 8, 11.0, 106, 31.8, 19.4, 8.64),
  _upn('UPN 100', 100, 50, 6, 8.5, 13.5, 206, 49.0, 29.3, 10.6),
  _upn('UPN 120', 120, 55, 7, 9, 17.0, 364, 72.6, 43.2, 13.4),
  _upn('UPN 140', 140, 60, 7, 10, 20.4, 605, 103, 62.7, 16.0),
  _upn('UPN 160', 160, 65, 7.5, 10.5, 24.0, 925, 138, 85.3, 18.8),
  _upn('UPN 180', 180, 70, 8, 11, 28.0, 1350, 179, 114, 22.0),
  _upn('UPN 200', 200, 75, 8.5, 11.5, 32.2, 1910, 228, 148, 25.3),
  _upn('UPN 220', 220, 80, 9, 12.5, 37.4, 2690, 292, 197, 29.4),
  _upn('UPN 240', 240, 85, 9.5, 13, 42.3, 3600, 358, 248, 33.2),
  _upn('UPN 260', 260, 90, 10, 14, 48.3, 4820, 442, 317, 37.9),
  _upn('UPN 300', 300, 100, 10, 16, 58.8, 8030, 632, 495, 46.2),
];

/// Catálogo de tubo rectangular.
final List<SteelProfile> rhsTable = [
  _rhs(40, 20, 2),
  _rhs(50, 30, 2),
  _rhs(60, 40, 2),
  _rhs(60, 40, 3),
  _rhs(80, 40, 3),
  _rhs(80, 60, 3),
  _rhs(100, 50, 3),
  _rhs(100, 50, 4),
  _rhs(120, 60, 4),
  _rhs(120, 80, 5),
  _rhs(140, 80, 5),
  _rhs(150, 100, 5),
  _rhs(160, 80, 6),
  _rhs(200, 100, 6),
  _rhs(250, 150, 8),
  _rhs(300, 200, 8),
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
    case ProfileFamily.upn:
      return upnTable;
    case ProfileFamily.rhs:
      return rhsTable;
    case ProfileFamily.round:
      return roundTable;
    case ProfileFamily.chs:
      return chsTable;
    case ProfileFamily.flat:
      return flatTable;
  }
}

/// Redondo macizo (tirantes).
SteelProfile _rd(double d) {
  final a = math.pi * d * d / 4;
  final i = math.pi * math.pow(d, 4) / 64;
  return SteelProfile(
    name: 'R${d.toStringAsFixed(0)}',
    family: ProfileFamily.round,
    h: d,
    b: d,
    tw: d / 2,
    tf: d / 2,
    area: a / 100,
    iy: i / 1e4,
    wply: math.pow(d, 3) / 6 / 1e3,
    iz: i / 1e4,
    kgm: a * 7850 / 1e6,
  );
}

/// Redondos para tirantes (barra roscada en extremos).
final List<SteelProfile> roundTable = [for (final d in [12.0, 14, 16, 20, 24, 27, 30]) _rd(d.toDouble())];

/// Tubo redondo (CHS, EN 10219): pasamanos, mástiles y báculos.
SteelProfile _chs(double d, double t) {
  final di = d - 2 * t;
  final a = math.pi / 4 * (d * d - di * di);
  final i = math.pi / 64 * (math.pow(d, 4) - math.pow(di, 4));
  return SteelProfile(
    name: 'CHS ${d.toStringAsFixed(1).replaceAll('.0', '')}x${t.toStringAsFixed(1).replaceAll('.0', '')}',
    family: ProfileFamily.chs,
    h: d,
    b: d,
    tw: t,
    tf: t,
    area: a / 100,
    iy: i / 1e4,
    wply: (math.pow(d, 3) - math.pow(di, 3)) / 6 / 1e3,
    iz: i / 1e4,
    kgm: a * 7850 / 1e6,
  );
}

final List<SteelProfile> chsTable = [
  for (final (d, t) in const [
    (33.7, 2.6), (42.4, 2.6), (48.3, 3.0), (60.3, 3.0), (76.1, 3.0), (88.9, 4.0), (101.6, 4.0),
    (114.3, 4.0), (114.3, 5.0), (139.7, 5.0), (168.3, 5.0), (168.3, 6.3), (193.7, 6.3), (219.1, 6.3),
  ])
    _chs(d, t),
];

/// Pletina (llanta laminada): h = ancho, b = espesor.
SteelProfile _flat(double w, double t) => SteelProfile(
      name: 'Pletina ${w.toStringAsFixed(0)}x${t.toStringAsFixed(0)}',
      family: ProfileFamily.flat,
      h: w,
      b: t,
      tw: t,
      tf: t,
      area: w * t / 100,
      iy: t * math.pow(w, 3) / 12 / 1e4,
      wply: t * w * w / 4 / 1e3,
      iz: w * math.pow(t, 3) / 12 / 1e4,
      kgm: w * t * 7850 / 1e6,
    );

final List<SteelProfile> flatTable = [
  for (final (w, t) in const [(30.0, 5.0), (40.0, 5.0), (40.0, 8.0), (50.0, 5.0), (50.0, 8.0), (50.0, 10.0),
    (60.0, 8.0), (60.0, 10.0), (80.0, 10.0), (100.0, 10.0)])
    _flat(w, t),
];

/// Todos los perfiles del catálogo.
List<SteelProfile> get allProfiles => [for (final f in ProfileFamily.values) ...tableFor(f)];

/// Busca un perfil por su designación ("HEB 220", "SHS 100x4", "IPE300").
SteelProfile? profileByName(String n) {
  String k(String s) => s.toUpperCase().replaceAll(RegExp(r'[\s.]'), '').replaceAll(',', '.');
  final key = k(n);
  for (final p in allProfiles) {
    if (k(p.name) == key) return p;
  }
  return null;
}

/// Tipo de material estructural.
enum MaterialKind { carbon, weathering, stainless, aluminium }

/// Material estructural (aceros, inoxidables y aluminio).
class SteelGrade {
  final String name;
  final double fy; // N/mm² (para aluminio: f0,2)
  final double fu; // N/mm²
  final double betaW; // factor de correlación soldadura (EN 1993-1-8 tabla 4.1)
  final double e; // módulo de elasticidad N/mm²
  final double density; // kg/m³
  final MaterialKind kind;
  final String description;
  final String weld; // proceso y material de aportación
  final String norm;
  const SteelGrade(this.name, this.fy, this.fu, this.betaW,
      {this.e = 210000,
      this.density = 7850,
      this.kind = MaterialKind.carbon,
      this.description = '',
      this.weld = '135 (MAG) hilo G 42 4 M21 3Si1 (ER70S-6) / 111 electrodo E 42 4 B (E7018)',
      this.norm = 'EN 10025-2'});

  bool get isSteel => kind != MaterialKind.aluminium;

  /// Tornillería adecuada (evita par galvánico).
  String get bolts => switch (kind) {
        MaterialKind.stainless => 'Tornillería inoxidable A4-70 (EN ISO 3506)',
        MaterialKind.aluminium => 'Tornillería inoxidable A2-70/A4-70 con arandelas aislantes',
        _ => 'Tornillería 8.8 galvanizada (EN 15048 / EN 14399)',
      };
}

const s235 = SteelGrade('S235JR', 235, 360, 0.80,
    description: 'Acero estructural no aleado de uso general, buena soldabilidad. Cerrajería y piezas ligeras.');
const s275 = SteelGrade('S275JR', 275, 430, 0.85,
    description: 'Acero estructural más habitual en edificación (antiguo A42). Tenacidad a +20 °C.');
const s275j0 = SteelGrade('S275J0', 275, 430, 0.85,
    description: 'S275 con tenacidad garantizada a 0 °C: exteriores y zonas frías.');
const s275j2 = SteelGrade('S275J2', 275, 430, 0.85,
    description: 'S275 con tenacidad a −20 °C: uniones muy soldadas y climas fríos.');
const s355jr = SteelGrade('S355JR', 355, 490, 0.90,
    description: 'Acero de alta resistencia (antiguo A52). Luces grandes y piezas muy cargadas.',
    weld: '135 (MAG) hilo G 46 4 M21 4Si1 (ER70S-6) / 111 electrodo E 46 4 B');
const s355j0 = SteelGrade('S355J0', 355, 490, 0.90,
    description: 'S355 con tenacidad a 0 °C.', weld: '135 (MAG) hilo G 46 4 M21 4Si1 / 111 electrodo E 46 4 B');
const s355 = SteelGrade('S355J2', 355, 490, 0.90,
    description: 'S355 con tenacidad a −20 °C: estructuras exigentes y exteriores fríos.',
    weld: '135 (MAG) hilo G 46 4 M21 4Si1 / 111 electrodo E 46 4 B');
const s355w = SteelGrade('S355J2W (corten)', 355, 490, 0.90,
    kind: MaterialKind.weathering,
    norm: 'EN 10025-5',
    description: 'Acero autopatinable (corten): forma una pátina de óxido protectora; sin pintura. '
        'Evitar zonas con agua estancada o ambiente marino.',
    weld: '135 (MAG) hilo patinable G 46 4 M21 Z (ER80S-Ni1 / ER80S-W) para igualar color y corrosión');
const inox304 = SteelGrade('Inox 1.4301 (AISI 304)', 210, 520, 1.0,
    e: 200000,
    density: 7900,
    kind: MaterialKind.stainless,
    norm: 'EN 10088-4 / EN 1993-1-4',
    description: 'Acero inoxidable austenítico para interiores y exteriores no marinos: barandillas, pasamanos, '
        'elementos vistos.',
    weld: '141 (TIG) o 131 (MIG) varilla/hilo 19 9 L Si (ER308LSi), gas Ar; decapado y pasivado tras soldar');
const inox316 = SteelGrade('Inox 1.4401 (AISI 316)', 220, 530, 1.0,
    e: 200000,
    density: 8000,
    kind: MaterialKind.stainless,
    norm: 'EN 10088-4 / EN 1993-1-4',
    description: 'Inoxidable con molibdeno: ambiente marino, piscinas, industria química.',
    weld: '141 (TIG) o 131 (MIG) varilla/hilo 19 12 3 L Si (ER316LSi), gas Ar; decapado y pasivado');
const alu6060 = SteelGrade('Aluminio EN AW-6060 T6', 140, 170, 1.0,
    e: 70000,
    density: 2700,
    kind: MaterialKind.aluminium,
    norm: 'EN 755-2 / EN 1999-1-1',
    description: 'Aleación de extrusión para perfilería ligera (pérgolas, barandillas, carpintería). '
        'Tres veces más flexible que el acero.',
    weld: '131 (MIG) hilo AlMg5 (ER5356) o AlSi5 (ER4043), gas Ar; la soldadura reduce la resistencia en la zona afectada');
const alu6082 = SteelGrade('Aluminio EN AW-6082 T6', 250, 290, 1.0,
    e: 70000,
    density: 2700,
    kind: MaterialKind.aluminium,
    norm: 'EN 755-2 / EN 1999-1-1',
    description: 'Aleación estructural de aluminio más resistente. Pasarelas, plataformas ligeras, estructuras '
        'desmontables.',
    weld: '131 (MIG) hilo AlMg5 (ER5356), gas Ar; resistencia en zona afectada ≈ 50 % (EN 1999-1-1)');

const allGrades = [s235, s275, s275j0, s275j2, s355jr, s355j0, s355, s355w, inox304, inox316, alu6060, alu6082];

/// Material indicado en un texto normalizado (minúsculas, sin tildes). Null si no se indica.
SteelGrade? gradeFromText(String t) {
  bool h(String re) => RegExp(re).hasMatch(t);
  if (h(r'aluminio|(?<![a-z])alu(?![a-z])|6082|6061|6060|6063')) {
    return h(r'6082|6061|estructural') ? alu6082 : alu6060;
  }
  if (h(r'inox|1\.4401|1\.4404|aisi ?316|(?<![0-9])316l?(?![0-9])')) {
    return h(r'316|1\.440|marin|piscina|costa') ? inox316 : inox304;
  }
  if (h(r'corten|patinable|s355j2w|s355j0w')) return s355w;
  if (h(r's355\s*jr')) return s355jr;
  if (h(r's355\s*j0')) return s355j0;
  if (h(r's355')) return s355;
  if (h(r's275\s*j2')) return s275j2;
  if (h(r's275\s*j0')) return s275j0;
  if (h(r's275')) return s275;
  if (h(r's235')) return s235;
  return null;
}

/// Módulo de elasticidad del acero (N/mm²).
const double steelE = 210000;
const double gammaM0 = 1.05; // CTE DB-SE-A
const double gammaM1 = 1.05;
const double gammaM2 = 1.25;
