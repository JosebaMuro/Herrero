import 'dart:math' as math;

import 'profiles.dart';

class Vec3 {
  final double x, y, z;
  const Vec3(this.x, this.y, this.z);
  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double k) => Vec3(x * k, y * k, z * k);
  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;
  Vec3 cross(Vec3 o) =>
      Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(x * x + y * y + z * z);
  Vec3 get normalized {
    final l = length;
    return l == 0 ? this : Vec3(x / l, y / l, z / l);
  }

  @override
  String toString() =>
      '(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)}, ${z.toStringAsFixed(2)})';
}

enum StructureType {
  nave,
  marquesina,
  entreplanta,
  escalera,
  pasarela,
  barandilla,
  cercha,
  torre,
  estanteria,
  cancela,
  valla,
  portico,
  poste,
}

extension StructureTypeName on StructureType {
  String get label {
    switch (this) {
      case StructureType.nave:
        return 'Nave / pórticos a dos aguas';
      case StructureType.marquesina:
        return 'Marquesina / pérgola / porche';
      case StructureType.entreplanta:
        return 'Entreplanta / altillo / plataforma';
      case StructureType.escalera:
        return 'Escalera metálica';
      case StructureType.pasarela:
        return 'Pasarela / puente peatonal';
      case StructureType.barandilla:
        return 'Barandilla / antepecho';
      case StructureType.cercha:
        return 'Cubierta de cerchas (celosía)';
      case StructureType.torre:
        return 'Torre / soporte de depósito / bancada';
      case StructureType.estanteria:
        return 'Estantería / rack de carga';
      case StructureType.cancela:
        return 'Cancela / puerta / portón';
      case StructureType.valla:
        return 'Valla / cerramiento / reja';
      case StructureType.portico:
        return 'Pórtico de elevación (polipasto)';
      case StructureType.poste:
        return 'Poste / mástil / soporte de cartel';
    }
  }

  /// Descripción en inglés (para la foto IA).
  String get english {
    switch (this) {
      case StructureType.nave:
        return 'steel portal frame industrial warehouse building with gable roof';
      case StructureType.marquesina:
        return 'steel carport canopy pergola structure';
      case StructureType.entreplanta:
        return 'steel mezzanine platform inside an industrial warehouse';
      case StructureType.escalera:
        return 'straight steel staircase with steel stringers, treads and handrail';
      case StructureType.pasarela:
        return 'steel pedestrian footbridge walkway with grating deck and handrails';
      case StructureType.barandilla:
        return 'steel safety railing with vertical balusters and handrail on a concrete edge';
      case StructureType.cercha:
        return 'steel roof trusses with lattice web members and purlins on walls';
      case StructureType.torre:
        return 'braced steel tower frame supporting a water tank';
      case StructureType.estanteria:
        return 'industrial steel pallet racking shelving in a warehouse';
      case StructureType.cancela:
        return 'steel driveway gate with vertical bars between steel posts';
      case StructureType.valla:
        return 'steel fence with posts and vertical bars along a property boundary';
      case StructureType.portico:
        return 'steel gantry crane frame with hoist beam in a workshop';
      case StructureType.poste:
        return 'steel pole structure supporting a large sign board';
    }
  }

  /// Tiene cubierta (para render y foto).
  bool get hasRoof =>
      this == StructureType.nave || this == StructureType.marquesina || this == StructureType.cercha;

  /// Etiqueta de las tres cotas principales (largo, ancho, altura).
  (String, String, String) get dimLabels {
    switch (this) {
      case StructureType.escalera:
        return ('Desarrollo en planta', 'Ancho de paso', 'Altura a salvar');
      case StructureType.barandilla:
      case StructureType.valla:
        return ('Longitud', 'Ancho (no aplica)', 'Altura');
      case StructureType.cercha:
        return ('Longitud de cubierta', 'Luz de la cercha', 'Altura de apoyo');
      case StructureType.cancela:
        return ('Hueco libre', 'Espesor (no aplica)', 'Altura');
      case StructureType.portico:
        return ('Recorrido (no aplica)', 'Luz entre patas', 'Altura bajo viga');
      case StructureType.poste:
        return ('Ancho del cartel', 'Alto del cartel', 'Altura libre bajo cartel');
      case StructureType.estanteria:
        return ('Largo total', 'Fondo', 'Altura');
      case StructureType.torre:
        return ('Lado X', 'Lado Y', 'Altura');
      default:
        return ('Largo', 'Ancho / luz', 'Altura');
    }
  }
}

/// Tipo de superficie (para render e isométrica).
enum SurfaceKind { roof, floor, grating, panel, mesh, glass, wall, wood }

/// Superficie plana de cuatro vértices (suelos, peldaños, chapas, cartel…).
class Surface {
  final Vec3 a, b, c, d;
  final SurfaceKind kind;
  const Surface(this.a, this.b, this.c, this.d, this.kind);
}

enum MemberRole {
  column,
  rafter,
  purlin,
  beam,
  joist,
  tie,
  brace,
  post,
  handrail,
  gablePost,
  haunch,
  baluster,
  stringer,
  tread,
  chordTop,
  chordBottom,
  diagonal,
  strut,
  frame,
  rail,
}

extension MemberRoleName on MemberRole {
  String get label {
    switch (this) {
      case MemberRole.column:
        return 'Pilar';
      case MemberRole.rafter:
        return 'Dintel';
      case MemberRole.purlin:
        return 'Correa';
      case MemberRole.beam:
        return 'Viga';
      case MemberRole.joist:
        return 'Vigueta';
      case MemberRole.tie:
        return 'Viga de atado';
      case MemberRole.brace:
        return 'Arriostramiento';
      case MemberRole.post:
        return 'Montante de barandilla';
      case MemberRole.handrail:
        return 'Pasamanos / larguero';
      case MemberRole.gablePost:
        return 'Pilarillo de hastial';
      case MemberRole.haunch:
        return 'Cartela de acartelamiento';
      case MemberRole.baluster:
        return 'Barrote';
      case MemberRole.stringer:
        return 'Zanca';
      case MemberRole.tread:
        return 'Soporte de peldaño';
      case MemberRole.chordTop:
        return 'Cordón superior';
      case MemberRole.chordBottom:
        return 'Cordón inferior';
      case MemberRole.diagonal:
        return 'Diagonal de celosía';
      case MemberRole.strut:
        return 'Montante de celosía';
      case MemberRole.frame:
        return 'Bastidor';
      case MemberRole.rail:
        return 'Travesaño / larguero';
    }
  }

  String get prefix {
    switch (this) {
      case MemberRole.column:
        return 'P';
      case MemberRole.rafter:
        return 'D';
      case MemberRole.purlin:
        return 'C';
      case MemberRole.beam:
        return 'V';
      case MemberRole.joist:
        return 'VG';
      case MemberRole.tie:
        return 'A';
      case MemberRole.brace:
        return 'X';
      case MemberRole.post:
        return 'M';
      case MemberRole.handrail:
        return 'B';
      case MemberRole.gablePost:
        return 'PH';
      case MemberRole.haunch:
        return 'K';
      case MemberRole.baluster:
        return 'R';
      case MemberRole.stringer:
        return 'Z';
      case MemberRole.tread:
        return 'PE';
      case MemberRole.chordTop:
        return 'CS';
      case MemberRole.chordBottom:
        return 'CI';
      case MemberRole.diagonal:
        return 'DG';
      case MemberRole.strut:
        return 'MC';
      case MemberRole.frame:
        return 'H';
      case MemberRole.rail:
        return 'T';
    }
  }
}

/// Barra de la estructura en el modelo 3D (coordenadas en metros;
/// x = longitud, y = ancho/luz, z = altura).
class Member {
  final MemberRole role;
  final SteelProfile profile;
  final Vec3 a;
  final Vec3 b;

  /// Dirección del canto (alma) del perfil en el espacio.
  final Vec3 webDir;
  String mark = '';
  int group = 0;

  /// Corte en los extremos (texto) p.ej. "Escuadra" o "Inglete 5,7°".
  final String cut;

  Member({
    required this.role,
    required this.profile,
    required this.a,
    required this.b,
    Vec3? webDir,
    this.cut = 'Escuadra',
  }) : webDir = webDir ?? const Vec3(0, 0, 1);

  double get length => (b - a).length;
}

/// Chapa (placas de anclaje, placas de testa, cartelas…)
class PlatePiece {
  final String mark;
  final String description;
  final double w; // mm
  final double h; // mm
  final double t; // mm
  final int qty;
  final String notes;
  PlatePiece({
    required this.mark,
    required this.description,
    required this.w,
    required this.h,
    required this.t,
    required this.qty,
    this.notes = '',
  });
  double density = 7850; // kg/m³
  double get unitKg => w * h * t * density * 1e-9;
  double get totalKg => unitKg * qty;
}

/// Tornillería / pernos
class BoltItem {
  final String description;
  final String spec;
  final int qty;
  final String use;
  BoltItem(this.description, this.spec, this.qty, this.use);
}

/// Unión soldada tipo con su cordón.
class WeldSpec {
  final String joint; // nombre de la unión
  final String type; // en ángulo, a tope…
  final double throat; // garganta a (mm)
  final double lengthPerJoint; // mm de cordón por unión
  final int count; // nº de uniones iguales
  String process;
  final String position;
  final String notes;
  double density = 7850; // kg/m³ del material de aportación
  WeldSpec({
    required this.joint,
    required this.type,
    required this.throat,
    required this.lengthPerJoint,
    required this.count,
    this.process = '135 (MAG) hilo ER70S-6 / 111 (electrodo E7018)',
    this.position = 'PB (horizontal en ángulo) en taller',
    this.notes = '',
  });

  double get totalMeters => lengthPerJoint * count / 1000;

  /// Metal depositado (kg): sección del cordón en ángulo = a² (lado z = a√2)
  double get depositedKg => throat * throat * lengthPerJoint * count * density * 1e-9;

  /// Consumible estimado (kg) considerando rendimiento ~65 %.
  double get consumableKg => depositedKg / 0.65;
}

/// Comprobación de un elemento (estado límite).
class Check {
  final String element;
  final String description;
  final double utilization; // η = solicitación / resistencia
  final String detail;
  Check(this.element, this.description, this.utilization, this.detail);
  bool get ok => utilization <= 1.0;
}

/// Línea de despiece.
class Piece {
  final String mark;
  final String description;
  final SteelProfile profile;
  final double lengthMm;
  final int qty;
  final String cut;
  final double density; // kg/m³ (las tablas están en acero, 7850)
  Piece({
    required this.mark,
    required this.description,
    required this.profile,
    required this.lengthMm,
    required this.qty,
    required this.cut,
    this.density = 7850,
  });
  double get unitKg => profile.kgm * lengthMm / 1000 * density / 7850;
  double get totalKg => unitKg * qty;
  double get paintM2 => profile.paintAreaPerM * lengthMm / 1000 * qty;
}

/// Necesidad de barras comerciales por perfil.
class StockPlan {
  final SteelProfile profile;
  final double barLength; // mm
  final int bars;
  final double usedMm;
  final List<List<double>> layout;
  StockPlan(this.profile, this.barLength, this.bars, this.usedMm, this.layout);
  double get wastePct =>
      bars == 0 ? 0 : 100 * (1 - usedMm / (bars * barLength));
}

/// Parámetros interpretados del prompt.
class StructureSpec {
  StructureType type;
  double length; // m (dirección x)
  double width; // m (luz, dirección y)
  double height; // m (altura libre / alero)
  double slopePct; // pendiente cubierta %
  double? bay; // separación entre pórticos m
  String roofing; // chapa, sándwich, policarbonato, sin cubierta…
  double snow; // kN/m²
  double wind; // presión básica qb kN/m²
  double liveLoad; // sobrecarga de uso kN/m² (entreplantas)
  String use;
  SteelGrade grade;
  bool railing;
  String finish; // galvanizado, pintado, …
  double pointLoad; // kN: carga concentrada / por nivel (depósito, polipasto, estantería)
  int levels; // niveles (estanterías, torres)
  String variant; // subtipo: corredera, abatible, chapa, malla, sobre pilares…
  /// Perfil o familia impuesta por parte: {'pilares': 'HEB 220', 'correas': 'tubo'…}
  Map<String, String> parts;
  String cladding; // cerramiento lateral
  List<String> notes;

  StructureSpec({
    required this.type,
    required this.length,
    required this.width,
    required this.height,
    this.slopePct = 10,
    this.bay,
    this.roofing = 'chapa grecada',
    this.snow = 0.5,
    this.wind = 0.5,
    this.liveLoad = 0,
    this.use = '',
    this.grade = s275,
    this.railing = false,
    this.finish = 'pintado (imprimación + esmalte)',
    this.pointLoad = 0,
    this.levels = 0,
    this.variant = '',
    Map<String, String>? parts,
    this.cladding = '',
    List<String>? notes,
  })  : parts = parts ?? {},
        notes = notes ?? [];
}

/// Resultado completo del diseño.
class Design {
  final StructureSpec spec;
  final String prompt;
  final List<Member> members;
  final List<PlatePiece> plates;
  final List<BoltItem> bolts;
  final List<WeldSpec> welds;
  final List<Check> checks;
  final List<String> hypotheses;
  final List<String> assembly;
  final List<String> warnings;

  /// Coordenadas de las zapatas (para el plano y render).
  final List<Vec3> footings;
  final double footingSize; // m

  /// Cotas principales de la geometría
  final List<double> frameX; // posiciones de pórticos/líneas de pilares
  final List<double> gridY; // líneas de pilares en dirección y
  final double ridgeHeight;

  /// Superficies (suelos, peldaños, cartel, chapas de cerramiento…).
  final List<Surface> surfaces;

  late final List<Piece> pieces;
  late final List<StockPlan> stock;

  Design({
    required this.spec,
    required this.prompt,
    required this.members,
    required this.plates,
    required this.bolts,
    required this.welds,
    required this.checks,
    required this.hypotheses,
    required this.assembly,
    required this.warnings,
    required this.footings,
    required this.footingSize,
    required this.frameX,
    required this.gridY,
    required this.ridgeHeight,
    this.surfaces = const [],
  });

  double get steelKg =>
      pieces.fold<double>(0, (s, p) => s + p.totalKg) +
      plates.fold<double>(0, (s, p) => s + p.totalKg);
  double get profilesKg => pieces.fold<double>(0, (s, p) => s + p.totalKg);
  double get platesKg => plates.fold<double>(0, (s, p) => s + p.totalKg);
  double get paintM2 => pieces.fold<double>(0, (s, p) => s + p.paintM2);
  double get weldMeters => welds.fold<double>(0, (s, w) => s + w.totalMeters);
  double get consumableKg =>
      welds.fold<double>(0, (s, w) => s + w.consumableKg);
  double get maxUtilization =>
      checks.fold<double>(0, (s, c) => math.max(s, c.utilization));
  double get coveredArea => spec.length * spec.width;

  /// Ratio de acero adaptado a la tipología: kg/m², kg/m o kg.
  (double, String) get steelRatio {
    switch (spec.type) {
      case StructureType.barandilla:
      case StructureType.valla:
        return (steelKg / math.max(spec.length, 0.1), 'kg/m');
      case StructureType.cancela:
        return (steelKg / math.max(spec.length * spec.height, 0.1), 'kg/m² de hoja');
      case StructureType.portico:
        return (steelKg / math.max(spec.width, 0.1), 'kg/m de luz');
      default:
        final a = coveredArea;
        return a < 0.1 ? (steelKg, 'kg') : (steelKg / a, 'kg/m²');
    }
  }
}
