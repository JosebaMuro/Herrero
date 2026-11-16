import 'dart:math' as math;

import 'bom.dart';
import 'model.dart';
import 'parser.dart';
import 'profiles.dart';

// ---------------------------------------------------------------------------
// Utilidades de cálculo (EN 1993-1-1 / CTE DB-SE-A)
// ---------------------------------------------------------------------------

const double _limit = 0.90; // aprovechamiento objetivo en predimensionado

double _lambdaBar(double lkMm, double iCm, double fy) =>
    (lkMm / (iCm * 10)) / (math.pi * math.sqrt(steelE / fy));

double _chi(double lb, double alpha) {
  if (lb <= 0.2) return 1.0;
  final phi = 0.5 * (1 + alpha * (lb - 0.2) + lb * lb);
  return math.min(1.0, 1 / (phi + math.sqrt(phi * phi - lb * lb)));
}

/// Curvas de pandeo (α) según tipo de sección.
double _alphaStrong(SteelProfile p) {
  switch (p.family) {
    case ProfileFamily.ipe:
      return 0.21; // curva a
    case ProfileFamily.heb:
      return 0.34; // curva b
    case ProfileFamily.shs:
      return 0.49; // conformado en frío: curva c
    case ProfileFamily.angle:
      return 0.34;
  }
}

double _alphaWeak(SteelProfile p) {
  switch (p.family) {
    case ProfileFamily.ipe:
      return 0.34; // curva b
    case ProfileFamily.heb:
      return 0.49; // curva c
    case ProfileFamily.shs:
      return 0.49;
    case ProfileFamily.angle:
      return 0.34;
  }
}

/// Resistencia a flexión (kN·m)
double _mRd(SteelProfile p, double fy) => p.wply * fy / gammaM0 / 1000;

/// Resistencia plástica a axil (kN)
double _nPl(SteelProfile p, double fy) => p.area * fy / gammaM0 / 10;

/// Flecha de viga biapoyada con carga uniforme (mm). q en kN/m, L en m.
double _deflSS(double q, double l, SteelProfile p) =>
    5 * q * math.pow(l * 1000, 4) / (384 * steelE * p.iy * 1e4);

/// Elige el primer perfil (más ligero) cuyas comprobaciones cumplen.
SteelProfile _choose(
  List<SteelProfile> candidates,
  List<Check> Function(SteelProfile) checksFor,
  List<Check> out, {
  double limit = _limit,
}) {
  final sorted = [...candidates]..sort((a, b) => a.kgm.compareTo(b.kgm));
  for (final p in sorted) {
    final cs = checksFor(p);
    if (cs.every((c) => c.utilization <= limit)) {
      out.addAll(cs);
      return p;
    }
  }
  final last = sorted.reduce((a, b) => a.wply > b.wply ? a : b);
  out.addAll(checksFor(last));
  return last;
}

String _f(double v, [int d = 1]) => v.toStringAsFixed(d).replaceAll('.', ',');

/// Garganta de soldadura en ángulo para unión de resistencia completa
/// (doble cordón), con mínimos constructivos.
double weldThroat(double tThin, double tThick, SteelGrade g) {
  final k = g.fy <= 235 ? 0.46 : (g.fy <= 275 ? 0.48 : 0.55);
  var a = (k * tThin).ceilToDouble();
  final aMin = tThick <= 10 ? 3.0 : (tThick <= 20 ? 4.0 : 5.0);
  a = math.max(a, aMin);
  return math.min(a, math.max(3.0, (0.7 * tThin).floorToDouble()));
}

/// Resistencia del cordón por unidad de longitud (kN/mm) – método simplificado
/// EN 1993-1-8 4.5.3.3.
double _fwRd(double a, SteelGrade g) =>
    g.fu / (math.sqrt(3) * g.betaW * gammaM2) * a / 1000;

double _stdPlate(double t) {
  const std = <double>[8, 10, 12, 15, 20, 25, 30, 35, 40, 50];
  for (final s in std) {
    if (s >= t) return s;
  }
  return 50;
}

double _roundUp(double v, double step) => (v / step).ceil() * step;

/// Peso propio del material de cubierta / suelo (kN/m²)
double _roofingWeight(String r) {
  if (r.contains('sandwich') || r.contains('sándwich')) return 0.15;
  if (r.contains('policarbonato')) return 0.05;
  if (r.contains('teja')) return 0.65;
  if (r.contains('fotovolta')) return 0.25;
  if (r.contains('sin cubierta')) return 0.0;
  if (r.contains('tramex')) return 0.40;
  if (r.contains('colaborante')) return 2.60;
  if (r.contains('tablero') || r.contains('lagrimada')) return 0.45;
  return 0.12; // chapa grecada
}

// ---------------------------------------------------------------------------
// Punto de entrada
// ---------------------------------------------------------------------------

Design designFromPrompt(String prompt) {
  final spec = parsePrompt(prompt);
  return designFromSpec(spec, prompt);
}

Design designFromSpec(StructureSpec spec, String prompt) {
  final Design d;
  switch (spec.type) {
    case StructureType.nave:
      d = _designNave(spec, prompt);
      break;
    case StructureType.marquesina:
      d = _designMarquesina(spec, prompt);
      break;
    case StructureType.entreplanta:
      d = _designEntreplanta(spec, prompt);
      break;
  }
  buildBom(d);
  return d;
}

List<String> _commonHypotheses(StructureSpec s) => [
      'Normativa: CTE DB-SE (bases de cálculo), DB-SE-AE (acciones), DB-SE-A (acero) y Eurocódigo 3 (EN 1993-1-1 y 1-8). Ejecución según EN 1090-2, clase EXC2.',
      'Acero ${s.grade.name}: fy = ${_f(s.grade.fy, 0)} N/mm², fu = ${_f(s.grade.fu, 0)} N/mm². γM0 = γM1 = 1,05; γM2 = 1,25.',
      'Coeficientes de mayoración ELU: γG = 1,35; γQ = 1,50; ψ0 nieve = 0,5; ψ0 viento = 0,6.',
      'Predimensionado con métodos simplificados y aprovechamiento objetivo ≤ ${_f(_limit * 100, 0)} %. No sustituye al cálculo matricial del proyecto.',
      'Tornillería de alta resistencia clase 8.8 (EN 15048 / EN 14399 en uniones pretensadas). Pernos de anclaje B500S o 8.8 con tuerca y contratuerca.',
      'Soldadura según EN ISO 15614 / EN ISO 9606-1; calidad nivel C (EN ISO 5817). Inspección visual 100 % + END según EXC2.',
      'Acabado: ${s.finish}.',
    ];

// ---------------------------------------------------------------------------
// NAVE DE PÓRTICOS A DOS AGUAS
// ---------------------------------------------------------------------------

Design _designNave(StructureSpec s, String prompt) {
  final g = s.grade;
  final fy = g.fy;
  final L = s.width; // luz
  final H = s.height;
  final lx = s.length;
  final slope = s.slopePct / 100;
  final rise = L / 2 * slope;
  final rafterLen = math.sqrt(math.pow(L / 2, 2) + rise * rise);
  final angleDeg = math.atan(slope) * 180 / math.pi;

  final nb = s.bay != null
      ? math.max(1, (lx / s.bay!).round())
      : math.max(1, (lx / 6.0).ceil());
  final bay = lx / nb;
  final frameX = List.generate(nb + 1, (i) => i * bay);

  // Cargas superficiales (kN/m²)
  final gRoof = _roofingWeight(s.roofing) + 0.05; // + fijaciones/instalaciones
  final qSnow = s.snow; // μ = 1 (pendiente < 30°)
  final qRoof = math.max(qSnow, s.liveLoad); // G1 no concomitante
  final qb = s.wind;
  const ce = 2.0; // coef. exposición (entorno rural/industrial, h ≤ 8 m) aprox.

  final checks = <Check>[];
  final warnings = <String>[...s.notes];

  // --- Correas ---------------------------------------------------------------
  final np = math.max(1, ((rafterLen - 0.2) / 1.6).ceil());
  final e = (rafterLen - 0.2) / np;
  late double qdPurlin;
  final purlin = _choose(ipeTable.where((p) => p.h <= 220).toList(), (p) {
    final self = p.kgm * 9.81 / 1000;
    qdPurlin = (1.35 * (gRoof * e + self) + 1.5 * qRoof * e);
    final med = qdPurlin * bay * bay / 10; // continua en 2+ vanos
    final qk = (gRoof * e + self + qRoof * e);
    final defl = qk * math.pow(bay * 1000, 4) / (185 * steelE * p.iy * 1e4);
    return [
      Check('Correa ${p.name}', 'Flexión ELU  M = q·s²/10',
          med / _mRd(p, fy),
          'qd = ${_f(qdPurlin, 2)} kN/m, s = ${_f(bay, 2)} m, MEd = ${_f(med)} kN·m, Mc,Rd = ${_f(_mRd(p, fy))} kN·m'),
      Check('Correa ${p.name}', 'Flecha ELS ≤ s/250', defl / (bay * 1000 / 250),
          'δ = ${_f(defl)} mm, límite ${_f(bay * 1000 / 250)} mm'),
    ];
  }, checks);

  // --- Dintel ----------------------------------------------------------------
  final purlinLine = purlin.kgm * 9.81 / 1000 * (2 * (np + 1)) / L;
  double qdRafter = 0, qkRafter = 0;
  final rafter = _choose(ipeTable, (p) {
    final self = p.kgm * 9.81 / 1000;
    qdRafter = 1.35 * (gRoof * bay + purlinLine * bay + self) + 1.5 * qRoof * bay;
    qkRafter = gRoof * bay + purlinLine * bay + self + qRoof * bay;
    final med = qdRafter * L * L / 12; // momento en nudo de pórtico biarticulado
    final defl = 0.4 * _deflSS(qkRafter, L, p); // reducción por continuidad del pórtico
    return [
      Check('Dintel ${p.name}', 'Flexión ELU en nudo M ≈ q·L²/12',
          med / _mRd(p, fy),
          'qd = ${_f(qdRafter, 2)} kN/m, L = ${_f(L, 2)} m, MEd = ${_f(med)} kN·m, Mc,Rd = ${_f(_mRd(p, fy))} kN·m'),
      Check('Dintel ${p.name}', 'Flecha ELS ≤ L/250', defl / (L * 1000 / 250),
          'δ ≈ ${_f(defl)} mm, límite ${_f(L * 1000 / 250)} mm'),
    ];
  }, checks);
  final mKnee = qdRafter * L * L / 12;

  // --- Pilares ---------------------------------------------------------------
  final wFacade = qb * ce * 1.3 * bay; // kN/m (barlovento + sotavento)
  final mWind = wFacade * H * H / 4; // momento en cabeza por viento
  final column = _choose([...ipeTable, ...hebTable], (p) {
    final self = p.kgm * 9.81 / 1000 * H;
    final ned = qdRafter * L / 2 + 1.35 * self;
    final m1 = mKnee + 0.9 * mWind; // nieve principal + viento ψ0
    final m2 = (1.35 * (gRoof * bay + purlinLine * bay) +
                0.75 * qRoof * bay) *
            L *
            L /
            12 +
        1.5 * mWind; // viento principal
    final med = math.max(m1, m2);
    final lbY = _lambdaBar(2.0 * H * 1000, p.ry, fy);
    final lbZ = _lambdaBar(1.0 * H * 1000, p.rz, fy);
    final nbY = _chi(lbY, _alphaStrong(p)) * p.area * fy / gammaM1 / 10;
    final nbZ = _chi(lbZ, _alphaWeak(p)) * p.area * fy / gammaM1 / 10;
    final mrd = _mRd(p, fy);
    return [
      Check('Pilar ${p.name}', 'Flexocompresión en plano  N/Nb,y + M/Mc ≤ 1',
          ned / nbY + med / mrd,
          'NEd = ${_f(ned)} kN, MEd = ${_f(med)} kN·m, Lk = 2·H = ${_f(2 * H)} m, λ̄y = ${_f(lbY, 2)}, Nb,y,Rd = ${_f(nbY)} kN'),
      Check('Pilar ${p.name}', 'Pandeo fuera del plano  N/Nb,z + 0,6·M/Mc ≤ 1',
          ned / nbZ + 0.6 * med / mrd,
          'Lk = H = ${_f(H)} m (arriostrado en cabeza), λ̄z = ${_f(lbZ, 2)}, Nb,z,Rd = ${_f(nbZ)} kN'),
    ];
  }, checks);
  final nColumnD = qdRafter * L / 2 + 1.35 * column.kgm * 9.81 / 1000 * H;
  final nColumnK = qkRafter * L / 2 + column.kgm * 9.81 / 1000 * H;

  // --- Vigas de atado y arriostramientos ------------------------------------
  final fGable = qb * ce * 0.8 * L * (H + rise / 2) / 2; // a cada hastial
  final tieN = 1.5 * fGable / 2;
  final tie = _choose(shsTable.where((p) => p.b >= 60).toList(), (p) {
    final lb = _lambdaBar(bay * 1000, p.rz, fy);
    final nb = _chi(lb, _alphaStrong(p)) * p.area * fy / gammaM1 / 10;
    final slender = (bay * 1000) / (p.rz * 10);
    return [
      Check('Viga de atado ${p.name}', 'Compresión  N/Nb,Rd',
          tieN / nb, 'NEd = ${_f(tieN)} kN, Lk = ${_f(bay, 2)} m, Nb,Rd = ${_f(nb)} kN'),
      Check('Viga de atado ${p.name}', 'Esbeltez λ ≤ 200', slender / 200,
          'λ = ${_f(slender, 0)}'),
    ];
  }, checks);

  final diagRoof =
      math.sqrt(bay * bay + rafterLen * rafterLen); // diagonal en faldón
  final braceN = 1.5 * fGable / 2 * diagRoof / bay;
  final brace = _choose(angleTable.where((p) => p.b >= 50).toList(), (p) {
    final nt = _nPl(p, fy) * 0.85; // sección neta aprox.
    return [
      Check('Cruz San Andrés ${p.name}', 'Tracción (solo diagonal traccionada)',
          braceN / nt, 'NEd = ${_f(braceN)} kN, Nt,Rd ≈ ${_f(nt)} kN'),
    ];
  }, checks);

  // --- Pilarillos de hastial ------------------------------------------------
  final gableYs = <double>[];
  if (L > 7) {
    final n = (L / 5).ceil();
    for (var i = 1; i < n; i++) {
      gableYs.add(L * i / n);
    }
  }
  final gableSpacing = gableYs.isEmpty ? L : L / (gableYs.length + 1);
  final hGable = H + rise;
  SteelProfile? gablePost;
  if (gableYs.isNotEmpty) {
    gablePost = _choose(ipeTable, (p) {
      final w = 1.5 * qb * ce * 0.8 * gableSpacing;
      final med = w * hGable * hGable / 8;
      final defl = _deflSS(qb * ce * 0.8 * gableSpacing, hGable, p);
      return [
        Check('Pilarillo hastial ${p.name}', 'Flexión por viento M = w·h²/8',
            med / _mRd(p, fy),
            'w = ${_f(w, 2)} kN/m, h = ${_f(hGable)} m, MEd = ${_f(med)} kN·m'),
        Check('Pilarillo hastial ${p.name}', 'Flecha ELS ≤ h/250',
            defl / (hGable * 1000 / 250), 'δ = ${_f(defl)} mm'),
      ];
    }, checks);
  }

  // --- Geometría 3D --------------------------------------------------------
  final members = <Member>[];
  final ridgeZ = H + rise;
  final rDirL = Vec3(0, L / 2, rise).normalized;
  final rDirR = Vec3(0, -L / 2, rise).normalized;
  final webL = Vec3(0, -rise, L / 2).normalized;
  final webR = Vec3(0, rise, L / 2).normalized;
  final footings = <Vec3>[];
  final cutRafter = 'Inglete ${_f(angleDeg)}° en cumbrera / placa testa';

  for (final x in frameX) {
    for (final y in [0.0, L]) {
      members.add(Member(
          role: MemberRole.column,
          profile: column,
          a: Vec3(x, y, 0),
          b: Vec3(x, y, H),
          webDir: const Vec3(0, 1, 0),
          cut: 'Escuadra'));
      footings.add(Vec3(x, y, 0));
    }
    members.add(Member(
        role: MemberRole.rafter,
        profile: rafter,
        a: Vec3(x, 0, H),
        b: Vec3(x, L / 2, ridgeZ),
        webDir: webL,
        cut: cutRafter));
    members.add(Member(
        role: MemberRole.rafter,
        profile: rafter,
        a: Vec3(x, L, H),
        b: Vec3(x, L / 2, ridgeZ),
        webDir: webR,
        cut: cutRafter));
    // Cartelas en nudos de alero (L/10)
    final lh = _roundUp(L / 10, 0.05);
    final dropL = webL * (-rafter.h / 1000);
    final dropR = webR * (-rafter.h / 1000);
    members.add(Member(
        role: MemberRole.haunch,
        profile: rafter,
        a: Vec3(x, column.h / 2000, H) + dropL,
        b: Vec3(x, column.h / 2000, H) + rDirL * lh + dropL * 0.2,
        webDir: webL,
        cut: 'Corte diagonal (1 barra → 2 cartelas)'));
    members.add(Member(
        role: MemberRole.haunch,
        profile: rafter,
        a: Vec3(x, L - column.h / 2000, H) + dropR,
        b: Vec3(x, L - column.h / 2000, H) + rDirR * lh + dropR * 0.2,
        webDir: webR,
        cut: 'Corte diagonal (1 barra → 2 cartelas)'));
  }

  // Correas
  final off = (rafter.h + purlin.h) / 2000;
  for (var i = 0; i < nb; i++) {
    final x0 = frameX[i], x1 = frameX[i + 1];
    for (var k = 0; k <= np; k++) {
      final t = k * e;
      final pL = Vec3(0, 0, H) + rDirL * t + webL * off;
      final pR = Vec3(0, L, H) + rDirR * t + webR * off;
      members.add(Member(
          role: MemberRole.purlin,
          profile: purlin,
          a: Vec3(x0, pL.y, pL.z),
          b: Vec3(x1, pL.y, pL.z),
          webDir: webL));
      members.add(Member(
          role: MemberRole.purlin,
          profile: purlin,
          a: Vec3(x0, pR.y, pR.z),
          b: Vec3(x1, pR.y, pR.z),
          webDir: webR));
    }
    // Vigas de atado en cabeza de pilares
    for (final y in [0.0, L]) {
      members.add(Member(
          role: MemberRole.tie,
          profile: tie,
          a: Vec3(x0, y, H - 0.15),
          b: Vec3(x1, y, H - 0.15)));
    }
    // Viga de atado en cumbrera
    members.add(Member(
        role: MemberRole.tie,
        profile: tie,
        a: Vec3(x0, L / 2, ridgeZ - rafter.h / 1000 - 0.05),
        b: Vec3(x1, L / 2, ridgeZ - rafter.h / 1000 - 0.05)));
  }

  // Cruces de San Andrés en vanos extremos (cubierta y fachadas laterales)
  final braceBays = nb == 1 ? [0] : [0, nb - 1];
  for (final i in braceBays) {
    final x0 = frameX[i], x1 = frameX[i + 1];
    final eaveZ = H, z0 = 0.3;
    // cubierta: un aspa por faldón
    for (final side in [0, 1]) {
      final yE = side == 0 ? 0.0 : L;
      members.add(Member(
          role: MemberRole.brace,
          profile: brace,
          a: Vec3(x0, yE, eaveZ),
          b: Vec3(x1, L / 2, ridgeZ),
          webDir: side == 0 ? webL : webR));
      members.add(Member(
          role: MemberRole.brace,
          profile: brace,
          a: Vec3(x0, L / 2, ridgeZ),
          b: Vec3(x1, yE, eaveZ),
          webDir: side == 0 ? webL : webR));
      // fachada lateral
      members.add(Member(
          role: MemberRole.brace,
          profile: brace,
          a: Vec3(x0, yE, z0),
          b: Vec3(x1, yE, eaveZ - 0.2),
          webDir: const Vec3(0, 1, 0)));
      members.add(Member(
          role: MemberRole.brace,
          profile: brace,
          a: Vec3(x0, yE, eaveZ - 0.2),
          b: Vec3(x1, yE, z0),
          webDir: const Vec3(0, 1, 0)));
    }
  }

  // Pilarillos de hastial
  if (gablePost != null) {
    for (final x in [0.0, lx]) {
      for (final y in gableYs) {
        final zTop = H + rise * (1 - (y - L / 2).abs() / (L / 2)) -
            rafter.h / 1000;
        members.add(Member(
            role: MemberRole.gablePost,
            profile: gablePost,
            a: Vec3(x, y, 0),
            b: Vec3(x, y, zTop),
            webDir: const Vec3(1, 0, 0)));
        footings.add(Vec3(x, y, 0));
      }
    }
  }

  // --- Placas, tornillos y soldaduras --------------------------------------
  final nFrames = frameX.length;
  final nCols = nFrames * 2;
  final nGable = gablePost == null ? 0 : gableYs.length * 2;

  // Placa de anclaje: comprobación de espesor por presión en hormigón
  const fjd = 13.0; // N/mm² (HA-25, βj·kj·fcd aprox.)
  final pw = _roundUp(column.b + 150, 50);
  final ph = _roundUp(column.h + 200, 50);
  final sigma = nColumnD * 1000 / (pw * ph);
  final c = 75.0;
  final tReq = c * math.sqrt(3 * math.max(sigma, 2.0) * gammaM0 / fy);
  final tp = _stdPlate(math.max(tReq, math.max(15.0, column.tf * 1.5)));
  checks.add(Check('Placa de anclaje ${_f(pw, 0)}x${_f(ph, 0)}x${_f(tp, 0)}',
      'Presión sobre hormigón σ ≤ fjd', sigma / fjd,
      'NEd = ${_f(nColumnD)} kN, σ = ${_f(sigma, 2)} N/mm², fjd = ${_f(fjd)} N/mm², t req. = ${_f(tReq)} mm'));
  final anchorD = column.h >= 300 || L > 20 ? 24 : (column.h >= 200 ? 20 : 16);

  final plates = <PlatePiece>[
    PlatePiece(
        mark: 'PA1',
        description: 'Placa de anclaje pilar ${column.name}',
        w: pw,
        h: ph,
        t: tp,
        qty: nCols,
        notes: '4 taladros Ø${anchorD + 6} para pernos M$anchorD; taladro central Ø40 para grout'),
    if (gablePost != null)
      PlatePiece(
          mark: 'PA2',
          description: 'Placa de anclaje pilarillo ${gablePost.name}',
          w: _roundUp(gablePost.b + 150, 50),
          h: _roundUp(gablePost.h + 150, 50),
          t: 15,
          qty: nGable,
          notes: '4 taladros Ø22 para pernos M16'),
  ];
  final hc = rafter.h * 2; // canto en nudo con cartela
  final tTesta = _stdPlate(math.max(15.0, rafter.tf * 1.8));
  plates.addAll([
    PlatePiece(
        mark: 'PT1',
        description: 'Placa de testa nudo alero (dintel+cartela)',
        w: _roundUp(rafter.b + 40, 10),
        h: _roundUp(hc + 80, 10),
        t: tTesta,
        qty: nFrames * 2,
        notes: '${rafter.h >= 300 ? 8 : 6} tornillos M${rafter.h >= 300 ? 20 : 16} 8.8'),
    PlatePiece(
        mark: 'PT2',
        description: 'Placa de testa cumbrera',
        w: _roundUp(rafter.b + 40, 10),
        h: _roundUp(rafter.h + 100, 10),
        t: _stdPlate(math.max(12.0, rafter.tf * 1.5)),
        qty: nFrames * 2,
        notes: '4–6 tornillos M16 8.8'),
    PlatePiece(
        mark: 'RG1',
        description: 'Rigidizador de pilar en nudo',
        w: _roundUp((column.b - column.tw) / 2 - 5, 5),
        h: _roundUp(column.h - 2 * column.tf, 5),
        t: _stdPlate(math.max(8.0, column.tf)),
        qty: nFrames * 2 * 4,
        notes: '2 parejas por nudo (a la altura de alas del dintel y cartela)'),
    PlatePiece(
        mark: 'EJ1',
        description: 'Ejión de correa (L 80x8, l=150 mm)',
        w: 150,
        h: 152,
        t: 8,
        qty: (np + 1) * 2 * nFrames,
        notes: '2 taladros Ø14 para M12'),
    PlatePiece(
        mark: 'GU1',
        description: 'Cartela de arriostramiento',
        w: 200,
        h: 200,
        t: 8,
        qty: braceBays.length * 8 * 2,
        notes: '2 taladros Ø18 para M16'),
  ]);

  final bolts = <BoltItem>[
    BoltItem('Pernos de anclaje', 'M$anchorD x ${anchorD * 30} mm B500S roscado + 2 tuercas + arandela',
        nCols * 4, 'Placas PA1'),
    if (gablePost != null)
      BoltItem('Pernos de anclaje', 'M16 x 500 mm B500S roscado + 2 tuercas', nGable * 4, 'Placas PA2'),
    BoltItem('Tornillos nudo alero', 'M${rafter.h >= 300 ? 20 : 16} x ${(tTesta + column.tf + 30).ceil()} 8.8 + tuerca + 2 arandelas',
        nFrames * 2 * (rafter.h >= 300 ? 8 : 6), 'Unión dintel-pilar'),
    BoltItem('Tornillos cumbrera', 'M16 x ${(2 * tTesta + 25).ceil()} 8.8 + tuerca + 2 arandelas',
        nFrames * 6, 'Unión dintel-dintel'),
    BoltItem('Tornillos correas', 'M12 x 35 8.8 + tuerca + arandela',
        (np + 1) * 2 * nFrames * 2, 'Correa-ejión'),
    BoltItem('Tornillos arriostramiento', 'M16 x 40 8.8 + tuerca + arandela',
        braceBays.length * 8 * 2, 'Cruces de San Andrés'),
    BoltItem('Tornillos vigas de atado', 'M16 x 40 8.8 + tuerca + arandela',
        nb * 3 * 2 * 2, 'Atado de cabeza y cumbrera'),
  ];

  final aCol = weldThroat(column.tMin, tp, g);
  final perCol = 2 * (2 * column.b - column.tw) + 2 * (column.h - 2 * column.tf);
  final aRaf = weldThroat(rafter.tMin, tTesta, g);
  final perRaf = 2 * (2 * rafter.b - rafter.tw) + 2 * (rafter.h - 2 * rafter.tf);
  final welds = <WeldSpec>[
    WeldSpec(
        joint: 'Pilar – placa de anclaje (PA1)',
        type: 'En ángulo, perimetral doble',
        throat: aCol,
        lengthPerJoint: perCol,
        count: nCols),
    if (gablePost != null)
      WeldSpec(
          joint: 'Pilarillo – placa de anclaje (PA2)',
          type: 'En ángulo, perimetral doble',
          throat: weldThroat(gablePost.tMin, 15, g),
          lengthPerJoint: 2 * (2 * gablePost.b - gablePost.tw) +
              2 * (gablePost.h - 2 * gablePost.tf),
          count: nGable),
    WeldSpec(
        joint: 'Dintel – placa de testa alero (PT1)',
        type: 'En ángulo, perimetral doble',
        throat: aRaf,
        lengthPerJoint: perRaf * 1.6,
        count: nFrames * 2),
    WeldSpec(
        joint: 'Cartela – dintel (alma y ala)',
        type: 'En ángulo, doble cordón',
        throat: weldThroat(rafter.tw, rafter.tf, g),
        lengthPerJoint: 2 * _roundUp(L / 10, 0.05) * 1000,
        count: nFrames * 2),
    WeldSpec(
        joint: 'Dintel – placa de testa cumbrera (PT2)',
        type: 'En ángulo, perimetral doble',
        throat: aRaf,
        lengthPerJoint: perRaf,
        count: nFrames * 2),
    WeldSpec(
        joint: 'Rigidizadores de pilar (RG1)',
        type: 'En ángulo, doble cordón a alma y alas',
        throat: weldThroat(math.min(column.tw, column.tf), column.tf, g),
        lengthPerJoint: 2 * ((column.h - 2 * column.tf) + (column.b - column.tw) / 2),
        count: nFrames * 2 * 4),
    WeldSpec(
        joint: 'Ejión – dintel (EJ1)',
        type: 'En ángulo, cordón en U',
        throat: 4,
        lengthPerJoint: 2 * 80 + 150,
        count: (np + 1) * 2 * nFrames,
        position: 'PB / PF en taller'),
    WeldSpec(
        joint: 'Cartela de arriostramiento – pilar/dintel (GU1)',
        type: 'En ángulo, doble cordón',
        throat: 5,
        lengthPerJoint: 2 * 200,
        count: braceBays.length * 8 * 2),
  ];
  final fw = _fwRd(aCol, g);
  checks.add(Check('Soldadura pilar-placa a=${_f(aCol, 0)}',
      'Cordones en ángulo (método simplificado EN 1993-1-8)',
      nColumnD / (fw * perCol),
      'Fw,Rd = ${_f(fw * 1000, 0)} N/mm, Lw = ${_f(perCol, 0)} mm, NEd = ${_f(nColumnD)} kN'));

  // Zapatas
  final fs = math.max(1.0,
      _roundUp(math.sqrt(nColumnK / 200) + 0.4, 0.1)); // σadm 0,2 N/mm² + margen por momento/viento

  final hyp = [
    ..._commonHypotheses(s),
    'Pórticos biarticulados en base, nudos rígidos en alero (cartela L/10) y cumbrera.',
    'Luz ${_f(L, 2)} m; longitud ${_f(lx, 2)} m; ${nb} vanos de ${_f(bay, 2)} m; altura alero ${_f(H, 2)} m; pendiente ${_f(s.slopePct)} % (${_f(angleDeg)}°); cumbrera a ${_f(ridgeZ, 2)} m.',
    'Cubierta: ${s.roofing} (${_f(_roofingWeight(s.roofing), 2)} kN/m²) + instalaciones 0,05 kN/m². Correas a ${_f(e, 2)} m.',
    'Nieve sk = ${_f(qSnow, 2)} kN/m² (μ = 1). Uso G1 = 0,40 kN/m² (no concomitante).',
    'Viento qb = ${_f(qb, 2)} kN/m², ce ≈ 2,0, cp,barlovento+sotavento ≈ 1,3 (simplificado). Succión sobre correas no evaluada: revisar en proyecto.',
    'Cruces de San Andrés trabajando solo a tracción, con tensor en el cruce para eliminar holguras. Pandeo pilares: Lk,y = 2·H (pórtico traslacional), Lk,z = H (vigas de atado y cruces). Pandeo lateral de dinteles impedido por correas.',
    'Cimentación orientativa: zapatas aisladas ${_f(fs, 1)}x${_f(fs, 1)}x0,6 m de HA-25 sobre terreno σadm = 0,2 N/mm² y viga de atado de cimentación 40x40 cm.',
  ];

  final assembly = [
    'Replanteo de ejes (${nb + 1} pórticos a ${_f(bay, 2)} m) y excavación de zapatas ${_f(fs, 1)}x${_f(fs, 1)} m.',
    'Colocación de pernos M$anchorD con plantilla (doble tuerca de nivelación), hormigón de limpieza y hormigonado HA-25.',
    'Presentación de placas PA1 sobre tuercas de nivelación. Comprobar cota y nivel ±2 mm.',
    'Izado de los pilares del pórtico 1 y pórtico 2; aplomado provisional con tensores/puntales.',
    'Ensamblaje en suelo de cada pareja de dinteles (unión de cumbrera PT2, tornillos M16) y montaje de cartelas.',
    'Izado del dintel completo con grúa (eslingado en 2 puntos, balancín si L > 15 m) y atornillado a pilares (PT1).',
    'Montaje de vigas de atado y cruces de San Andrés del vano 1 → primer módulo estable. Comprobar aplomado y diagonales.',
    'Montaje sucesivo del resto de pórticos y vigas de atado; arriostramiento del último vano.',
    if (gablePost != null) 'Montaje de pilarillos de hastial (PH) y su unión al dintel.',
    'Montaje de correas sobre ejiones (tornillos M12), de alero a cumbrera.',
    'Apriete definitivo de tornillería (par según EN 1090-2), relleno de placas con mortero sin retracción (grout) 30 mm.',
    'Retoques de imprimación en soldaduras de obra y daños; colocación de cubierta y cerramientos.',
    'Seguridad: plataformas elevadoras, líneas de vida en cubierta, redes bajo correas y plan de izado firmado.',
  ];

  warnings.add(
      'Resultados orientativos de predimensionado. Deben ser revisados y firmados por un técnico competente antes de fabricar.');
  return Design(
    spec: s,
    prompt: prompt,
    members: members,
    plates: plates,
    bolts: bolts,
    welds: welds,
    checks: checks,
    hypotheses: hyp,
    assembly: assembly,
    warnings: warnings,
    footings: footings,
    footingSize: fs,
    frameX: frameX,
    gridY: [0, L],
    ridgeHeight: ridgeZ,
  );
}

// ---------------------------------------------------------------------------
// MARQUESINA / PÉRGOLA / COBERTIZO
// ---------------------------------------------------------------------------

Design _designMarquesina(StructureSpec s, String prompt) {
  final g = s.grade;
  final fy = g.fy;
  final lx = s.length;
  final w = s.width;
  final H = s.height;
  final slope = s.slopePct / 100;
  final drop = w * slope; // la cubierta vierte hacia y = w
  final noRoof = s.roofing.contains('sin cubierta');

  final nb = s.bay != null
      ? math.max(1, (lx / s.bay!).round())
      : math.max(1, (lx / 4.5).ceil());
  final bay = lx / nb;
  final frameX = List.generate(nb + 1, (i) => i * bay);
  final midLine = w > 7;
  final gridY = midLine ? [0.0, w / 2, w] : [0.0, w];
  final spanY = midLine ? w / 2 : w;

  final gRoof = _roofingWeight(s.roofing) + (noRoof ? 0 : 0.03);
  final qRoof = noRoof ? s.liveLoad : math.max(s.snow, s.liveLoad);
  final qb = s.wind;
  const ce = 1.9;
  final checks = <Check>[];
  final warnings = <String>[...s.notes];

  // Correas (tubo) a lo largo de x, apoyadas en jácenas transversales
  final nps = math.max(2, (w / (noRoof ? 0.5 : 1.2)).ceil());
  final e = w / nps;
  final purlin = _choose(shsTable.where((p) => p.b >= 40).toList(), (p) {
    final self = p.kgm * 9.81 / 1000;
    final qd = 1.35 * (gRoof * e + self) + 1.5 * qRoof * e;
    final qk = gRoof * e + self + qRoof * e;
    final med = qd * bay * bay / 8;
    final defl = _deflSS(qk, bay, p);
    return [
      Check('Correa ${p.name}', 'Flexión ELU M = q·s²/8', med / _mRd(p, fy),
          'qd = ${_f(qd, 2)} kN/m, s = ${_f(bay, 2)} m, MEd = ${_f(med, 2)} kN·m'),
      Check('Correa ${p.name}', 'Flecha ELS ≤ s/250', defl / (bay * 1000 / 250),
          'δ = ${_f(defl)} mm'),
    ];
  }, checks);

  // Jácenas transversales (dirección y) en cada línea de pilares
  double qdBeam = 0;
  final beamCands = spanY > 4.5 ? ipeTable : [...ipeTable, ...shsTable.where((p) => p.b >= 80)];
  final beam = _choose(beamCands, (p) {
    final self = p.kgm * 9.81 / 1000;
    final purl = purlin.kgm * 9.81 / 1000 * (nps + 1) / w * bay;
    qdBeam = 1.35 * (gRoof * bay + purl + self) + 1.5 * qRoof * bay;
    final qk = gRoof * bay + purl + self + qRoof * bay;
    final med = qdBeam * spanY * spanY / 8;
    final defl = _deflSS(qk, spanY, p);
    return [
      Check('Jácena ${p.name}', 'Flexión ELU M = q·L²/8', med / _mRd(p, fy),
          'qd = ${_f(qdBeam, 2)} kN/m, L = ${_f(spanY, 2)} m, MEd = ${_f(med)} kN·m'),
      Check('Jácena ${p.name}', 'Flecha ELS ≤ L/250', defl / (spanY * 1000 / 250),
          'δ = ${_f(defl)} mm'),
    ];
  }, checks);

  // Vigas perimetrales longitudinales (dirección x) en líneas de pilares
  final edge = _choose(shsTable.where((p) => p.b >= 60).toList(), (p) {
    final self = p.kgm * 9.81 / 1000;
    final qd = 1.35 * (gRoof * e / 2 + self) + 1.5 * qRoof * e / 2;
    final med = qd * bay * bay / 8;
    final defl = _deflSS(qd / 1.4, bay, p);
    return [
      Check('Viga de borde ${p.name}', 'Flexión ELU', med / _mRd(p, fy),
          'MEd = ${_f(med, 2)} kN·m'),
      Check('Viga de borde ${p.name}', 'Flecha ELS ≤ s/300', defl / (bay * 1000 / 300),
          'δ = ${_f(defl)} mm'),
    ];
  }, checks);

  // Pilares (tubo) empotrados en base
  final colH = H + drop;
  final trib = midLine ? spanY : spanY / 2;
  final column = _choose(shsTable.where((p) => p.b >= 60).toList(), (p) {
    final self = p.kgm * 9.81 / 1000 * colH;
    final ned = qdBeam * trib * 1.25 + 1.35 * self; // 1,25 continuidad aprox.
    // viento: borde de cubierta repartido entre líneas de pilares + fuste
    final fEdge = qb * ce * 1.3 * bay * (noRoof ? 0.15 : 0.35) / gridY.length * 2;
    final wCol = qb * ce * 1.2 * p.b / 1000;
    final fk = fEdge + wCol * colH / 2;
    final med = 1.5 * (fEdge * colH + wCol * colH * colH / 2) + ned * 0.03;
    final lb = _lambdaBar(2.0 * colH * 1000, p.ry, fy);
    final nb = _chi(lb, _alphaStrong(p)) * p.area * fy / gammaM1 / 10;
    final mrd = _mRd(p, fy);
    final dx = fk * math.pow(colH * 1000, 3) / (3 * steelE * p.iy * 1e4) * 1000;
    return [
      Check('Pilar ${p.name}', 'Flexocompresión  N/Nb + M/Mc ≤ 1 (ménsula)',
          ned / nb + med / mrd,
          'NEd = ${_f(ned)} kN, MEd = ${_f(med)} kN·m, Lk = 2·h = ${_f(2 * colH)} m, λ̄ = ${_f(lb, 2)}'),
      Check('Pilar ${p.name}', 'Desplome ELS ≤ h/150', dx / (colH * 1000 / 150),
          'δ = ${_f(dx)} mm'),
    ];
  }, checks);

  final members = <Member>[];
  final footings = <Vec3>[];
  double zAt(double y) => H + drop * (1 - y / w); // alto en y=0, bajo en y=w
  for (final x in frameX) {
    for (final y in gridY) {
      members.add(Member(
          role: MemberRole.column,
          profile: column,
          a: Vec3(x, y, 0),
          b: Vec3(x, y, zAt(y) - beam.h / 1000),
          cut: 'Escuadra'));
      footings.add(Vec3(x, y, 0));
    }
    final web = Vec3(0, drop, w).normalized;
    for (var j = 0; j < gridY.length - 1; j++) {
      final y0 = gridY[j], y1 = gridY[j + 1];
      members.add(Member(
          role: MemberRole.beam,
          profile: beam,
          a: Vec3(x, y0 - (j == 0 ? 0.2 : 0), zAt(y0) - beam.h / 2000),
          b: Vec3(x, y1 + (j == gridY.length - 2 ? 0.2 : 0), zAt(y1) - beam.h / 2000),
          webDir: web,
          cut: drop > 0
              ? 'Escuadra (pendiente ${_f(s.slopePct)} %)'
              : 'Escuadra'));
    }
  }
  final webP = Vec3(0, drop, w).normalized;
  for (var i = 0; i < nb; i++) {
    final x0 = frameX[i], x1 = frameX[i + 1];
    for (var k = 1; k < nps; k++) {
      final y = k * e;
      members.add(Member(
          role: MemberRole.purlin,
          profile: purlin,
          a: Vec3(x0, y, zAt(y) + purlin.h / 2000),
          b: Vec3(x1, y, zAt(y) + purlin.h / 2000),
          webDir: webP));
    }
    for (final y in gridY) {
      members.add(Member(
          role: MemberRole.tie,
          profile: edge,
          a: Vec3(x0, y, zAt(y) - beam.h / 1000 - edge.h / 2000),
          b: Vec3(x1, y, zAt(y) - beam.h / 1000 - edge.h / 2000)));
    }
  }

  // Tornapuntas a 45° en pilares extremos (rigidez longitudinal)
  final kb = shsTable.firstWhere((p) => p.b >= 50 && p.tw >= 3);
  final kl = math.min(0.8, bay / 3);
  for (final y in gridY) {
    final ztop = zAt(y) - beam.h / 1000 - edge.h / 1000;
    for (final pair in [
      [frameX.first, 1.0],
      [frameX.last, -1.0]
    ]) {
      members.add(Member(
          role: MemberRole.brace,
          profile: kb,
          a: Vec3(pair[0], y, ztop - kl),
          b: Vec3(pair[0] + pair[1] * kl, y, ztop),
          cut: 'Inglete 45° ambos extremos'));
    }
  }

  final nCols = frameX.length * gridY.length;
  final fEdgeK = qb * ce * 1.3 * bay * (noRoof ? 0.15 : 0.35) / gridY.length * 2;
  final mBase = 1.5 * (fEdgeK * colH + qb * ce * 1.2 * column.b / 1000 * colH * colH / 2);
  final pw = _roundUp(column.b + 200, 50);
  final tp = _stdPlate(math.max(15.0,
      math.sqrt(6 * mBase * 1e6 / 4 / (pw * fy / gammaM0)) * 0.6)); // ménsula de placa aprox.
  final anchorD = mBase > 15 ? 20 : 16;
  final plates = <PlatePiece>[
    PlatePiece(
        mark: 'PA1',
        description: 'Placa de anclaje empotrada pilar ${column.name}',
        w: pw,
        h: pw,
        t: tp,
        qty: nCols,
        notes: '4 pernos M$anchorD; 4 cartelas rigidizadoras CR1'),
    PlatePiece(
        mark: 'CR1',
        description: 'Cartela rigidizadora de placa',
        w: _roundUp((pw - column.b) / 2, 5),
        h: 150,
        t: 8,
        qty: nCols * 4),
    PlatePiece(
        mark: 'PC1',
        description: 'Placa de cabeza de pilar',
        w: _roundUp(math.max(column.b, beam.b) + 40, 10),
        h: _roundUp(math.max(column.b, beam.b) + 40, 10),
        t: 10,
        qty: nCols,
        notes: '4 taladros Ø14 para M12 a jácena'),
  ];
  final bolts = <BoltItem>[
    BoltItem('Pernos de anclaje',
        'M$anchorD x ${anchorD * 25} mm B500S roscado + 2 tuercas (o anclaje químico M$anchorD en losa existente)',
        nCols * 4, 'Placas PA1'),
    BoltItem('Tornillos cabeza pilar', 'M12 x 40 8.8 + tuerca + arandela', nCols * 4,
        'Pilar-jácena'),
    BoltItem('Tornillos / tirafondos de correas',
        'Soldadas a jácena (alternativa: casquillo + M10)', 0, ''),
  ];
  final aCol = weldThroat(column.tw, tp, g);
  final welds = <WeldSpec>[
    WeldSpec(
        joint: 'Pilar – placa de anclaje (PA1)',
        type: 'En ángulo perimetral',
        throat: aCol,
        lengthPerJoint: 4 * column.b,
        count: nCols),
    WeldSpec(
        joint: 'Cartelas CR1 – pilar y placa',
        type: 'En ángulo doble cordón',
        throat: 5,
        lengthPerJoint: 2 * (150 + (pw - column.b) / 2),
        count: nCols * 4),
    WeldSpec(
        joint: 'Pilar – placa de cabeza (PC1)',
        type: 'En ángulo perimetral',
        throat: weldThroat(column.tw, 10, g),
        lengthPerJoint: 4 * column.b,
        count: nCols),
    WeldSpec(
        joint: 'Correa – jácena / viga borde',
        type: 'En ángulo perimetral (tubo sobre perfil)',
        throat: weldThroat(purlin.tw, beam.tf, g),
        lengthPerJoint: 4 * purlin.b,
        count: (nps - 1) * nb * 2,
        position: 'PA/PB taller o PF en obra'),
    WeldSpec(
        joint: 'Viga de borde – jácena',
        type: 'En ángulo perimetral',
        throat: weldThroat(edge.tw, beam.tw, g),
        lengthPerJoint: 4 * edge.b,
        count: nb * gridY.length * 2),
    WeldSpec(
        joint: 'Tornapuntas – pilar y viga',
        type: 'En ángulo perimetral (corte a inglete)',
        throat: weldThroat(kb.tw, column.tw, g),
        lengthPerJoint: 4 * kb.b * 1.41,
        count: gridY.length * 2 * 2),
  ];
  final nColK = (gRoof + qRoof) * bay * trib * 1.25;
  final fs = math.max(0.8, _roundUp(math.sqrt(nColK / 150) + 0.3, 0.1));
  checks.add(Check('Placa de anclaje ${_f(pw, 0)}x${_f(pw, 0)}x${_f(tp, 0)}',
      'Empotramiento: momento de base (pernos traccionados)',
      (mBase / (pw / 1000 * 0.8)) /
          (2 * 0.9 * 800 * (anchorD == 20 ? 245 : 157) / 1250),
      'MEd = ${_f(mBase)} kN·m; tracción por 2 pernos M$anchorD 8.8'));

  final hyp = [
    ..._commonHypotheses(s),
    'Pilares empotrados en base (ménsula), jácenas biapoyadas en cabeza, correas biapoyadas.',
    'Planta ${_f(lx, 2)} x ${_f(w, 2)} m; ${nb} vanos de ${_f(bay, 2)} m; altura libre ${_f(H, 2)} m; pendiente ${_f(s.slopePct)} % hacia la fachada trasera.',
    'Cubierta: ${s.roofing}. Correas a ${_f(e, 2)} m.',
    noRoof
        ? 'Sin cubierta: sin nieve acumulada; mantenimiento 0,4 kN/m².'
        : 'Nieve sk = ${_f(s.snow, 2)} kN/m²; uso G1 0,4 kN/m² no concomitante.',
    'Viento qb = ${_f(qb, 2)} kN/m², ce ≈ 1,9, cf ≈ 1,3 (marquesina) – simplificado; succión ascendente a comprobar en anclajes de cubierta.',
    'Cimentación orientativa: zapatas ${_f(fs, 1)}x${_f(fs, 1)}x0,6 m HA-25 (o anclaje químico en solera existente ≥ 15 cm previa comprobación).',
  ];

  final assembly = [
    'Replanteo de ${nCols} apoyos (ejes a ${_f(bay, 2)} m en x y ${gridY.map((v) => _f(v, 2)).join(' / ')} m en y).',
    'Ejecución de zapatas con pernos M$anchorD en plantilla, o taladro y anclaje químico si hay losa.',
    'Soldadura en taller de placas PA1, cartelas CR1 y placa de cabeza PC1 a cada pilar.',
    'Presentación y aplomado de pilares sobre tuercas de nivelación; apriete y grout.',
    'Montaje de jácenas transversales atornilladas a la cabeza de pilar (M12).',
    'Colocación de vigas de borde y tornapuntas; comprobación de escuadra (diagonales iguales).',
    'Colocación y soldadura de correas; repaso de soldaduras de obra con imprimación rica en zinc.',
    'Colocación de ${s.roofing}, canalón en el lado bajo y bajantes por el interior de un pilar si se desea.',
  ];
  warnings.add(
      'Resultados orientativos de predimensionado. Deben ser revisados y firmados por un técnico competente antes de fabricar.');
  return Design(
    spec: s,
    prompt: prompt,
    members: members,
    plates: plates,
    bolts: bolts.where((b) => b.qty > 0).toList(),
    welds: welds,
    checks: checks,
    hypotheses: hyp,
    assembly: assembly,
    warnings: warnings,
    footings: footings,
    footingSize: fs,
    frameX: frameX,
    gridY: gridY,
    ridgeHeight: H + drop,
  );
}

// ---------------------------------------------------------------------------
// ENTREPLANTA / ALTILLO
// ---------------------------------------------------------------------------

Design _designEntreplanta(StructureSpec s, String prompt) {
  final g = s.grade;
  final fy = g.fy;
  final lx = s.length;
  final w = s.width;
  final H = s.height;
  final q = s.liveLoad;
  final gDeck = _roofingWeight(s.roofing) + 0.1;
  final checks = <Check>[];
  final warnings = <String>[...s.notes];

  final nb = s.bay != null
      ? math.max(1, (lx / s.bay!).round())
      : math.max(1, (lx / 5.0).ceil());
  final sx = lx / nb;
  final ny = math.max(1, (w / 5.0).ceil());
  final sy = w / ny;
  final frameX = List.generate(nb + 1, (i) => i * sx);
  final gridY = List.generate(ny + 1, (j) => j * sy);

  final colaborante = s.roofing.contains('colaborante');
  final ej = colaborante ? 2.0 : (s.roofing.contains('tramex') ? 1.0 : 0.6);
  final nj = math.max(1, (lx / ej).ceil());
  final e = lx / nj;

  // Viguetas (dirección y, luz sy)
  final joist = _choose(ipeTable, (p) {
    final self = p.kgm * 9.81 / 1000;
    final qd = 1.35 * (gDeck * e + self) + 1.5 * q * e;
    final qk = gDeck * e + self + q * e;
    final med = qd * sy * sy / 8;
    final defl = _deflSS(qk, sy, p);
    return [
      Check('Vigueta ${p.name}', 'Flexión ELU M = q·L²/8', med / _mRd(p, fy),
          'qd = ${_f(qd, 2)} kN/m, L = ${_f(sy, 2)} m, MEd = ${_f(med)} kN·m'),
      Check('Vigueta ${p.name}', 'Flecha ELS ≤ L/300', defl / (sy * 1000 / 300),
          'δ = ${_f(defl)} mm'),
    ];
  }, checks);

  // Vigas principales (dirección x, luz sx) – líneas interiores con ancho sy
  double qdBeam = 0;
  final beam = _choose([...ipeTable, ...hebTable], (p) {
    final self = p.kgm * 9.81 / 1000;
    final jl = joist.kgm * 9.81 / 1000 * sy / e;
    final trib = ny > 1 ? sy : sy / 2;
    qdBeam = 1.35 * (gDeck * trib + jl + self) + 1.5 * q * trib;
    final qk = gDeck * trib + jl + self + q * trib;
    final med = qdBeam * sx * sx / 8;
    final defl = _deflSS(qk, sx, p);
    return [
      Check('Viga ${p.name}', 'Flexión ELU M = q·L²/8', med / _mRd(p, fy),
          'qd = ${_f(qdBeam, 2)} kN/m, L = ${_f(sx, 2)} m, MEd = ${_f(med)} kN·m'),
      Check('Viga ${p.name}', 'Flecha ELS ≤ L/300', defl / (sx * 1000 / 300),
          'δ = ${_f(defl)} mm'),
    ];
  }, checks);

  // Pilares
  final ned = qdBeam * sx * (nb > 1 ? 1.0 : 0.5);
  final colH = H - beam.h / 1000;
  final column = _choose([...shsTable.where((p) => p.b >= 80), ...hebTable], (p) {
    final self = 1.35 * p.kgm * 9.81 / 1000 * colH;
    final n = ned + self;
    final ecc = (p.h / 2 + 50) / 1000;
    final med = n * ecc;
    final lb = _lambdaBar(colH * 1000, math.min(p.ry, p.rz), fy);
    final nbRd = _chi(lb, _alphaWeak(p)) * p.area * fy / gammaM1 / 10;
    return [
      Check('Pilar ${p.name}', 'Pandeo + excentricidad  N/Nb + M/Mc ≤ 1',
          n / nbRd + med / _mRd(p, fy),
          'NEd = ${_f(n)} kN, e = ${_f(ecc * 1000, 0)} mm, Lk = ${_f(colH, 2)} m, λ̄ = ${_f(lb, 2)}, Nb,Rd = ${_f(nbRd)} kN'),
    ];
  }, checks);

  final members = <Member>[];
  final footings = <Vec3>[];
  final zTop = H;
  for (final x in frameX) {
    for (final y in gridY) {
      members.add(Member(
          role: MemberRole.column,
          profile: column,
          a: Vec3(x, y, 0),
          b: Vec3(x, y, zTop - beam.h / 1000),
          webDir: const Vec3(1, 0, 0)));
      footings.add(Vec3(x, y, 0));
    }
  }
  for (final y in gridY) {
    for (var i = 0; i < nb; i++) {
      members.add(Member(
          role: MemberRole.beam,
          profile: beam,
          a: Vec3(frameX[i], y, zTop - beam.h / 2000),
          b: Vec3(frameX[i + 1], y, zTop - beam.h / 2000)));
    }
  }
  for (var k = 0; k <= nj; k++) {
    final x = k * e;
    for (var j = 0; j < ny; j++) {
      members.add(Member(
          role: MemberRole.joist,
          profile: joist,
          a: Vec3(x, gridY[j], zTop - joist.h / 2000),
          b: Vec3(x, gridY[j + 1], zTop - joist.h / 2000)));
    }
  }
  // Cruces de arriostramiento (un vano por dirección)
  final hTot = (q + gDeck) * lx * w;
  final fh = 1.5 * hTot / 100 + 0.8 * lx * 0; // imperfección 1/100 aprox.
  final brace = _choose(angleTable, (p) {
    final dl = math.sqrt(sx * sx + colH * colH);
    final n = fh / 2 * dl / sx;
    return [
      Check('Arriostramiento ${p.name}', 'Tracción (imperfecciones 1/100 + empujes)',
          n / (_nPl(p, fy) * 0.85), 'NEd = ${_f(n)} kN'),
    ];
  }, checks);
  void cross(Vec3 a, Vec3 b, Vec3 c, Vec3 d) {
    members.add(Member(role: MemberRole.brace, profile: brace, a: a, b: d));
    members.add(Member(role: MemberRole.brace, profile: brace, a: c, b: b));
  }

  final zb = colH - 0.1;
  cross(Vec3(0, 0, 0.2), Vec3(0, 0, zb), Vec3(sx, 0, 0.2), Vec3(sx, 0, zb));
  cross(Vec3(0, w, 0.2), Vec3(0, w, zb), Vec3(sx, w, 0.2), Vec3(sx, w, zb));
  cross(Vec3(0, 0, 0.2), Vec3(0, 0, zb), Vec3(0, sy, 0.2), Vec3(0, sy, zb));
  cross(Vec3(lx, 0, 0.2), Vec3(lx, 0, zb), Vec3(lx, sy, 0.2), Vec3(lx, sy, zb));

  // Barandilla (CTE DB-SUA 1 y DB-SE-AE 3.2)
  SteelProfile? post, rail, bal;
  int balusters = 0;
  if (s.railing) {
    final hr = H >= 6 ? 1.10 : 0.90;
    post = _choose(shsTable.where((p) => p.b >= 40).toList(), (p) {
      final med = 1.5 * 0.8 * 1.5 * hr; // 0,8 kN/m a 1,5 m de separación
      return [
        Check('Montante barandilla ${p.name}', 'Empuje horizontal 0,8 kN/m',
            med / _mRd(p, fy), 'MEd = ${_f(med, 2)} kN·m, h = ${_f(hr, 2)} m'),
      ];
    }, checks);
    rail = shsTable.firstWhere((p) => p.b >= 40 && p.tw >= 2);
    bal = shsTable.first;
    final z0 = zTop + 0.02;
    final gap = 1.0; // hueco para escalera
    final runs = <List<Vec3>>[
      [Vec3(0, 0, z0), Vec3(lx - gap, 0, z0)],
      [Vec3(lx, 0, z0), Vec3(lx, w, z0)],
      [Vec3(lx, w, z0), Vec3(0, w, z0)],
      [Vec3(0, w, z0), Vec3(0, 0, z0)],
    ];
    for (final r in runs) {
      final a = r[0], b = r[1];
      final len = (b - a).length;
      final np = math.max(1, (len / 1.5).ceil());
      for (var k = 0; k <= np; k++) {
        final p = a + (b - a) * (k / np);
        members.add(Member(
            role: MemberRole.post,
            profile: post,
            a: p,
            b: p + Vec3(0, 0, hr)));
      }
      members.add(Member(
          role: MemberRole.handrail,
          profile: rail,
          a: a + Vec3(0, 0, hr),
          b: b + Vec3(0, 0, hr)));
      members.add(Member(
          role: MemberRole.handrail,
          profile: rail,
          a: a + Vec3(0, 0, 0.1),
          b: b + Vec3(0, 0, 0.1)));
      final nbal = (len / 0.11).floor();
      for (var k = 1; k < nbal; k++) {
        if (k % ((1.5 / 0.11).round()) == 0) continue;
        final p = a + (b - a) * (k / nbal);
        members.add(Member(
            role: MemberRole.baluster,
            profile: bal,
            a: p + Vec3(0, 0, 0.12),
            b: p + Vec3(0, 0, hr - 0.02)));
        balusters++;
      }
    }
  }

  final nCols = frameX.length * gridY.length;
  final pw = _roundUp(column.b + 120, 50);
  final sigma = ned * 1000 / (pw * pw);
  final tp = _stdPlate(math.max(12.0, 50 * math.sqrt(3 * math.max(sigma, 2) * gammaM0 / fy)));
  checks.add(Check('Placa base ${_f(pw, 0)}x${_f(pw, 0)}x${_f(tp, 0)}',
      'Presión sobre solera σ ≤ fjd', sigma / 10.0,
      'σ = ${_f(sigma, 2)} N/mm² (solera HA-25, fjd ≈ 10 N/mm² conservador)'));

  final plates = <PlatePiece>[
    PlatePiece(
        mark: 'PA1',
        description: 'Placa base pilar ${column.name}',
        w: pw,
        h: pw,
        t: tp,
        qty: nCols,
        notes: '4 anclajes químicos M12/M16'),
    PlatePiece(
        mark: 'PC1',
        description: 'Placa de cabeza de pilar',
        w: _roundUp(beam.b + 40, 10),
        h: _roundUp(column.b + 60, 10),
        t: 12,
        qty: nCols),
    PlatePiece(
        mark: 'CS1',
        description: 'Casquillo vigueta-viga (chapa de alma)',
        w: _roundUp(joist.h * 0.7, 10),
        h: 100,
        t: 8,
        qty: (nj + 1) * ny * 2,
        notes: '2 taladros Ø14 (M12)'),
    PlatePiece(
        mark: 'GU1',
        description: 'Cartela de arriostramiento',
        w: 180,
        h: 180,
        t: 8,
        qty: 16),
  ];
  final bolts = <BoltItem>[
    BoltItem('Anclaje químico', column.b >= 120 ? 'M16 x 190 varilla 8.8 + resina epoxi' : 'M12 x 160 varilla 8.8 + resina epoxi',
        nCols * 4, 'Placas PA1 sobre solera ≥ 15 cm'),
    BoltItem('Tornillos viga-pilar', 'M16 x 45 8.8 + tuerca + arandela', nCols * 4, 'PC1'),
    BoltItem('Tornillos vigueta-viga', 'M12 x 35 8.8 + tuerca + arandela', (nj + 1) * ny * 2 * 2, 'CS1'),
    BoltItem('Tornillos arriostramiento', 'M12 x 35 8.8', 16 * 2, 'GU1'),
    BoltItem('Fijación de tablero/chapa', colaborante ? 'Conectores / clavos Hilti' : 'Tornillo autotaladrante 6,3 mm', (lx * w * 6).ceil(), 'Suelo'),
  ];
  final welds = <WeldSpec>[
    WeldSpec(
        joint: 'Pilar – placa base (PA1)',
        type: 'En ángulo perimetral',
        throat: weldThroat(column.tMin, tp, g),
        lengthPerJoint: column.isHollow
            ? 4 * column.b
            : 2 * (2 * column.b - column.tw) + 2 * (column.h - 2 * column.tf),
        count: nCols),
    WeldSpec(
        joint: 'Pilar – placa de cabeza (PC1)',
        type: 'En ángulo perimetral',
        throat: weldThroat(column.tMin, 12, g),
        lengthPerJoint: column.isHollow ? 4 * column.b : 2 * (2 * column.b),
        count: nCols),
    WeldSpec(
        joint: 'Casquillo CS1 – alma de viga',
        type: 'En ángulo doble cordón',
        throat: weldThroat(math.min(beam.tw, 8), 8, g),
        lengthPerJoint: 2 * joist.h * 0.7,
        count: (nj + 1) * ny * 2),
    WeldSpec(
        joint: 'Cartela GU1 – pilar/viga',
        type: 'En ángulo doble cordón',
        throat: 4,
        lengthPerJoint: 2 * 180,
        count: 16),
    if (s.railing)
      WeldSpec(
          joint: 'Barandilla: montantes, pasamanos y barrotes',
          type: 'En ángulo perimetral (tubo)',
          throat: 3,
          lengthPerJoint: 4 * 20,
          count: balusters * 2 + 200,
          process: '135 (MAG) hilo 0,8 mm / 141 (TIG) en acabados vistos',
          position: 'PA/PB taller'),
  ];

  final hyp = [
    ..._commonHypotheses(s),
    'Planta ${_f(lx, 2)} x ${_f(w, 2)} m a ${_f(H, 2)} m de altura. Retícula de pilares ${_f(sx, 2)} x ${_f(sy, 2)} m.',
    'Uso: ${s.use}. Sobrecarga q = ${_f(q, 2)} kN/m² (CTE DB-SE-AE tabla 3.1). Suelo: ${s.roofing} (${_f(gDeck, 2)} kN/m² incl. acabados).',
    'Viguetas biapoyadas cada ${_f(e, 2)} m; vigas biapoyadas en cabeza de pilar. Pandeo lateral impedido por el forjado.',
    'Pilares biarticulados con arriostramiento en cruz (1 vano por dirección). Excentricidad de apoyo h/2 + 50 mm.',
    if (s.railing)
      'Barandilla h = ${H >= 6 ? '1,10' : '0,90'} m (CTE DB-SUA 1 §3.2), barrotes verticales cada ≤ 10 cm (no escalable), empuje 0,8 kN/m. Hueco de 1 m para escalera (escalera no incluida).',
    'Apoyo sobre solera existente: comprobar espesor (≥ 15 cm) y capacidad del terreno con carga puntual de ${_f(ned / 1.45, 0)} kN aprox. por pilar.',
  ];
  final assembly = [
    'Replanteo de ${nCols} pilares y comprobación de la solera (catas).',
    'Presentación de pilares con placa PA1 soldada; taladro y anclaje químico; aplomado.',
    'Montaje de vigas principales sobre placas de cabeza PC1 (M16).',
    'Montaje de cruces de arriostramiento antes de cargar el forjado.',
    'Colocación de viguetas sobre casquillos CS1 (M12) cada ${_f(e, 2)} m.',
    'Colocación y fijación del suelo (${s.roofing}).',
    if (s.railing) 'Montaje de barandilla perimetral por tramos soldados en taller y atornillados en obra.',
    'Señalización de carga máxima admisible (${_f(q * 100, 0)} kg/m²) en lugar visible.',
  ];
  warnings.add(
      'Resultados orientativos de predimensionado. Deben ser revisados y firmados por un técnico competente antes de fabricar.');
  if (s.railing) {
    warnings.add('Escalera de acceso no incluida en el cálculo (prever CTE DB-SUA: huella ≥ 28 cm, contrahuella 13–18,5 cm).');
  }
  return Design(
    spec: s,
    prompt: prompt,
    members: members,
    plates: plates,
    bolts: bolts,
    welds: welds,
    checks: checks,
    hypotheses: hyp,
    assembly: assembly,
    warnings: warnings,
    footings: footings,
    footingSize: 0.0,
    frameX: frameX,
    gridY: gridY,
    ridgeHeight: H,
  );
}
