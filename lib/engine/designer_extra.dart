part of 'designer.dart';

// ===========================================================================
// Tipologías adicionales: escaleras, pasarelas, barandillas, cerchas, torres,
// estanterías, cancelas, vallas, pórticos de elevación y postes / carteles.
// Mismo criterio que el resto: predimensionado ELU/ELS simplificado (CTE / EC3).
// ===========================================================================

double _self(SteelProfile p) => p.kgm * 9.81 / 1000; // kN/m

/// Coeficiente de exposición aproximado (CTE DB-SE-AE, entorno III).
double _ce(double z) => z <= 3 ? 1.7 : (z <= 6 ? 2.0 : (z <= 12 ? 2.4 : 2.7));

/// Anclajes (químico / perno 8.8) con tracción de cálculo orientativa en hormigón C20/25 (kN).
const _anchors = <(String, double)>[('M10', 9), ('M12', 14), ('M16', 24), ('M20', 36), ('M24', 50)];

(String, double) _anchorFor(double tEd) =>
    _anchors.firstWhere((a) => a.$2 >= tEd, orElse: () => _anchors.last);

/// Viga biapoyada con carga uniforme (y puntual centrada opcional).
SteelProfile _beamFor(List<SteelProfile> cands, String what, double qd, double qk, double l, double fy,
    List<Check> checks,
    {double defl = 300, double pd = 0, double pk = 0}) {
  return _choose(cands, (p) {
    final qdd = qd + 1.35 * _self(p), qkk = qk + _self(p);
    final med = qdd * l * l / 8 + pd * l / 4;
    final d = _deflSS(qkk, l, p) + pk * 1000 * math.pow(l * 1000, 3) / (48 * _youngE * p.iy * 1e4);
    return [
      Check('$what ${p.name}', 'Flexión ELU', med / _mRd(p, fy),
          'qd = ${_f(qdd, 2)} kN/m${pd > 0 ? ', Pd = ${_f(pd)} kN' : ''}, L = ${_f(l, 2)} m, MEd = ${_f(med, 2)} kN·m'),
      Check('$what ${p.name}', 'Flecha ELS ≤ L/${defl.toStringAsFixed(0)}', d / (l * 1000 / defl), 'δ = ${_f(d)} mm'),
    ];
  }, checks);
}

/// Soporte a compresión (y flexión) con longitud de pandeo dada.
SteelProfile _columnFor(List<SteelProfile> cands, String what, double nEd, double mEd, double lk, double fy,
    List<Check> checks) {
  return _choose(cands, (p) {
    final lb = _lambdaBar(lk * 1000, math.min(p.ry, p.rz), fy);
    final nbRd = _chi(lb, _alphaWeak(p)) * p.area * fy / gammaM1 / 10;
    final u = nEd / nbRd + (mEd > 0 ? mEd / _mRd(p, fy) : 0);
    return [
      Check('$what ${p.name}', mEd > 0 ? 'Flexocompresión N/Nb + M/Mc ≤ 1' : 'Pandeo N/Nb,Rd ≤ 1', u,
          'NEd = ${_f(nEd)} kN${mEd > 0 ? ', MEd = ${_f(mEd, 2)} kN·m' : ''}, Lk = ${_f(lk, 2)} m, λrel = ${_f(lb, 2)}, Nb,Rd = ${_f(nbRd)} kN'),
    ];
  }, checks);
}

/// Barra a tracción (arriostramientos en cruz).
SteelProfile _tieFor(String what, double nEd, double fy, List<Check> checks, {List<SteelProfile>? cands}) {
  return _choose(cands ?? angleTable, (p) {
    return [Check('$what ${p.name}', 'Tracción (sección neta ≈ 85 %)', nEd / (_nPl(p, fy) * 0.85), 'NEd = ${_f(nEd)} kN')];
  }, checks);
}

/// Placa base con pernos: dimensiones según perfil y tracción por momento.
({double w, double t, String anchor, int bolts}) _basePlate(
    SteelProfile p, double nEd, double mEd, double fy, List<Check> checks, String mark,
    {int bolts = 4, double minW = 150}) {
  var w = math.max(minW, _roundUp(math.max(p.h, p.b) + 120, 10));
  var tens = 0.0;
  if (mEd > 0) {
    for (var k = 0; k < 10; k++) {
      final z = (w - 60) / 1000;
      tens = math.max(0.0, mEd / z - nEd / 2) / (bolts / 2);
      if (tens <= _anchors.last.$2 * 0.8 || w >= 700) break;
      w += 50;
    }
  }
  final a = _anchorFor(tens);
  final m = math.max(30.0, (w - math.min(p.b, p.h)) / 2 - 10);
  final sigma = math.max(1.0, nEd * 1000 / (w * w) + (mEd > 0 ? 6 * mEd * 1e6 / (w * w * w) : 0));
  var t = m * math.sqrt(3 * sigma * gammaM0 / fy);
  if (tens > 0) t = math.max(t, math.sqrt(4 * tens * 1000 * 40 * gammaM0 / (w / 2 * fy)));
  t = _stdPlate(math.max(t, 8));
  checks.add(Check('Placa $mark ${_f(w, 0)}x${_f(w, 0)}x${_f(t, 0)}', 'Pernos a tracción / presión',
      math.max(tens / a.$2, sigma / 10),
      'σ = ${_f(sigma, 2)} N/mm², Ft,Ed = ${_f(tens)} kN por perno; anclaje ${a.$1} (≈ ${_f(a.$2, 0)} kN)'));
  return (w: w, t: t, anchor: a.$1, bolts: bolts);
}

/// Barandilla genérica: montantes, pasamanos, larguero inferior y barrotes.
class _Rail {
  int posts = 0;
  int balusters = 0;
  double meters = 0;
  bool secondRail = false;
  late SteelProfile post;
}

/// Barandilla de tubo redondo: inoxidable, aluminio o pedida expresamente.
bool _tubularRailing(StructureSpec s, String t) =>
    s.grade.kind == MaterialKind.stainless || s.grade.kind == MaterialKind.aluminium || RegExp(r'tubo redondo|tubular|redond|inox').hasMatch(t);

/// «doble pasamanos», «dos pasamanos», «pasamanos a dos alturas»…
bool _doubleHandrail(String t) =>
    RegExp(r'(?:doble|dos|2) pasamanos|pasamanos (?:doble|a dos alturas|a doble altura)|segundo pasamanos').hasMatch(t);

_Rail _railing(List<Member> members, List<Check> checks, List<(Vec3, Vec3)> runs, double hr, double fy,
    {double lineLoad = 0.8,
    double spacing = 1.5,
    bool bars = true,
    SteelProfile? baluster,
    double barStep = 0.11,
    bool tubular = false,
    bool doubleRail = false}) {
  final r = _Rail();
  // Tubular (inox, «tubo», «redondo»): montantes y pasamanos de tubo redondo
  // y barrotes de redondo macizo, como se fabrican las barandillas de inox.
  final postCands = tubular ? chsTable.where((p) => p.h >= 42 && p.h <= 61).toList() : shsTable.where((p) => p.b >= 40).toList();
  r.post = _choose(postCands, (p) {
    final med = 1.5 * lineLoad * spacing * hr;
    return [
      Check('Montante ${p.name}', 'Empuje horizontal ${_f(lineLoad)} kN/m (DB-SE-AE 3.2)', med / _mRd(p, fy),
          'MEd = ${_f(med, 2)} kN·m, h = ${_f(hr, 2)} m, separación ${_f(spacing, 2)} m'),
    ];
  }, checks);
  final rail = tubular ? chsTable.firstWhere((p) => p.h >= 42) : shsTable.firstWhere((p) => p.b >= 40 && p.tw >= 2);
  final bal = baluster ?? (tubular ? roundTable.firstWhere((p) => p.h >= 14) : shsTable.first);
  final rail2 = chsTable.firstWhere((p) => p.h >= 42);
  for (final (a, b) in runs) {
    final d = b - a;
    final horiz = math.sqrt(d.x * d.x + d.y * d.y);
    if (horiz < 0.05) continue;
    final np = math.max(1, (horiz / spacing).ceil());
    for (var k = 0; k <= np; k++) {
      final p = a + d * (k / np);
      members.add(Member(role: MemberRole.post, profile: r.post, a: p, b: p + Vec3(0, 0, hr)));
      r.posts++;
    }
    members.add(Member(role: MemberRole.handrail, profile: rail, a: a + Vec3(0, 0, hr), b: b + Vec3(0, 0, hr)));
    members.add(Member(role: MemberRole.rail, profile: rail, a: a + Vec3(0, 0, 0.1), b: b + Vec3(0, 0, 0.1)));
    if (doubleRail) {
      // Segundo pasamanos (CTE DB-SUA 1 §4.2.4: 65–75 cm) por la cara interior,
      // sobre soportes soldados a cada montante, separado ≥ 4 cm del relleno.
      final nrm = Vec3(-d.y, d.x, 0) * (1 / horiz);
      final off = nrm * (r.post.b / 2000 + 0.05 + rail2.h / 2000);
      const z2 = 0.70;
      members.add(Member(role: MemberRole.handrail, profile: rail2, a: a + off + Vec3(0, 0, z2), b: b + off + Vec3(0, 0, z2)));
      for (var k = 0; k <= np; k++) {
        final p = a + d * (k / np);
        members.add(Member(role: MemberRole.bracket, profile: roundTable.firstWhere((q) => q.h >= 14),
            a: p + nrm * (r.post.b / 2000) + Vec3(0, 0, z2 - 0.05), b: p + off + Vec3(0, 0, z2 - rail2.h / 2000)));
      }
      r.secondRail = true;
    }
    r.meters += d.length;
    if (bars) {
      final nbal = (horiz / barStep).floor();
      final seg = horiz / np;
      for (var k = 1; k < nbal; k++) {
        final xh = horiz * k / nbal;
        final rem = xh % seg;
        if (rem < 0.06 || seg - rem < 0.06) continue;
        final p = a + d * (k / nbal);
        members.add(Member(role: MemberRole.baluster, profile: bal, a: p + Vec3(0, 0, 0.12), b: p + Vec3(0, 0, hr - 0.02)));
        r.balusters++;
      }
    }
  }
  return r;
}

WeldSpec _railWeld(_Rail r) => WeldSpec(
    joint: 'Barandilla: montantes, pasamanos, largueros y barrotes',
    type: 'En ángulo perimetral (tubo)',
    throat: 3,
    lengthPerJoint: 80,
    count: r.balusters * 2 + r.posts * 3,
    process: '135 (MAG) hilo 0,8 mm / 141 (TIG) en acabados vistos',
    position: 'PA/PB taller');

void _cross(List<Member> ms, SteelProfile p, Vec3 bl, Vec3 tl, Vec3 br, Vec3 tr) {
  ms.add(Member(role: MemberRole.brace, profile: p, a: bl, b: tr));
  ms.add(Member(role: MemberRole.brace, profile: p, a: br, b: tl));
}

String _warnValidate() =>
    'Resultados orientativos de predimensionado. Deben ser revisados y firmados por un técnico competente antes de fabricar.';

// ---------------------------------------------------------------------------
// ESCALERA
// ---------------------------------------------------------------------------

Design _designEscalera(StructureSpec s, String prompt) {
  final form = stairForms.firstWhere((f) => s.variant.startsWith(f), orElse: () => 'recta');
  if (form == 'caracol') return _designCaracol(s, prompt);
  if (form == 'escala de gato') return _designEscalaGato(s, prompt);
  final turn = form == 'en l' ? 90 : (form == 'en u' ? 180 : 0);
  final central = form == 'zanca central';
  final g = s.grade, fy = g.fy;
  final hTot = s.height, w = s.width, q = s.liveLoad;
  final checks = <Check>[];
  final warnings = <String>[...s.notes];
  final members = <Member>[];
  final surfaces = <Surface>[];
  final footings = <Vec3>[];
  final tramex = s.roofing.contains('tramex');

  // Peldañeado (CTE DB-SUA 1 §4.2): contrahuella 13–18,5 cm, huella ≥ 28 cm, 54 ≤ 2C + H ≤ 70 cm
  final flights = math.max(turn > 0 ? 2 : 1, (hTot / 3.2 - 1e-9).ceil());
  var n = (hTot / 0.175).ceil();
  if (n % flights != 0) n += flights - n % flights;
  final c = hTot / n;
  final tr = (0.63 - 2 * c).clamp(0.28, 0.32).toDouble();
  final per = n ~/ flights;
  const gap = 0.2; // ojo de la escalera en U
  final landing = turn == 90 ? w : math.max(1.0, w); // fondo de la meseta
  final landW = turn == 180 ? 2 * w + gap : w; // ancho de la meseta
  final hf = per * c;
  final runF = math.max(0.01, (per - 1) * tr);
  final alpha = math.atan2(hf, runF);
  checks.add(Check('Peldañeado', 'Contrahuella ≤ 18,5 cm y 54 ≤ 2C + H ≤ 70 cm', c / 0.185,
      '$n peldaños: C = ${_f(c * 100)} cm, H = ${_f(tr * 100)} cm, 2C + H = ${_f((2 * c + tr) * 100)} cm, '
      '${flights > 1 ? '$flights tramos con meseta${turn > 0 ? ' de giro' : ''}' : '1 tramo'}'));

  // Peldaños (tramex o chapa lagrimada plegada): flexión con carga uniforme y puntual
  final qPoint = q >= 4 ? 4.0 : 2.0;
  final gTread = tramex ? 0.35 : 0.45;
  final treadOpts = tramex
      ? <(String, double)>[
          ('Peldaño tramex 30x30, pletina 30x2', 33 * 2 * 30 * 30 / 6),
          ('Peldaño tramex 30x30, pletina 30x3', 33 * 3 * 30 * 30 / 6),
          ('Peldaño tramex 30x30, pletina 40x3', 33 * 3 * 40 * 40 / 6),
        ]
      : <(String, double)>[
          ('Peldaño chapa lagrimada 4 mm plegada (pestañas 40 mm)', 2 * 4 * 40 * 40 / 6 / tr),
          ('Peldaño chapa lagrimada 5 mm plegada (pestañas 50 mm)', 2 * 5 * 50 * 50 / 6 / tr),
          ('Peldaño chapa lagrimada 6 mm plegada + L 40x4 central', 2 * 6 * 60 * 60 / 6 / tr),
        ];
  var treadName = treadOpts.last.$1;
  for (final o in treadOpts) {
    final wPerM = o.$2; // mm³ por metro de huella
    final mRdUni = wPerM * tr * fy / gammaM0 / 1e6; // kN·m (todo el peldaño)
    final mRdPt = wPerM * math.min(tr, 0.2) * fy / gammaM0 / 1e6;
    final mU = (1.35 * gTread + 1.5 * q) * tr * w * w / 8;
    final mP = 1.5 * qPoint * w / 4;
    final u = math.max(mU / mRdUni, mP / mRdPt);
    treadName = o.$1;
    if (u <= _limit || o == treadOpts.last) {
      checks.add(Check(o.$1, 'Peldaño: uniforme ${_f(q, 0)} kN/m² y puntual ${_f(qPoint, 0)} kN', u,
          '${central ? 'Apoyado en ménsula a todo el ancho' : 'Vano ${_f(w, 2)} m'}, '
          'huella ${_f(tr * 100)} cm (sección resistente equivalente)'));
      break;
    }
  }

  // Zancas (dos laterales o una central de tubo, que además trabaja a torsión)
  final lh = runF + 0.3;
  final cosA = math.cos(alpha), sinA = math.sin(alpha);
  final li = lh / cosA;
  final share = central ? 1.0 : 0.5;
  final stringer = _choose(
      central
          ? [...rhsTable.where((p) => p.h >= 150), ...shsTable.where((p) => p.b >= 150)]
          : [...upnTable.where((p) => p.h >= 120), ...rhsTable.where((p) => p.h >= 120)], (p) {
    final qd = (1.35 * gTread + 1.5 * q) * w * share + 1.35 * (_self(p) / cosA + 0.15);
    final qk = (gTread + q) * w * share + _self(p) / cosA + 0.15;
    final med = qd * lh * lh / 8;
    final qPerp = qk * cosA * cosA;
    final defl = 5 * qPerp * math.pow(li * 1000, 4) / (384 * _youngE * p.iy * 1e4);
    final am = (p.h - p.tw) * (p.b - p.tw); // área media de la sección cerrada (mm²)
    final tRd = 2 * am * p.tw * fy / (math.sqrt(3) * gammaM0) / 1e6;
    final tEd = 1.5 * q * (w / 2) * (w / 4) * lh / 2;
    return [
      Check('Zanca ${p.name}', 'Flexión ELU (proyección horizontal)', med / _mRd(p, fy),
          'qd = ${_f(qd, 2)} kN/m, Lh = ${_f(lh, 2)} m, inclinación ${_f(alpha * 180 / math.pi)}°, MEd = ${_f(med, 2)} kN·m'),
      Check('Zanca ${p.name}', 'Flecha ELS ≤ L/300', defl / (li * 1000 / 300), 'δ = ${_f(defl)} mm (L = ${_f(li, 2)} m)'),
      if (central)
        Check('Zanca ${p.name}', 'Torsión con sobrecarga en medio peldaño', tEd / tRd,
            'TEd = ${_f(tEd, 2)} kN·m, TRd = ${_f(tRd, 1)} kN·m (sección cerrada)'),
    ];
  }, checks);
  final nose = angleTable.first;
  // Ménsula de peldaño en voladizo de w/2 a cada lado de la zanca central
  final bracket = central
      ? _choose([...flatTable.where((p) => p.h >= 60), ...rhsTable.where((p) => p.h <= 100)], (p) {
          final med = 1.5 * qPoint * w / 2 + (1.35 * gTread + 1.5 * q) * tr * w * w / 8 + 1.35 * _self(p) * w * w / 8;
          final defl = qPoint * 1000 * math.pow(w / 2 * 1000, 3) / (3 * _youngE * p.iy * 1e4);
          return [
            Check('Ménsula de peldaño ${p.name}', 'Voladizo ${_f(w / 2, 2)} m con ${_f(qPoint, 0)} kN en la punta', med / _mRd(p, fy),
                'MEd = ${_f(med, 2)} kN·m'),
            Check('Ménsula de peldaño ${p.name}', 'Flecha en punta ≤ L/150', defl / (w / 2 * 1000 / 150), 'δ = ${_f(defl)} mm'),
          ];
        }, checks)
      : null;

  // Geometría: cada tramo con su origen, dirección de subida (d) y sentido transversal (p).
  // Recta: tramos en línea. En L: giro de 90° en meseta cuadrada. En U: giro de 180° con ojo.
  var o = const Vec3(0, 0, 0);
  var d = const Vec3(1, 0, 0), pv = const Vec3(0, 1, 0);
  Vec3 at(double u, double v, double z) => Vec3(o.x + d.x * u + pv.x * v, o.y + d.y * u + pv.y * v, z);
  final frameX = <double>[0];
  var z = 0.0;
  final railRuns = <(Vec3, Vec3)>[];
  final railSides = w >= 1.2 ? [0.0, w] : [w];
  final lines = central ? [w / 2] : [0.0, w];
  final landingCols = <Vec3>[];
  final landings = <List<Vec3>>[];
  final joist = landW > 1.6 ? rhsTable[6] : rhsTable[4];
  final floorKind = tramex ? SurfaceKind.grating : SurfaceKind.floor;
  for (var f = 0; f < flights; f++) {
    final z0 = z, z1 = z0 + hf;
    final web = Vec3(-d.x * sinA, -d.y * sinA, cosA);
    for (final v in lines) {
      members.add(Member(role: MemberRole.stringer, profile: stringer, a: at(0, v, z0), b: at(runF, v, z1), webDir: web));
    }
    for (var k = 1; k < per; k++) {
      final zt = z0 + k * c;
      final ua = (k - 1) * tr, ub = k * tr;
      members.add(Member(role: MemberRole.tread, profile: nose, a: at(ua, 0, zt), b: at(ua, w, zt)));
      if (bracket != null) {
        final um = (ua + ub) / 2;
        members.add(Member(role: MemberRole.bracket, profile: bracket, a: at(um, 0.02, zt - 0.03), b: at(um, w - 0.02, zt - 0.03)));
      }
      surfaces.add(Surface(at(ua, 0, zt), at(ub, 0, zt), at(ub, w, zt), at(ua, w, zt), floorKind));
    }
    for (final v in railSides) {
      railRuns.add((at(0, v, z0 + c), at(runF, v, z1)));
    }
    if (f == 0) footings.addAll([for (final v in lines) at(0, v, 0)]);
    if (turn == 0) frameX.add(at(runF, 0, 0).x);
    z = z1;
    if (f == flights - 1) break;
    // Meseta
    final u0 = runF, u1 = runF + landing;
    final cs = [at(u0, 0, z), at(u1, 0, z), at(u1, landW, z), at(u0, landW, z)];
    for (final v in [0.0, landW]) {
      members.add(Member(role: MemberRole.beam, profile: stringer, a: at(u0, v, z), b: at(u1, v, z)));
    }
    for (final u in [u0, u1]) {
      members.add(Member(role: MemberRole.joist, profile: joist, a: at(u, 0, z), b: at(u, landW, z)));
    }
    landingCols.addAll(cs);
    landings.add(cs);
    surfaces.add(Surface(cs[0], cs[1], cs[2], cs[3], floorKind));
    if (turn == 0) {
      for (final v in railSides) {
        railRuns.add((at(u0, v, z), at(u1, v, z)));
      }
      frameX.add(at(u1, 0, 0).x);
      o = at(u1, 0, 0);
    } else if (turn == 90) {
      if (w >= 1.2) {
        railRuns.add((at(u0, 0, z), at(u1, 0, z)));
        railRuns.add((at(u1, 0, z), at(u1, w, z)));
      }
      final no = at(u1, w, 0), nd = pv, np = d * -1;
      o = no;
      d = nd;
      pv = np;
    } else {
      railRuns.add((at(u0, w, z), at(u0, w + gap, z))); // borde del ojo
      if (w >= 1.2) {
        railRuns.add((at(u0, 0, z), at(u1, 0, z)));
        railRuns.add((at(u1, 0, z), at(u1, landW, z)));
        railRuns.add((at(u1, landW, z), at(u0, landW, z)));
      }
      o = at(u0, landW, 0);
      d = d * -1;
      pv = pv * -1;
    }
  }
  final runs = <(Vec3, Vec3)>[];
  for (final r in railRuns) {
    if (!runs.any((o) => (o.$1 - r.$1).length < 1e-6 && (o.$2 - r.$2).length < 1e-6)) runs.add(r);
  }

  SteelProfile? column;
  if (landingCols.isNotEmpty) {
    final zl = landingCols.map((p) => p.z).reduce(math.max);
    final nEd = (1.35 * gTread + 1.5 * q) * (landing * landW + runF * w) / 4 + 2;
    column = _columnFor([...shsTable.where((p) => p.b >= 60), ...hebTable], 'Pilar de meseta', nEd, 0, zl, fy, checks);
    final brace = _tieFor('Cruz de meseta', 0.02 * nEd * 4 * landing / zl + 1, fy, checks);
    for (final p in landingCols) {
      members.add(Member(role: MemberRole.column, profile: column, a: Vec3(p.x, p.y, 0), b: Vec3(p.x, p.y, p.z - stringer.h / 1000)));
      footings.add(Vec3(p.x, p.y, 0));
    }
    for (final cs in landings) {
      final zc = cs.first.z;
      for (final (a, b) in [(cs[0], cs[1]), (cs[3], cs[2])]) {
        _cross(members, brace, Vec3(a.x, a.y, 0.2), Vec3(a.x, a.y, zc - 0.2), Vec3(b.x, b.y, 0.2), Vec3(b.x, b.y, zc - 0.2));
      }
    }
  }

  final hr = hTot > 6 ? 1.1 : 0.9;
  final rail = _railing(members, checks, runs, hr, fy, lineLoad: q >= 4 ? 1.6 : 0.8, spacing: 1.2,
      tubular: _tubularRailing(s, normalize(prompt)), doubleRail: _doubleHandrail(normalize(prompt)));

  final nTreads = (per - 1) * flights;
  final nl = lines.length;
  final pa = _basePlate(stringer, (1.35 * gTread + 1.5 * q) * lh * w * share / 2, 0, fy, checks, 'PA1', bolts: 2, minW: 160);
  final plates = <PlatePiece>[
    PlatePiece(mark: 'PA1', description: 'Placa de apoyo inferior de zanca', w: pa.w, h: 160, t: pa.t, qty: nl,
        notes: '2 anclajes químicos ${pa.anchor}'),
    PlatePiece(mark: 'PT1', description: 'Chapa de cuelgue superior de zanca (a forjado/viga)', w: 200, h: _roundUp(stringer.h + 80, 10),
        t: 10, qty: nl, notes: '4 anclajes químicos M12 o 4 M12 8.8 a viga'),
    PlatePiece(mark: 'PE', description: treadName, w: w * 1000 - 10, h: tr * 1000 + 30, t: tramex ? 3 : (treadName.contains('6 mm') ? 6 : (treadName.contains('5 mm') ? 5 : 4)),
        qty: nTreads, notes: tramex ? 'Galvanizado, con pisante antideslizante y cantoneras laterales' : 'Plegado en U, antideslizante'),
    if (landingCols.isNotEmpty)
      PlatePiece(mark: 'PA2', description: 'Placa base pilar de meseta ${column!.name}', w: 200, h: 200, t: 10,
          qty: landingCols.length, notes: '4 anclajes químicos M12'),
    if (landingCols.isNotEmpty)
      PlatePiece(mark: 'ME', description: 'Suelo de meseta (${tramex ? 'tramex 30x30' : 'chapa lagrimada 5 mm'})', w: landing * 1000, h: landW * 1000,
          t: tramex ? 3 : 5, qty: flights - 1),
  ];
  final bolts = <BoltItem>[
    BoltItem('Anclaje inferior de zancas', '${pa.anchor} varilla 8.8 + resina epoxi', 2 * nl, 'PA1 sobre solera'),
    BoltItem('Cuelgue superior', 'M12 anclaje químico / tornillo 8.8', 4 * nl, 'PT1'),
    BoltItem('Fijación de peldaños', tramex ? 'M10 x 30 8.8 + tuerca autoblocante' : 'Soldado (sin tornillería)', tramex ? nTreads * 4 : 0, 'Peldaño – zanca'),
    if (landingCols.isNotEmpty) BoltItem('Anclaje pilares de meseta', 'M12 varilla 8.8 + resina', landingCols.length * 4, 'PA2'),
  ];
  final welds = <WeldSpec>[
    WeldSpec(joint: 'Zanca – placas PA1 / PT1', type: 'En ángulo perimetral', throat: weldThroat(stringer.tMin, pa.t, g),
        lengthPerJoint: 2 * (stringer.h + stringer.b), count: 2 * nl),
    if (central)
      WeldSpec(joint: 'Ménsula de peldaño – zanca central', type: 'En ángulo por ambos lados', throat: 5,
          lengthPerJoint: 2 * stringer.b, count: nTreads),
    WeldSpec(joint: tramex ? 'Casquillo de peldaño – zanca' : 'Peldaño / soporte L – zanca', type: 'En ángulo', throat: 3,
        lengthPerJoint: tramex ? 2 * 50 : 2 * (tr * 1000 * 0.6), count: nTreads * (central ? 1 : 2)),
    if (landingCols.isNotEmpty)
      WeldSpec(joint: 'Pilar de meseta – placa base', type: 'En ángulo perimetral', throat: weldThroat(column!.tMin, 10, g),
          lengthPerJoint: 4 * column.b, count: landingCols.length),
    _railWeld(rail),
  ];
  final formText = switch (form) {
    'en l' => 'Escalera en L (dos tramos a 90° con meseta cuadrada en la esquina)',
    'en u' => 'Escalera en U (ida y vuelta con meseta de giro y ojo de ${_f(gap * 100, 0)} cm)',
    'zanca central' => 'Escalera de zanca central (una zanca de tubo con los peldaños en voladizo)',
    _ => 'Escalera recta',
  };
  final hyp = [
    ..._commonHypotheses(s),
    '$formText de ${_f(hTot, 2)} m de altura y ${_f(w, 2)} m de ancho: $n peldaños de ${_f(c * 100)} cm de contrahuella y ${_f(tr * 100)} cm de huella (CTE DB-SUA 1 §4.2.1).',
    if (flights > 1)
      '$flights tramos con meseta${turn > 0 ? ' de giro' : ' intermedia'} de ${_f(landing, 2)} x ${_f(landW, 2)} m apoyada en ${landingCols.length} pilares.',
    'Sobrecarga de uso ${_f(q, 0)} kN/m² (${s.use}) y carga puntual de ${_f(qPoint, 0)} kN en peldaño (DB-SE-AE tabla 3.1). Peso de peldaños ${_f(gTread, 2)} kN/m².',
    if (central)
      'Zanca central ${stringer.name} comprobada a flexión, flecha y torsión con la sobrecarga en medio peldaño; ménsulas ${bracket!.name} soldadas encima.'
    else
      'Zancas biapoyadas: apoyo inferior en solera y cuelgue superior en forjado o viga existente (comprobar su capacidad).',
    'Barandilla de ${_f(hr, 2)} m${w >= 1.2 ? ' a ambos lados' : ' en el lado libre'} medida desde la línea de peldaños; pasamanos continuo (DB-SUA 1 §4.2.4).',
    if (w < 1.2) turn > 0 ? 'Se supone el lado exterior de la escalera junto a muro; si está libre, añadir la misma barandilla.' : 'Se supone el lado y = 0 junto a muro; si está libre, añadir la misma barandilla.',
  ];
  final assembly = [
    'Replanteo del arranque y del desembarco; comprobar la altura real entre acabados${turn > 0 ? ' y el hueco disponible en planta' : ''}.',
    'Fabricación en taller de ${central ? 'la zanca central con las ménsulas de peldaño soldadas' : 'las zancas con casquillos de peldaño soldados'}${tramex ? ' y taladros para tramex' : ''}.',
    if (flights > 1) 'Montaje de los pilares y la meseta, aplomado y arriostrado.',
    'Presentación de zancas: anclaje inferior (PA1) y cuelgue superior (PT1).',
    'Colocación y fijación de peldaños de abajo hacia arriba.',
    'Montaje de barandilla por tramos; repaso de soldaduras y acabado (${s.finish}).',
  ];
  warnings.add(_warnValidate());
  if (s.variant.contains('exterior')) warnings.add('Escalera exterior: galvanizado en caliente recomendado y peldaños antideslizantes con drenaje.');
  if (central && w > 1.2) warnings.add('Con zanca central y más de 1,20 m de ancho el voladizo del peldaño es grande: valora dos zancas.');
  final xs = [for (final m in members) ...[m.a.x, m.b.x]];
  final ys = [for (final m in members) ...[m.a.y, m.b.y]];
  final x0 = xs.reduce(math.min), x1 = xs.reduce(math.max);
  final y0 = ys.reduce(math.min), y1 = ys.reduce(math.max);
  return Design(
    spec: s..length = x1 - x0,
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
    footingSize: 0,
    frameX: turn == 0 ? frameX : [x0, x1],
    gridY: turn == 0 ? [0, w] : [y0, y1],
    ridgeHeight: hTot,
    surfaces: surfaces,
  );
}

// ---------------------------------------------------------------------------
// PASARELA
// ---------------------------------------------------------------------------

Design _designPasarela(StructureSpec s, String prompt) {
  final g = s.grade, fy = g.fy;
  final lx = s.length, w = s.width, hgt = s.height, q = s.liveLoad;
  final checks = <Check>[];
  final warnings = <String>[...s.notes];
  final t = normalize(prompt);
  final single = RegExp(r'puente|sin apoyos intermedios|salvar|vano unico|luz libre').hasMatch(t);
  final nb = s.bay != null ? math.max(1, (lx / s.bay!).round()) : (single ? 1 : math.max(1, (lx / 6.0).ceil()));
  final sx = lx / nb;
  final frameX = List.generate(nb + 1, (i) => i * sx);
  final tramex = s.roofing.contains('tramex');
  final gDeck = tramex ? 0.35 : 0.45;
  if (single && lx > 15) warnings.add('Vano único de ${_f(lx)} m: requiere viga armada o celosía; revisar vibraciones (frecuencia > 5 Hz).');

  final nj = math.max(1, (lx / 1.0).ceil());
  final e = lx / nj;
  final joist = _beamFor([...rhsTable, ...upnTable], 'Travesaño', 1.35 * gDeck * e + 1.5 * q * e, (gDeck + q) * e, w, fy, checks);
  final trib = w / 2;
  final beam = _beamFor([...upnTable, ...ipeTable, ...hebTable], 'Viga principal',
      1.35 * (gDeck * trib + 0.25 + _self(joist) * trib / e) + 1.5 * q * trib, (gDeck + q) * trib + 0.25, sx, fy, checks,
      defl: 350);
  final rBeam = (1.35 * (gDeck * trib + 0.25) + 1.5 * q * trib) * sx;
  final column = _columnFor([...shsTable.where((p) => p.b >= 80), ...hebTable], 'Pilar', rBeam * (nb > 1 ? 1 : 0.5) + 2, 0, hgt, fy, checks);
  final brace = _tieFor('Arriostramiento', 0.015 * rBeam * nb + 1.5 * s.wind * 1.0 * lx * 1.5 / 2, fy, checks);

  final members = <Member>[];
  final footings = <Vec3>[];
  final zt = hgt;
  for (final x in frameX) {
    for (final y in [0.0, w]) {
      members.add(Member(role: MemberRole.column, profile: column, a: Vec3(x, y, 0), b: Vec3(x, y, zt - beam.h / 1000), webDir: const Vec3(1, 0, 0)));
      footings.add(Vec3(x, y, 0));
    }
    _cross(members, brace, Vec3(x, 0, 0.2), Vec3(x, 0, zt - 0.25), Vec3(x, w, 0.2), Vec3(x, w, zt - 0.25));
  }
  for (final y in [0.0, w]) {
    for (var i = 0; i < nb; i++) {
      members.add(Member(role: MemberRole.beam, profile: beam, a: Vec3(frameX[i], y, zt - beam.h / 2000), b: Vec3(frameX[i + 1], y, zt - beam.h / 2000)));
    }
    _cross(members, brace, Vec3(0, y, 0.2), Vec3(0, y, zt - 0.25), Vec3(frameX[1], y, 0.2), Vec3(frameX[1], y, zt - 0.25));
    if (nb > 2) {
      _cross(members, brace, Vec3(frameX[nb - 1], y, 0.2), Vec3(frameX[nb - 1], y, zt - 0.25), Vec3(lx, y, 0.2), Vec3(lx, y, zt - 0.25));
    }
  }
  for (var k = 0; k <= nj; k++) {
    members.add(Member(role: MemberRole.joist, profile: joist, a: Vec3(k * e, 0, zt - joist.h / 2000), b: Vec3(k * e, w, zt - joist.h / 2000)));
  }
  final industrial = s.variant != 'peatonal pública';
  final hr = (industrial || hgt > 6) ? 1.1 : 0.9;
  final rail = _railing(members, checks, [(Vec3(0, 0, zt), Vec3(lx, 0, zt)), (Vec3(0, w, zt), Vec3(lx, w, zt))], hr, fy,
      lineLoad: q >= 5 ? 1.6 : 0.8, tubular: _tubularRailing(s, t), doubleRail: _doubleHandrail(t));
  final nCols = frameX.length * 2;
  final pa = _basePlate(column, rBeam, 0, fy, checks, 'PA1');
  final plates = <PlatePiece>[
    PlatePiece(mark: 'PA1', description: 'Placa base pilar ${column.name}', w: pa.w, h: pa.w, t: pa.t, qty: nCols, notes: '4 anclajes ${pa.anchor}'),
    PlatePiece(mark: 'PC1', description: 'Placa de cabeza de pilar', w: _roundUp(beam.b + 40, 10), h: _roundUp(column.b + 60, 10), t: 12, qty: nCols),
    PlatePiece(mark: 'CS1', description: 'Casquillo travesaño-viga', w: _roundUp(joist.h * 0.8, 10), h: 80, t: 8, qty: (nj + 1) * 2),
    PlatePiece(mark: 'GU1', description: 'Cartela de arriostramiento', w: 160, h: 160, t: 8, qty: members.where((m) => m.role == MemberRole.brace).length * 2),
    PlatePiece(mark: 'SU', description: tramex ? 'Suelo tramex 30x30x30x2 galvanizado' : 'Chapa lagrimada 5 mm', w: 1000, h: w * 1000, t: 3, qty: lx.ceil()),
  ];
  final bolts = <BoltItem>[
    BoltItem('Anclaje de pilares', '${pa.anchor} varilla 8.8 + resina epoxi', nCols * 4, 'PA1'),
    BoltItem('Viga-pilar', 'M16 x 45 8.8', nCols * 4, 'PC1'),
    BoltItem('Travesaño-viga', 'M12 x 35 8.8', (nj + 1) * 4, 'CS1'),
    BoltItem('Fijación de suelo', tramex ? 'Grapa de tramex M8' : 'Tornillo autotaladrante', (lx * w * 4).ceil(), 'Suelo'),
  ];
  final welds = <WeldSpec>[
    WeldSpec(joint: 'Pilar – placas PA1 / PC1', type: 'En ángulo perimetral', throat: weldThroat(column.tMin, pa.t, g),
        lengthPerJoint: column.isHollow ? 4 * column.b : 2 * (2 * column.b + column.h), count: nCols * 2),
    WeldSpec(joint: 'Casquillo CS1 – viga', type: 'En ángulo doble cordón', throat: weldThroat(math.min(beam.tw, 8), 8, g),
        lengthPerJoint: 2 * joist.h * 0.8, count: (nj + 1) * 2),
    _railWeld(rail),
  ];
  final hyp = [
    ..._commonHypotheses(s),
    'Pasarela de ${_f(lx, 2)} m x ${_f(w, 2)} m a ${_f(hgt, 2)} m: $nb vano(s) de ${_f(sx, 2)} m, travesaños cada ${_f(e, 2)} m.',
    'Uso: ${s.use}, q = ${_f(q, 0)} kN/m². Suelo ${s.roofing} (${_f(gDeck, 2)} kN/m²). Flecha de vigas ≤ L/350.',
    'Pilares biarticulados con cruces transversales en cada apoyo y longitudinales en los vanos extremos.',
    'Barandilla a ambos lados de ${_f(hr, 2)} m con rodapié de 0,10 m${industrial ? ' (EN ISO 14122-3)' : ' (CTE DB-SUA 1)'}.',
  ];
  final assembly = [
    'Replanteo de apoyos y ejecución de dados de hormigón / anclajes.',
    'Montaje de pórticos transversales (pilares + cruces) y aplomado.',
    'Izado de vigas principales por vanos y atornillado a placas PC1.',
    'Montaje de travesaños y suelo; fijación con grapas.',
    'Barandillas por tramos y repaso de acabado (${s.finish}).',
  ];
  warnings.add(_warnValidate());
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
    footingSize: 0.6,
    frameX: frameX,
    gridY: [0, w],
    ridgeHeight: hgt,
    surfaces: [Surface(Vec3(0, 0, zt + 0.01), Vec3(lx, 0, zt + 0.01), Vec3(lx, w, zt + 0.01), Vec3(0, w, zt + 0.01),
        tramex ? SurfaceKind.grating : SurfaceKind.floor)],
  );
}

// ---------------------------------------------------------------------------
// BARANDILLA
// ---------------------------------------------------------------------------

Design _designBarandilla(StructureSpec s, String prompt) {
  final t = normalize(prompt);
  final form = railForms.firstWhere((f) => s.variant.startsWith(f), orElse: () => t.contains('vidrio') ? 'vidrio' : 'barrotes');
  if (form == 'pasamanos a pared') return _designPasamanosPared(s, prompt);
  final toe = s.variant.contains('rodapié');
  final g = s.grade, fy = g.fy;
  final lx = s.length, hr = s.height, ql = s.liveLoad;
  final checks = <Check>[];
  final warnings = <String>[...s.notes];
  final members = <Member>[];
  final surfaces = <Surface>[];
  // Separación de montantes: la mayor (≤ 1,5 m) con montante de hasta SHS 60x4
  final tubular = _tubularRailing(s, t);
  final double2 = _doubleHandrail(t);
  final maxPost = tubular ? chsTable.firstWhere((p) => p.h >= 60) : shsTable.firstWhere((p) => p.name == 'SHS 60x4');
  var spacing = form == 'vidrio' ? 1.2 : 1.5;
  while (spacing > 0.8) {
    final med = 1.5 * ql * spacing * hr;
    if (med / _mRd(maxPost, fy) <= _limit) break;
    spacing -= 0.1;
  }
  final lamas = form == 'lamas';
  final rail = _railing(members, checks, [(const Vec3(0, 0, 0), Vec3(lx, 0, 0))], hr, fy,
      lineLoad: ql, spacing: spacing, bars: form == 'barrotes' || lamas,
      baluster: lamas ? _flatNamed('Pletina 40x8') : null, barStep: lamas ? 0.10 : 0.11,
      tubular: tubular, doubleRail: double2);
  final post = rail.post;
  final postXs = [for (final m in members.where((m) => m.role == MemberRole.post)) m.a.x]..sort();
  // Relleno entre montantes
  var nFill = 0;
  String fillText;
  switch (form) {
    case 'vidrio':
      for (var i = 0; i < postXs.length - 1; i++) {
        surfaces.add(Surface(Vec3(postXs[i] + 0.04, 0, 0.12), Vec3(postXs[i + 1] - 0.04, 0, 0.12), Vec3(postXs[i + 1] - 0.04, 0, hr - 0.06),
            Vec3(postXs[i] + 0.04, 0, hr - 0.06), SurfaceKind.glass));
      }
      fillText = 'vidrio laminado 6+6 (o 8+8) con butiral, sujeto con pinzas al montante';
      break;
    case 'cables':
    case 'barras horizontales':
      final cable = form == 'cables';
      final step = cable ? 0.08 : 0.10;
      final n = ((hr - 0.25) / step).floor();
      for (var k = 1; k <= n; k++) {
        final z = 0.1 + k * step;
        members.add(Member(role: MemberRole.rail, profile: cable ? _cable6 : roundTable.first, a: Vec3(0, 0, z), b: Vec3(lx, 0, z)));
        nFill++;
      }
      fillText = cable
          ? '$n cables inox Ø6 cada ${_f(step * 100, 0)} cm, con tensores en los extremos'
          : '$n barras horizontales ${roundTable.first.name} cada ${_f(step * 100, 0)} cm';
      if (cable) {
        // montantes de extremo: tiro de los cables tensados (≈ 0,5 kN por cable)
        final mEnd = 1.5 * 0.5 * n * (0.1 + (n + 1) * step / 2);
        final endPost = _choose(shsTable.where((p) => p.b >= post.b).toList(), (p) => [
              Check('Montante de extremo ${p.name}', 'Tiro de $n cables tensados (0,5 kN c/u)', mEnd / _mRd(p, fy),
                  'MEd = ${_f(mEnd, 2)} kN·m en la base'),
            ], checks);
        for (final x in [postXs.first, postXs.last]) {
          final i = members.indexWhere((m) => m.role == MemberRole.post && (m.a.x - x).abs() < 1e-6);
          if (i >= 0) members[i] = Member(role: MemberRole.post, profile: endPost, a: members[i].a, b: members[i].b);
        }
      }
      warnings.add('Relleno horizontal escalable: el CTE DB-SUA 1 §3.2.3 no lo admite donde pueda haber niños (vivienda, uso público, docente). '
          'Ahí usa barrotes verticales, vidrio o chapa perforada.');
      break;
    case 'chapa perforada':
      for (var i = 0; i < postXs.length - 1; i++) {
        surfaces.add(Surface(Vec3(postXs[i] + 0.03, 0, 0.12), Vec3(postXs[i + 1] - 0.03, 0, 0.12), Vec3(postXs[i + 1] - 0.03, 0, hr - 0.05),
            Vec3(postXs[i] + 0.03, 0, hr - 0.05), SurfaceKind.mesh));
      }
      fillText = 'chapa perforada de 2 mm (agujero ≤ 10 mm, no escalable) atornillada a marco de pletina';
      break;
    case 'lamas':
      fillText = 'lamas verticales de pletina 40x8 con hueco ≤ 10 cm';
      break;
    default:
      fillText = tubular
          ? 'barrotes verticales de redondo macizo con hueco libre ≤ 10 cm'
          : 'barrotes verticales con hueco libre ≤ 10 cm';
  }
  if (toe) {
    members.add(Member(role: MemberRole.rail, profile: _toePlate, a: const Vec3(0, 0, 0.06), b: Vec3(lx, 0, 0.06), webDir: const Vec3(0, 0, 1)));
  }
  final mBase = 1.5 * ql * spacing * hr;
  final lateral = RegExp(r'lateral|canto|frente de forjado').hasMatch(t);
  final pa = _basePlate(post, 0.5, mBase, fy, checks, 'PA1', minW: lateral ? 100 : 120);
  final handrail = members.firstWhere((m) => m.role == MemberRole.handrail).profile;
  checks.add(Check('Pasamanos ${handrail.name}', 'Flexión entre montantes (continuo)',
      1.5 * ql * spacing * spacing / 10 / _mRd(handrail, fy), 'MEd = ${_f(1.5 * ql * spacing * spacing / 10, 2)} kN·m'));
  if (form == 'vidrio') {
    checks.add(Check('Vidrio laminado 6+6', 'Empuje ${_f(ql, 1)} kN/m repartido al vidrio entre montantes', ql * spacing * hr / 6 / 2.5,
        'Orientativo: comprobar con el fabricante (UNE-EN 12600, clase 2B2 mínimo)'));
  }
  final footings = [for (final m in members.where((m) => m.role == MemberRole.post)) m.a];
  final nPanels = postXs.length - 1;
  final plates = <PlatePiece>[
    PlatePiece(mark: 'PA1', description: lateral ? 'Pletina de anclaje lateral (al canto del forjado)' : 'Placa de anclaje de montante',
        w: pa.w, h: lateral ? 200 : pa.w, t: pa.t, qty: rail.posts, notes: '${lateral ? 2 : 4} anclajes químicos ${pa.anchor}'),
    if (form == 'chapa perforada')
      PlatePiece(mark: 'CP', description: 'Chapa perforada 2 mm R10 T15 (paño)', w: spacing * 1000 - 60, h: (hr - 0.17) * 1000, t: 2, qty: nPanels,
          notes: 'Atornillada a pletinas soldadas a los montantes'),
  ];
  final bolts = <BoltItem>[
    BoltItem('Anclaje de montantes', '${pa.anchor} varilla 8.8 + resina epoxi', rail.posts * (lateral ? 2 : 4), 'PA1'),
    BoltItem('Tapones de tubo', 'Tapón de PVC / soldado', rail.posts + 2, 'Montantes y extremos'),
    if (form == 'vidrio')
      BoltItem('Vidrio laminado 6+6 butiral, ${_f(spacing - 0.08, 2)} x ${_f(hr - 0.18, 2)} m', 'Cantos pulidos (no es acero: aparte del peso)', nPanels, 'Paños entre montantes'),
    if (form == 'vidrio') BoltItem('Pinzas de vidrio', 'Pinza inox AISI 316 para vidrio 12,76 mm', nPanels * 4, 'Vidrio – montante'),
    if (form == 'cables') BoltItem('Tensores de cable', 'Terminal roscado + tensor inox M8', nFill * 2, 'Montantes de extremo'),
    if (form == 'chapa perforada') BoltItem('Tornillería de paños', 'M6 inox avellanado', nPanels * 8, 'Chapa – marco'),
  ];
  final welds = <WeldSpec>[
    WeldSpec(joint: 'Montante – placa PA1', type: 'En ángulo perimetral', throat: weldThroat(post.tMin, pa.t, g),
        lengthPerJoint: post.family == ProfileFamily.chs ? (math.pi * post.h).roundToDouble() : 4 * post.b, count: rail.posts),
    _railWeld(rail),
    if (double2) WeldSpec(joint: 'Soportes del segundo pasamanos', type: 'En ángulo perimetral', throat: 3, lengthPerJoint: 50, count: rail.posts * 2),
    if (toe) WeldSpec(joint: 'Rodapié – montantes', type: 'En ángulo', throat: 3, lengthPerJoint: 2 * 100, count: rail.posts),
  ];
  final hyp = [
    ..._commonHypotheses(s),
    'Barandilla de ${_f(lx, 2)} m y ${_f(hr, 2)} m de altura (CTE DB-SUA 1 §3.2: 0,90 m si la caída ≤ 6 m; 1,10 m si es mayor).',
    'Empuje horizontal ${_f(ql, 1)} kN/m en el pasamanos (${s.use}, DB-SE-AE 3.2.1). Montantes cada ${_f(spacing, 2)} m.',
    'Relleno: $fillText.',
    if (tubular) 'Montantes, pasamanos y larguero de tubo redondo ${post.name} (barandilla tubular${s.grade.kind == MaterialKind.stainless ? ' de inox' : ''}).',
    if (double2) 'Doble pasamanos: el de coronación a ${_f(hr, 2)} m y otro a 0,70 m sobre soportes por la cara interior (CTE DB-SUA 1 §4.2.4: 90–110 cm y 65–75 cm).',
    if (form == 'barrotes' || lamas) 'Sin elementos escalables entre 30 y 50 cm de altura.',
    if (form == 'vidrio') 'Vidrio no calculado en detalle: seguir UNE-EN 12600 / CTE DB-SUA 2 con perfil de pinza homologado.',
    if (toe) 'Rodapié de pletina 100x5 a ras de suelo (EN ISO 14122-3 en zonas industriales; evita la caída de objetos).',
    'Anclaje ${lateral ? 'lateral al canto del forjado' : 'sobre losa'}: el soporte debe ser hormigón sano de ≥ 15 cm.',
  ];
  final assembly = [
    'Replanteo de montantes cada ${_f(spacing, 2)} m.',
    'Fabricación por tramos de ≤ 3 m en taller (montantes, pasamanos, larguero${form == 'barrotes' || lamas ? ' y barrotes' : ''}${toe ? ', rodapié' : ''}).',
    'Taladro, limpieza y anclaje químico de placas; aplomado.',
    if (double2) 'Soldar los soportes del segundo pasamanos a 0,70 m y montar el pasamanos con remates curvos en los extremos.',
    if (form == 'vidrio') 'Colocación de pinzas y vidrios con calzos de neopreno; sellado.',
    if (form == 'cables') 'Pasar y tensar los cables desde los montantes de extremo; repaso de tensión a las 48 h.',
    if (form == 'chapa perforada') 'Atornillado de los paños de chapa perforada.',
    'Unión entre tramos y remates; acabado (${s.finish}).',
  ];
  warnings.add(_warnValidate());
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
    footingSize: 0,
    frameX: [0, lx],
    gridY: const [0, 0.15],
    ridgeHeight: hr,
    surfaces: surfaces,
  );
}

// ---------------------------------------------------------------------------
// CUBIERTA DE CERCHAS
// ---------------------------------------------------------------------------

Design _designCercha(StructureSpec s, String prompt) {
  final g = s.grade, fy = g.fy;
  final lx = s.length, span = s.width, hgt = s.height;
  final checks = <Check>[];
  final warnings = <String>[...s.notes];
  final onCols = s.variant.contains('pilares');
  final flat = s.variant.contains('paralelos');
  final nb = s.bay != null ? math.max(1, (lx / s.bay!).round()) : math.max(1, (lx / 5.0).ceil());
  final bay = lx / nb;
  final frameX = List.generate(nb + 1, (i) => i * bay);
  var nP = (span / 1.5).round();
  if (nP.isOdd) nP++;
  nP = math.max(4, nP);
  final pl = span / nP;
  // Canto
  double rise;
  if (flat) {
    rise = math.max(span / 12, 0.5);
  } else {
    rise = span / 2 * s.slopePct / 100;
    if (rise < span / 10) {
      warnings.add('Pendiente baja para cercha triangular: se adopta un canto de L/10 = ${_f(span / 10, 2)} m.');
      rise = span / 10;
    }
  }
  final roofW = _roofingWeight(s.roofing);
  final gk = roofW + 0.08 + 0.12; // cubierta + correas + cercha
  final sn = s.snow * 0.8;
  final qd = (1.35 * gk + 1.5 * sn + 0.9 * s.wind * 0.2) * bay; // kN/m sobre la cercha
  final r = qd * span / 2;
  final slopeLen = flat ? pl : pl / math.cos(math.atan(rise / (span / 2)));
  // Esfuerzos
  final nTop = flat ? qd * span * span / (8 * rise) : r / math.sin(math.atan(2 * rise / span));
  final nBot = flat ? nTop : r / math.tan(math.atan(2 * rise / span));
  final vDiag = flat ? r : r * 0.6;
  final hDiagMin = flat ? rise : rise * 2 / nP;
  final dLen = math.sqrt(pl * pl + math.pow(flat ? rise : rise * 0.5, 2));
  final sinD = (flat ? rise : rise * 0.5) / dLen;
  // Succión de viento: compresión del cordón inferior
  final up = 1.5 * s.wind * _ce(hgt + rise) * 0.8 * bay - 0.8 * gk * bay;
  final nBotC = up > 0 ? (flat ? up * span * span / (8 * rise) : up * span / 2 / math.tan(math.atan(2 * rise / span))) : 0.0;

  final chords = shsTable.where((p) => p.b >= 50).toList();
  final top = _columnFor(chords, 'Cordón superior', nTop, 0, slopeLen, fy, checks);
  final bot = _choose(chords, (p) {
    final lb = _lambdaBar(2 * pl * 1000, math.min(p.ry, p.rz), fy);
    final nbRd = _chi(lb, _alphaWeak(p)) * p.area * fy / gammaM1 / 10;
    return [
      Check('Cordón inferior ${p.name}', 'Tracción', nBot / _nPl(p, fy), 'NEd = ${_f(nBot)} kN'),
      if (nBotC > 0) Check('Cordón inferior ${p.name}', 'Compresión por succión (Lk = 2 paneles)', nBotC / nbRd, 'NEd = ${_f(nBotC)} kN'),
    ];
  }, checks);
  final diag = _tieFor('Diagonal', vDiag / sinD, fy, checks, cands: shsTable.where((p) => p.b >= 40).toList());
  final strut = _columnFor(shsTable.where((p) => p.b >= 40).toList(), 'Montante', vDiag, 0, math.max(hDiagMin, rise * 0.8), fy, checks);
  // Flecha (inercia equivalente de los cordones, −20 % por deformación de alma)
  final hEff = flat ? rise : rise * 0.55;
  final iEff = 0.8 * (top.area * bot.area / (top.area + bot.area)) * math.pow(hEff * 100, 2); // cm⁴
  final qk = (gk + sn) * bay;
  final defl = 5 * qk * math.pow(span * 1000, 4) / (384 * _youngE * iEff * 1e4);
  checks.add(Check('Cercha', 'Flecha ELS ≤ L/300', defl / (span * 1000 / 300), 'δ ≈ ${_f(defl)} mm, canto ${_f(rise, 2)} m'));
  // Correas en los nudos del cordón superior
  final purlin = _beamFor([...rhsTable, ...ipeTable], 'Correa', (1.35 * (roofW + 0.05) + 1.5 * sn) * slopeLen,
      (roofW + 0.05 + sn) * slopeLen, bay, fy, checks, defl: 250);

  final members = <Member>[];
  final footings = <Vec3>[];
  double zTop(double y) => flat ? hgt + rise : hgt + (y <= span / 2 ? y : span - y) * 2 * rise / span;
  double zBot(double y) => hgt;
  for (final x in frameX) {
    for (var i = 0; i < nP; i++) {
      final y0 = i * pl, y1 = (i + 1) * pl;
      members.add(Member(role: MemberRole.chordBottom, profile: bot, a: Vec3(x, y0, zBot(y0)), b: Vec3(x, y1, zBot(y1))));
      members.add(Member(role: MemberRole.chordTop, profile: top, a: Vec3(x, y0, zTop(y0)), b: Vec3(x, y1, zTop(y1))));
    }
    if (flat) {
      members.add(Member(role: MemberRole.strut, profile: strut, a: Vec3(x, 0, hgt), b: Vec3(x, 0, hgt + rise)));
      members.add(Member(role: MemberRole.strut, profile: strut, a: Vec3(x, span, hgt), b: Vec3(x, span, hgt + rise)));
    }
    for (var i = 1; i < nP; i++) {
      final y = i * pl;
      members.add(Member(role: MemberRole.strut, profile: strut, a: Vec3(x, y, hgt), b: Vec3(x, y, zTop(y))));
    }
    // Diagonales Pratt (traccionadas hacia el centro)
    for (var i = 0; i < nP; i++) {
      final yA = i * pl, yB = (i + 1) * pl;
      if (i < nP / 2) {
        if (!flat && i == 0) continue;
        members.add(Member(role: MemberRole.diagonal, profile: diag, a: Vec3(x, yA, zTop(yA)), b: Vec3(x, yB, hgt)));
      } else {
        if (!flat && i == nP - 1) continue;
        members.add(Member(role: MemberRole.diagonal, profile: diag, a: Vec3(x, yA, hgt), b: Vec3(x, yB, zTop(yB))));
      }
    }
  }
  // Correas
  for (var i = 0; i <= nP; i++) {
    final y = i * pl;
    for (var k = 0; k < nb; k++) {
      final z = zTop(y) + top.h / 1000 / 2 + purlin.h / 2000;
      members.add(Member(role: MemberRole.purlin, profile: purlin, a: Vec3(frameX[k], y, z), b: Vec3(frameX[k + 1], y, z)));
    }
  }
  // Arriostramiento de cubierta en vanos extremos + atado del cordón inferior
  final windEnd = 1.5 * s.wind * _ce(hgt) * 0.8 * span * (hgt + rise) / 2;
  final brace = _tieFor('Arriostramiento de cubierta', windEnd / 2 / math.cos(math.atan(span / 2 / bay)), fy, checks);
  for (final k in {0, nb - 1}) {
    final xa = frameX[k], xb = frameX[k + 1];
    for (var i = 0; i < nP; i += 2) {
      final y0 = i * pl, y1 = math.min(span, (i + 2) * pl);
      _cross(members, brace, Vec3(xa, y0, zTop(y0)), Vec3(xa, y1, zTop(y1)), Vec3(xb, y0, zTop(y0)), Vec3(xb, y1, zTop(y1)));
    }
  }
  final tie = shsTable.firstWhere((p) => p.b >= 40);
  for (var k = 0; k < nb; k++) {
    members.add(Member(role: MemberRole.tie, profile: tie, a: Vec3(frameX[k], span / 2, hgt), b: Vec3(frameX[k + 1], span / 2, hgt)));
  }
  // Apoyos
  SteelProfile? col;
  final surfaces = <Surface>[];
  if (onCols) {
    final mCol = 1.5 * s.wind * _ce(hgt) * 0.8 * bay * hgt * hgt / 2;
    col = _columnFor([...shsTable.where((p) => p.b >= 100), ...hebTable], 'Pilar', r + 1.35 * 2, mCol, 2 * hgt, fy, checks);
    for (final x in frameX) {
      for (final y in [0.0, span]) {
        members.add(Member(role: MemberRole.column, profile: col, a: Vec3(x, y, 0), b: Vec3(x, y, hgt - 0.01), webDir: const Vec3(0, 1, 0)));
        footings.add(Vec3(x, y, 0));
      }
    }
  } else {
    for (final y in [0.0, span]) {
      surfaces.add(Surface(Vec3(-0.15, y, 0), Vec3(lx + 0.15, y, 0), Vec3(lx + 0.15, y, hgt - 0.02), Vec3(-0.15, y, hgt - 0.02), SurfaceKind.wall));
      for (final x in frameX) {
        footings.add(Vec3(x, y, 0));
      }
    }
  }
  // Cubierta (media cubierta para ver la estructura)
  if (!s.roofing.contains('sin cubierta')) {
    final xr = frameX.length > 2 ? frameX[(frameX.length / 2).floor()] : lx;
    final off = top.h / 1000 / 2 + purlin.h / 1000 + 0.02;
    final kind = s.roofing.contains('policarbonato') ? SurfaceKind.glass : SurfaceKind.roof;
    if (flat) {
      final z = hgt + rise + off;
      surfaces.add(Surface(Vec3(-0.2, -0.3, z), Vec3(xr, -0.3, z), Vec3(xr, span + 0.3, z), Vec3(-0.2, span + 0.3, z), kind));
    } else {
      final zr = hgt + rise + off;
      final ze = hgt + off - 0.3 * 2 * rise / span;
      surfaces.add(Surface(Vec3(-0.2, -0.3, ze), Vec3(xr, -0.3, ze), Vec3(xr, span / 2, zr), Vec3(-0.2, span / 2, zr), kind));
      surfaces.add(Surface(Vec3(-0.2, span / 2, zr), Vec3(xr, span / 2, zr), Vec3(xr, span + 0.3, ze), Vec3(-0.2, span + 0.3, ze), kind));
    }
  }
  final nTr = frameX.length;
  final pa = onCols ? _basePlate(col!, r, 1.5 * s.wind * _ce(hgt) * 0.8 * bay * hgt * hgt / 2, fy, checks, 'PA1') : null;
  final plates = <PlatePiece>[
    PlatePiece(mark: 'AP1', description: onCols ? 'Placa de cabeza de pilar / apoyo de cercha' : 'Placa de apoyo de cercha sobre muro (un extremo con colisos)',
        w: 200, h: 250, t: 12, qty: nTr * 2, notes: onCols ? '4 M16 8.8' : '2 anclajes químicos M16; zuncho de hormigón bajo apoyo'),
    PlatePiece(mark: 'GN', description: 'Cartela de nudo (si no se suelda directo)', w: 150, h: 150, t: 8, qty: nTr * 2),
    if (pa != null) PlatePiece(mark: 'PA1', description: 'Placa base de pilar ${col!.name}', w: pa.w, h: pa.w, t: pa.t, qty: nTr * 2, notes: '4 pernos ${pa.anchor}'),
  ];
  final bolts = <BoltItem>[
    BoltItem('Apoyo de cerchas', onCols ? 'M16 x 50 8.8' : 'M16 anclaje químico', nTr * 2 * (onCols ? 4 : 2), 'AP1'),
    BoltItem('Correa – cercha', 'M12 x 35 8.8 + ejión soldado', (nP + 1) * nTr * 2, 'Nudos superiores'),
    BoltItem('Fijación de cubierta', 'Tornillo autotaladrante 6,3 + arandela EPDM', (lx * span * 4).ceil(), 'Cubierta'),
    if (pa != null) BoltItem('Pernos de anclaje', '${pa.anchor} B500S/8.8 con tuerca y contratuerca', nTr * 2 * 4, 'PA1'),
  ];
  final nNodes = (nP * 2) * nTr;
  final welds = <WeldSpec>[
    WeldSpec(joint: 'Nudos de celosía (diagonales y montantes a cordones)', type: 'En ángulo perimetral (tubo a tubo)',
        throat: weldThroat(math.min(diag.tMin, strut.tMin), top.tMin, g), lengthPerJoint: 4 * math.max(diag.b, strut.b) * 1.2,
        count: nNodes),
    WeldSpec(joint: 'Empalme de cordones en cumbrera y apoyos', type: 'En ángulo / a tope con chapa', throat: weldThroat(top.tMin, 12, g),
        lengthPerJoint: 4 * top.b, count: nTr * 3),
    WeldSpec(joint: 'Ejiones de correa', type: 'En ángulo', throat: 4, lengthPerJoint: 2 * 80, count: (nP + 1) * nTr),
  ];
  final hyp = [
    ..._commonHypotheses(s),
    '$nTr cerchas ${flat ? 'de cordones paralelos' : 'triangulares (Pratt)'} de ${_f(span, 2)} m de luz cada ${_f(bay, 2)} m, canto ${_f(rise, 2)} m, $nP paneles de ${_f(pl, 2)} m.',
    'Cargas: cubierta ${s.roofing} + correas + peso propio = ${_f(gk, 2)} kN/m²; nieve μ·sk = ${_f(sn, 2)} kN/m²; viento qb = ${_f(s.wind, 2)} kN/m².',
    'Nudos articulados: esfuerzos axiles por equilibrio de nudos. Correas sobre nudos (sin flexión local del cordón).',
    onCols ? 'Apoyo sobre pilares empotrados en la base (ménsula) frente al viento.' : 'Apoyo sobre muros con zuncho: un extremo fijo y el otro deslizante (colisos) para dilataciones.',
    'Arriostramiento en cruz en el plano de cubierta en los vanos extremos y atado longitudinal del cordón inferior.',
  ];
  final assembly = [
    'Fabricación de cerchas en taller sobre plantilla (contraflecha L/500).',
    onCols ? 'Montaje de pilares sobre pernos, nivelación y retacado.' : 'Ejecución de zunchos y placas de apoyo AP1 nivelados.',
    'Izado de la primera cercha y arriostrado provisional; colocación de la segunda y del arriostramiento definitivo.',
    'Resto de cerchas, atado inferior y correas.',
    'Cubierta (${s.roofing}) y remates.',
  ];
  warnings.add(_warnValidate());
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
    footingSize: onCols ? 1.0 : 0,
    frameX: frameX,
    gridY: List.generate(nP + 1, (i) => i * pl),
    ridgeHeight: hgt + rise,
    surfaces: surfaces,
  );
}

// ---------------------------------------------------------------------------
// TORRE / SOPORTE DE DEPÓSITO / BANCADA
// ---------------------------------------------------------------------------

Design _designTorre(StructureSpec s, String prompt) {
  final g = s.grade, fy = g.fy;
  final a = s.length, b = s.width, hgt = s.height;
  final checks = <Check>[];
  final warnings = <String>[...s.notes];
  final tank = s.variant == 'depósito';
  final w = s.pointLoad; // kN
  final live = s.liveLoad * a * b;
  // Viento sobre depósito (cilindro de altura ≈ diámetro) y estructura
  final vol = tank ? w / 11 : 0.0; // m³
  final dTank = tank ? math.pow(4 * vol / math.pi, 1 / 3).toDouble() : 0.0;
  final fwTank = tank ? 1.5 * s.wind * _ce(hgt + dTank) * 0.8 * dTank * dTank : 0.0;
  final fwStr = 1.5 * s.wind * _ce(hgt) * 1.6 * 0.15 * hgt * 2;
  final fw = fwTank + fwStr;
  final mOver = fwTank * (hgt + dTank / 2) + fwStr * hgt / 2;
  final lev = math.max(1, (hgt / 2.5).ceil());
  final hl = hgt / lev;
  final nLeg = 1.35 * w / 4 + 1.5 * live / 4 + mOver / (2 * math.min(a, b)) + 1.0;
  final leg = _columnFor([...shsTable.where((p) => p.b >= 60), ...hebTable], 'Pata', nLeg, 0, hl, fy, checks);
  final uplift = mOver / (2 * math.min(a, b)) - 0.9 * (w * 0.1 + 2) / 4;
  final diagL = math.sqrt(a * a + hl * hl);
  final brace = _tieFor('Cruz', (fw / 2 + 0.015 * w) * diagL / a, fy, checks);
  final strut = _columnFor(shsTable.where((p) => p.b >= 50).toList(), 'Travesaño horizontal', fw / 2 + 1, 0, a, fy, checks);
  final pd = 1.35 * w / 2 + 1.5 * live / 2;
  final beam = _beamFor([...upnTable, ...ipeTable, ...hebTable], tank ? 'Viga bajo depósito' : 'Viga superior',
      pd / a, (w + live) / 2 / a, a, fy, checks);
  final members = <Member>[];
  final footings = <Vec3>[];
  final corners = [Vec3(0, 0, 0), Vec3(a, 0, 0), Vec3(a, b, 0), Vec3(0, b, 0)];
  for (final c in corners) {
    members.add(Member(role: MemberRole.column, profile: leg, a: c, b: c + Vec3(0, 0, hgt - beam.h / 1000)));
    footings.add(c);
  }
  for (var k = 1; k <= lev; k++) {
    final z = k == lev ? hgt - beam.h / 2000 : k * hl;
    final prof = k == lev ? beam : strut;
    final role = k == lev ? MemberRole.beam : MemberRole.tie;
    for (var i = 0; i < 4; i++) {
      final p = corners[i], q = corners[(i + 1) % 4];
      members.add(Member(role: role, profile: prof, a: Vec3(p.x, p.y, z), b: Vec3(q.x, q.y, z)));
    }
  }
  for (var k = 0; k < lev; k++) {
    final z0 = k * hl + 0.15, z1 = (k + 1) * hl - (k == lev - 1 ? beam.h / 1000 : 0) - 0.05;
    for (var i = 0; i < 4; i++) {
      final p = corners[i], q = corners[(i + 1) % 4];
      _cross(members, brace, Vec3(p.x, p.y, z0), Vec3(p.x, p.y, z1), Vec3(q.x, q.y, z0), Vec3(q.x, q.y, z1));
    }
  }
  // Vigas interiores bajo la carga
  final zt = hgt - beam.h / 2000;
  for (final f in [1 / 3, 2 / 3]) {
    members.add(Member(role: MemberRole.joist, profile: beam, a: Vec3(0, b * f, zt), b: Vec3(a, b * f, zt)));
  }
  final surfaces = <Surface>[];
  _Rail? rail;
  if (s.roofing.contains('tramex') || !tank) {
    surfaces.add(Surface(Vec3(0, 0, hgt + 0.01), Vec3(a, 0, hgt + 0.01), Vec3(a, b, hgt + 0.01), Vec3(0, b, hgt + 0.01),
        s.roofing.contains('tramex') ? SurfaceKind.grating : SurfaceKind.floor));
  }
  if (s.railing) {
    rail = _railing(members, checks, [
      (Vec3(0, 0, hgt), Vec3(a, 0, hgt)),
      (Vec3(a, 0, hgt), Vec3(a, b, hgt)),
      (Vec3(a, b, hgt), Vec3(0, b, hgt)),
    ], hgt > 6 ? 1.1 : 0.9, fy);
  }
  final nK = nLeg / 1.35;
  final fSize = math.max(0.6, _roundUp(math.sqrt((nK + 10) / 150), 0.1));
  final pa = _basePlate(leg, nLeg, uplift > 0 ? uplift * 0.2 : 0, fy, checks, 'PA1');
  if (uplift > 0) {
    checks.add(Check('Anclaje a vuelco', 'Tracción por pata (depósito vacío + viento)', uplift / (4 * _anchorFor(uplift / 4).$2),
        'Tracción ${_f(uplift)} kN por pata; la zapata debe pesar más que ${_f(uplift * 1.5)} kN'));
  }
  final plates = <PlatePiece>[
    PlatePiece(mark: 'PA1', description: 'Placa base de pata ${leg.name}', w: pa.w, h: pa.w, t: pa.t, qty: 4, notes: '4 pernos ${pa.anchor}'),
    PlatePiece(mark: 'GU1', description: 'Cartela de cruz', w: 160, h: 160, t: 8, qty: lev * 4 * 4),
    if (tank) PlatePiece(mark: 'TP', description: 'Chapa de reparto bajo depósito (o tablero)', w: a * 1000, h: b * 1000, t: 4, qty: 1),
  ];
  final bolts = <BoltItem>[
    BoltItem('Pernos de anclaje', '${pa.anchor} 8.8 con tuerca y contratuerca', 16, 'PA1 en zapatas'),
    BoltItem('Cruces', 'M12 x 35 8.8', lev * 4 * 4, 'GU1'),
  ];
  final welds = <WeldSpec>[
    WeldSpec(joint: 'Pata – placa base', type: 'En ángulo perimetral', throat: weldThroat(leg.tMin, pa.t, g),
        lengthPerJoint: leg.isHollow ? 4 * leg.b : 2 * (2 * leg.b + leg.h), count: 4),
    WeldSpec(joint: 'Vigas y travesaños – patas', type: 'En ángulo perimetral', throat: weldThroat(math.min(beam.tMin, strut.tMin), leg.tMin, g),
        lengthPerJoint: 2 * (beam.h + beam.b), count: lev * 4 * 2 + 4),
    WeldSpec(joint: 'Cartelas GU1 – patas', type: 'En ángulo doble cordón', throat: 4, lengthPerJoint: 2 * 160, count: lev * 4 * 4),
    if (rail != null) _railWeld(rail),
  ];
  final hyp = [
    ..._commommTorre(s, a, b, hgt, lev),
    if (tank) 'Depósito de ${_f(vol, 1)} m³ (≈ ${_f(w / 10, 1)} t con agua), Ø ≈ ${_f(dTank, 2)} m; viento sobre el depósito ${_f(fwTank / 1.5, 1)} kN (cp 0,8).',
    if (!tank && w > 0) 'Carga útil ${_f(w, 1)} kN repartida en las vigas superiores.',
    'Vuelco: momento ${_f(mOver, 1)} kN·m; ${uplift > 0 ? 'hay tracción en patas con el depósito vacío: anclajes y zapatas lastradas.' : 'sin tracción en patas.'}',
    'Patas arriostradas con cruces en las 4 caras cada ${_f(hl, 2)} m (Lk = ${_f(hl, 2)} m).',
    'Zapatas orientativas de ${_f(fSize, 1)} x ${_f(fSize, 1)} m para σadm = 150 kPa (sin estudio geotécnico).',
  ];
  final assembly = [
    'Zapatas con pernos embebidos mediante plantilla.',
    'Montaje de patas y primer nivel de travesaños; aplomado.',
    'Cruces de todas las caras y niveles superiores.',
    'Vigas superiores${tank ? ' y chapa de reparto' : ''}; ${s.railing ? 'barandilla; ' : ''}apriete final y retacado.',
    if (tank) 'Colocación del depósito vacío; llenado gradual comprobando nivelación.',
  ];
  warnings.add(_warnValidate());
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
    footingSize: fSize,
    frameX: [0, a],
    gridY: [0, b],
    ridgeHeight: hgt,
    surfaces: surfaces,
  );
}

List<String> _commommTorre(StructureSpec s, double a, double b, double h, int lev) => [
      ..._commonHypotheses(s),
      'Estructura de 4 patas en planta ${_f(a, 2)} x ${_f(b, 2)} m y ${_f(h, 2)} m de altura con $lev nivel(es) de arriostramiento.',
    ];

// ---------------------------------------------------------------------------
// ESTANTERÍA / RACK
// ---------------------------------------------------------------------------

Design _designEstanteria(StructureSpec s, String prompt) {
  final g = s.grade, fy = g.fy;
  final lx = s.length, depth = s.width, hgt = s.height;
  final checks = <Check>[];
  final warnings = <String>[...s.notes];
  final pallets = s.variant == 'palés';
  final nb = math.max(1, (lx / (pallets ? 2.8 : 1.5)).ceil());
  final bl = lx / nb;
  final levels = math.max(1, s.levels);
  final hs = hgt / levels;
  final p = s.pointLoad; // kN por nivel y vano
  final beam = _beamFor(rhsTable, 'Larguero', 1.5 * p / 2 / bl, p / 2 / bl, bl, fy, checks, defl: 200);
  final nUp = 1.5 * levels * p / 2 + 1.35 * 0.5;
  final upright = _columnFor(shsTable.where((q) => q.b >= 40).toList(), 'Puntal', nUp, 1.5 * p / 2 * 0.0, 1.5 * hs, fy, checks);
  final diag = shsTable.firstWhere((q) => q.b >= 30);
  checks.add(Check('Celosía de bastidor ${diag.name}', 'Imperfección 1/200 de la carga vertical', (nUp * 2 / 200) / (_nPl(diag, fy) * 0.5),
      'Vd ≈ ${_f(nUp * 2 / 200, 2)} kN'));
  final members = <Member>[];
  final footings = <Vec3>[];
  final surfaces = <Surface>[];
  for (var i = 0; i <= nb; i++) {
    final x = i * bl;
    for (final y in [0.0, depth]) {
      members.add(Member(role: MemberRole.column, profile: upright, a: Vec3(x, y, 0), b: Vec3(x, y, hgt), webDir: const Vec3(1, 0, 0)));
      footings.add(Vec3(x, y, 0));
    }
    // celosía del bastidor (zigzag)
    final nz = math.max(2, (hgt / 1.0).round());
    final dz = hgt / nz;
    members.add(Member(role: MemberRole.strut, profile: diag, a: Vec3(x, 0, 0.1), b: Vec3(x, depth, 0.1)));
    for (var k = 0; k < nz; k++) {
      final y0 = k.isEven ? 0.0 : depth, y1 = k.isEven ? depth : 0.0;
      members.add(Member(role: MemberRole.diagonal, profile: diag, a: Vec3(x, y0, k * dz + 0.1), b: Vec3(x, y1, (k + 1) * dz)));
    }
    members.add(Member(role: MemberRole.strut, profile: diag, a: Vec3(x, 0, hgt - 0.05), b: Vec3(x, depth, hgt - 0.05)));
  }
  for (var k = 1; k <= levels; k++) {
    final z = k * hs - beam.h / 2000;
    for (var i = 0; i < nb; i++) {
      for (final y in [0.0, depth]) {
        members.add(Member(role: MemberRole.beam, profile: beam, a: Vec3(i * bl, y, z), b: Vec3((i + 1) * bl, y, z)));
      }
      final zs = z + beam.h / 2000 + 0.01;
      if (pallets) {
        for (var j = 0; j < 2; j++) {
          final x0 = i * bl + 0.15 + j * (bl - 0.3) / 2, x1 = x0 + (bl - 0.3) / 2 - 0.1;
          surfaces.add(Surface(Vec3(x0, 0.05, zs + 0.14), Vec3(x1, 0.05, zs + 0.14), Vec3(x1, depth - 0.05, zs + 0.14), Vec3(x0, depth - 0.05, zs + 0.14), SurfaceKind.wood));
        }
      } else {
        surfaces.add(Surface(Vec3(i * bl, 0, zs), Vec3((i + 1) * bl, 0, zs), Vec3((i + 1) * bl, depth, zs), Vec3(i * bl, depth, zs), SurfaceKind.panel));
      }
    }
  }
  final nUps = (nb + 1) * 2;
  final pa = _basePlate(upright, nUp, 0, fy, checks, 'PA1', bolts: 2, minW: 120);
  final plates = <PlatePiece>[
    PlatePiece(mark: 'PA1', description: 'Placa base de puntal', w: pa.w, h: 120, t: pa.t, qty: nUps, notes: '2 anclajes ${pa.anchor}'),
    PlatePiece(mark: 'CN', description: 'Conector de larguero (chapa con uñas / tornillos)', w: 60, h: _roundUp(beam.h + 40, 10), t: 4, qty: nb * levels * 4),
    if (!pallets) PlatePiece(mark: 'BA', description: 'Balda de chapa plegada 0,8 mm', w: bl * 1000, h: depth * 1000, t: 1, qty: nb * levels),
  ];
  final bolts = <BoltItem>[
    BoltItem('Anclaje al suelo', '${pa.anchor} anclaje químico / mecánico', nUps * 2, 'PA1'),
    BoltItem('Pasador de seguridad de larguero', 'Pasador antidesenganche', nb * levels * 4, 'Conectores'),
  ];
  final welds = <WeldSpec>[
    WeldSpec(joint: 'Celosía de bastidor – puntales', type: 'En ángulo', throat: 3, lengthPerJoint: 4 * diag.b, count: members.where((m) => m.role == MemberRole.diagonal || m.role == MemberRole.strut).length * 2),
    WeldSpec(joint: 'Larguero – conector', type: 'En ángulo perimetral', throat: weldThroat(beam.tMin, 4, g), lengthPerJoint: 2 * (beam.h + beam.b), count: nb * levels * 4),
    WeldSpec(joint: 'Puntal – placa base', type: 'En ángulo perimetral', throat: weldThroat(upright.tMin, pa.t, g), lengthPerJoint: 4 * upright.b, count: nUps),
  ];
  final hyp = [
    ..._commonHypotheses(s),
    'Estantería de $nb vano(s) de ${_f(bl, 2)} m, fondo ${_f(depth, 2)} m, altura ${_f(hgt, 2)} m y $levels nivel(es) cada ${_f(hs, 2)} m.',
    'Carga por nivel y vano ${_f(p * 100, 0)} kg (${pallets ? 'palés' : 'baldas'}); largueros con flecha ≤ L/200 (EN 15512).',
    'Puntales de tubo (simplificación de los perfiles abiertos perforados comerciales); pandeo en el plano del pasillo con Lk = 1,5·h nivel (traslacional).',
    'Bastidores con celosía soldada. Anclaje obligatorio al suelo y placa de carga visible.',
  ];
  final assembly = [
    'Replanteo y nivelación de la solera (tolerancia ±10 mm).',
    'Montaje de bastidores (puntales + celosía) y anclaje al suelo.',
    'Colocación de largueros por niveles con pasadores de seguridad.',
    if (pallets) 'Protectores de puntal en pasillos de carretilla y placa de características.',
    'Revisión anual según EN 15635.',
  ];
  warnings.add(_warnValidate());
  if (pallets) warnings.add('Para estanterías de paletización comerciales se recomienda sistema certificado (EN 15512 / EN 15635).');
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
    footingSize: 0,
    frameX: List.generate(nb + 1, (i) => i * bl),
    gridY: [0, depth],
    ridgeHeight: hgt,
    surfaces: surfaces,
  );
}

// ---------------------------------------------------------------------------
// CANCELA / PUERTA / PORTÓN
// ---------------------------------------------------------------------------

Design _designCancela(StructureSpec s, String prompt) {
  final g = s.grade, fy = g.fy;
  final open = s.length, hgt = s.height;
  final checks = <Check>[];
  final warnings = <String>[...s.notes];
  final sliding = s.variant.startsWith('corredera');
  final selfSupp = s.variant.contains('autoportante');
  final two = s.variant.contains('2 hojas');
  final infill = s.variant.endsWith('chapa') ? 'chapa' : (s.variant.endsWith('malla') ? 'malla' : 'barrotes');
  final solidity = infill == 'chapa' ? 1.0 : (infill == 'malla' ? 0.3 : 0.25);
  final leafW = sliding ? open + 0.2 : (two ? open / 2 - 0.02 : open - 0.03);
  final nLeaves = sliding ? 1 : (two ? 2 : 1);
  final fw = 1.5 * s.wind * 1.7 * 1.2 * solidity * leafW * hgt; // kN por hoja
  // Larguero intermedio: franja de h/2, biapoyado en los montantes; flexión
  // respecto al eje débil (el canto mayor queda en el plano de la hoja).
  final mW = fw * leafW / 16;
  double wplz(SteelProfile p) => (p.h * p.b * p.b - (p.h - 2 * p.tw) * math.pow(p.b - 2 * p.tw, 2)) / 4 / 1000; // cm³
  double etaW(SteelProfile p) => mW / (wplz(p) * fy / 1.05 / 1000);
  final minH = open > 3.5 || hgt > 2.2 ? 80.0 : 60.0;
  final frameCands = rhsTable.where((p) => p.h >= minH && p.b >= 40).toList()..sort((a, b) => a.kgm.compareTo(b.kgm));
  final frame = frameCands.firstWhere((p) => etaW(p) <= _limit, orElse: () => frameCands.last);
  final bar = shsTable.first;
  // Peso de la hoja
  final perim = 2 * (leafW + hgt) + leafW; // + travesaño intermedio
  final nBars = infill == 'barrotes' ? (leafW / 0.12).floor() : 0;
  final kg = frame.kgm * perim + bar.kgm * nBars * (hgt - 0.1) + (infill == 'chapa' ? 11.8 * leafW * hgt : (infill == 'malla' ? 4 * leafW * hgt : 0));
  final gLeaf = kg * 9.81 / 1000; // kN
  checks.add(Check('Bastidor ${frame.name}', 'Viento sobre la hoja (larguero intermedio, eje débil)',
      etaW(frame), 'Fw = ${_f(fw, 2)} kN por hoja, MEd = ${_f(mW, 2)} kNm, hoja ${_f(leafW, 2)} x ${_f(hgt, 2)} m, ${_f(kg, 0)} kg'));
  final mPost = sliding ? fw / 2 * hgt : 1.35 * gLeaf * leafW / 2 + fw * hgt / 2;
  final post = _columnFor([...shsTable.where((p) => p.b >= 80), ...hebTable], sliding ? 'Pilar guía' : 'Pilar de cuelgue', 1.35 * gLeaf + 0.5,
      mPost, 2 * hgt, fy, checks);
  final members = <Member>[];
  final surfaces = <Surface>[];
  final pb = post.b / 1000;
  final hp = hgt + 0.15;
  final postsX = [-pb / 2, open + pb / 2];
  final footings = <Vec3>[];
  for (final x in postsX) {
    members.add(Member(role: MemberRole.column, profile: post, a: Vec3(x, 0, 0), b: Vec3(x, 0, hp)));
    footings.add(Vec3(x, 0, 0));
  }
  void leaf(double x0, double x1) {
    final z0 = 0.06, z1 = hgt;
    members.add(Member(role: MemberRole.frame, profile: frame, a: Vec3(x0, 0, z0), b: Vec3(x1, 0, z0)));
    members.add(Member(role: MemberRole.frame, profile: frame, a: Vec3(x0, 0, z1), b: Vec3(x1, 0, z1)));
    members.add(Member(role: MemberRole.frame, profile: frame, a: Vec3(x0, 0, z0), b: Vec3(x0, 0, z1), webDir: const Vec3(1, 0, 0)));
    members.add(Member(role: MemberRole.frame, profile: frame, a: Vec3(x1, 0, z0), b: Vec3(x1, 0, z1), webDir: const Vec3(1, 0, 0)));
    members.add(Member(role: MemberRole.rail, profile: frame, a: Vec3(x0, 0, (z0 + z1) / 2), b: Vec3(x1, 0, (z0 + z1) / 2)));
    if (!sliding) {
      members.add(Member(role: MemberRole.diagonal, profile: rhsTable.first, a: Vec3(x0, 0, z0 + 0.05), b: Vec3(x1, 0, (z0 + z1) / 2 - 0.03)));
    }
    if (infill == 'barrotes') {
      final n = ((x1 - x0) / 0.12).floor();
      for (var k = 1; k < n; k++) {
        final x = x0 + (x1 - x0) * k / n;
        members.add(Member(role: MemberRole.baluster, profile: bar, a: Vec3(x, 0, z0 + 0.03), b: Vec3(x, 0, z1 - 0.03)));
      }
    } else {
      surfaces.add(Surface(Vec3(x0, 0, z0), Vec3(x1, 0, z0), Vec3(x1, 0, z1), Vec3(x0, 0, z1), infill == 'chapa' ? SurfaceKind.panel : SurfaceKind.mesh));
    }
  }

  if (sliding) {
    final tail = selfSupp ? open * 0.4 : 0.0;
    leaf(-tail, open + 0.1);
  } else if (two) {
    leaf(0.01, open / 2 - 0.01);
    leaf(open / 2 + 0.01, open - 0.01);
  } else {
    leaf(0.015, open - 0.015);
  }
  final pa = _basePlate(post, 1.35 * gLeaf, mPost, fy, checks, 'PA1');
  final pinSize = gLeaf < 1.5 ? 'Ø20' : (gLeaf < 3 ? 'Ø25' : 'Ø30');
  final plates = <PlatePiece>[
    PlatePiece(mark: 'PA1', description: 'Placa base de pilar ${post.name}', w: pa.w, h: pa.w, t: pa.t, qty: 2, notes: '4 anclajes ${pa.anchor} (o pilar empotrado en dado)'),
    PlatePiece(mark: 'TP', description: 'Tapa de pilar', w: post.b, h: post.b, t: 4, qty: 2),
    if (infill == 'chapa') PlatePiece(mark: 'CH', description: 'Chapa de relleno 1,5 mm', w: leafW * 1000, h: hgt * 1000, t: 1.5, qty: nLeaves),
  ];
  final bolts = <BoltItem>[
    BoltItem('Anclaje de pilares', '${pa.anchor} varilla 8.8 + resina', 8, 'PA1'),
    if (!sliding) BoltItem('Pernios regulables $pinSize', 'Pernio de soldar con rodamiento', nLeaves * 2, 'Cuelgue de hojas'),
    if (!sliding) BoltItem('Pasador de suelo / cerrojo', 'Pasador vertical + tope', nLeaves, 'Cierre'),
    if (sliding && !selfSupp) BoltItem('Guía de suelo + 2 ruedas', 'Carril en U/V galvanizado + ruedas Ø100–120 (${_f(kg, 0)} kg)', 1, 'Rodadura'),
    if (selfSupp) BoltItem('Kit de puerta autoportante', 'Perfil guía + 2 carros + rodillo final (hoja ${_f(kg, 0)} kg)', 1, 'Rodadura'),
    if (sliding) BoltItem('Guía superior', 'Rodillos guía de nylon', 1, 'Pilar guía'),
    BoltItem('Cerradura', 'Cerradura de embutir para tubo 40 mm', 1, 'Hoja'),
  ];
  final welds = <WeldSpec>[
    WeldSpec(joint: 'Bastidor de hoja (inglete o a tope)', type: 'En ángulo perimetral / a tope', throat: weldThroat(frame.tMin, frame.tMin, g),
        lengthPerJoint: 2 * (frame.h + frame.b), count: nLeaves * 6),
    if (infill == 'barrotes')
      WeldSpec(joint: 'Barrotes – bastidor', type: 'En ángulo perimetral', throat: 3, lengthPerJoint: 4 * bar.b, count: members.where((m) => m.role == MemberRole.baluster).length * 2,
          process: '135 (MAG) hilo 0,8 mm', position: 'PA/PB taller'),
    if (infill == 'chapa') WeldSpec(joint: 'Chapa – bastidor (puntos cada 150 mm)', type: 'Puntos de soldadura', throat: 3, lengthPerJoint: 20, count: nLeaves * ((2 * (leafW + hgt)) / 0.15).ceil()),
    WeldSpec(joint: 'Pilar – placa base', type: 'En ángulo perimetral', throat: weldThroat(post.tMin, pa.t, g), lengthPerJoint: post.isHollow ? 4 * post.b : 2 * (2 * post.b + post.h), count: 2),
    if (!sliding) WeldSpec(joint: 'Pernios', type: 'En ángulo', throat: 4, lengthPerJoint: 2 * 60, count: nLeaves * 2 * 2),
  ];
  final hyp = [
    ..._commonHypotheses(s),
    'Cancela ${s.variant} de ${_f(open, 2)} m de hueco libre y ${_f(hgt, 2)} m de altura: $nLeaves hoja(s) de ${_f(leafW, 2)} m, ${_f(kg, 0)} kg cada una.',
    'Viento: qb = ${_f(s.wind, 2)} kN/m², ce = 1,7, cp = 1,2 y opacidad ${_f(solidity * 100, 0)} %.',
    sliding
        ? 'Pilares solicitados por el viento de la hoja cerrada (guía superior en el pilar).'
        : 'Pilar de cuelgue en ménsula: excentricidad del peso de la hoja (L/2) + viento con la hoja abierta.',
    if (infill == 'barrotes') 'Barrotes ${bar.name} cada 12 cm (hueco ≤ 10 cm).',
    'Si es motorizada: cumplir EN 12453 (bandas de seguridad, fotocélulas, fuerza de cierre).',
  ];
  final assembly = [
    'Dados de hormigón para pilares (≈ 0,5 x 0,5 x 0,6 m) o placas ancladas.',
    'Fabricación de hojas en taller sobre mesa plana (comprobar diagonales).',
    sliding ? 'Colocación de guía/kit${selfSupp ? ' autoportante' : ' de suelo'} nivelado y presentación de la hoja.' : 'Soldadura de pernios y presentación de hojas con cuñas; holgura inferior 15–20 mm.',
    'Ajuste de cierre, topes y cerradura; acabado (${s.finish}).',
  ];
  warnings.add(_warnValidate());
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
    footingSize: 0.5,
    frameX: [0, open],
    gridY: const [0, 0.15],
    ridgeHeight: hp,
    surfaces: surfaces,
  );
}

// ---------------------------------------------------------------------------
// VALLA / CERRAMIENTO
// ---------------------------------------------------------------------------

Design _designValla(StructureSpec s, String prompt) {
  if (s.variant.startsWith('reja')) return _designReja(s, prompt);
  final g = s.grade, fy = g.fy;
  final lx = s.length, hgt = s.height;
  final checks = <Check>[];
  final warnings = <String>[...s.notes];
  final infill = s.variant.isEmpty ? 'barrotes' : s.variant;
  final solidity = infill == 'chapa' ? 1.0 : (infill == 'malla' ? 0.3 : 0.25);
  final nb = math.max(1, (lx / 2.5).ceil());
  final sp = lx / nb;
  final qw = 1.5 * s.wind * _ce(hgt) * 1.3 * solidity; // kN/m²
  final post = _columnFor([...shsTable.where((p) => p.b >= 50), ...hebTable], 'Poste', 0.5, qw * sp * hgt * hgt / 2, 2 * hgt, fy, checks);
  final railP = _beamFor([...rhsTable, ...shsTable], 'Larguero', qw * hgt / 2, qw / 1.5 * hgt / 2, sp, fy, checks, defl: 200);
  final bar = shsTable.first;
  final members = <Member>[];
  final surfaces = <Surface>[];
  final footings = <Vec3>[];
  for (var i = 0; i <= nb; i++) {
    final x = i * sp;
    members.add(Member(role: MemberRole.column, profile: post, a: Vec3(x, 0, 0), b: Vec3(x, 0, hgt + 0.05)));
    footings.add(Vec3(x, 0, 0));
  }
  var nBars = 0;
  for (var i = 0; i < nb; i++) {
    final x0 = i * sp, x1 = (i + 1) * sp;
    for (final z in [0.15, hgt - 0.1]) {
      members.add(Member(role: MemberRole.rail, profile: railP, a: Vec3(x0, 0, z), b: Vec3(x1, 0, z)));
    }
    if (infill == 'barrotes') {
      final n = (sp / 0.12).floor();
      for (var k = 1; k < n; k++) {
        final x = x0 + sp * k / n;
        members.add(Member(role: MemberRole.baluster, profile: bar, a: Vec3(x, 0, 0.1), b: Vec3(x, 0, hgt)));
        nBars++;
      }
    } else {
      surfaces.add(Surface(Vec3(x0, 0, 0.12), Vec3(x1, 0, 0.12), Vec3(x1, 0, hgt - 0.05), Vec3(x0, 0, hgt - 0.05), infill == 'chapa' ? SurfaceKind.panel : SurfaceKind.mesh));
    }
  }
  final mBase = qw * sp * hgt * hgt / 2;
  final pa = _basePlate(post, 0.5, mBase, fy, checks, 'PA1');
  final plates = <PlatePiece>[
    PlatePiece(mark: 'PA1', description: 'Placa base de poste ${post.name}', w: pa.w, h: pa.w, t: pa.t, qty: nb + 1, notes: '4 anclajes ${pa.anchor}'),
    if (infill == 'chapa') PlatePiece(mark: 'CH', description: 'Chapa de cerramiento 1,2 mm (o panel)', w: sp * 1000, h: hgt * 1000, t: 1.2, qty: nb),
  ];
  final bolts = <BoltItem>[
    BoltItem('Anclaje de postes', '${pa.anchor} varilla 8.8 + resina', (nb + 1) * 4, 'PA1 sobre murete/zapata corrida'),
    if (infill == 'malla') BoltItem('Malla', 'Malla electrosoldada 200x50x4 + abrazaderas', nb, 'Paños'),
  ];
  final welds = <WeldSpec>[
    WeldSpec(joint: 'Poste – placa base', type: 'En ángulo perimetral', throat: weldThroat(post.tMin, pa.t, g), lengthPerJoint: post.isHollow ? 4 * post.b : 2 * (2 * post.b + post.h), count: nb + 1),
    WeldSpec(joint: 'Largueros – postes', type: 'En ángulo perimetral', throat: weldThroat(railP.tMin, post.tMin, g), lengthPerJoint: 2 * (railP.h + railP.b), count: nb * 4),
    if (nBars > 0) WeldSpec(joint: 'Barrotes – largueros', type: 'En ángulo perimetral', throat: 3, lengthPerJoint: 4 * bar.b, count: nBars * 2, process: '135 (MAG) hilo 0,8 mm', position: 'PA/PB taller'),
  ];
  final hyp = [
    ..._commonHypotheses(s),
    'Valla de ${_f(lx, 2)} m y ${_f(hgt, 2)} m de altura, postes cada ${_f(sp, 2)} m, relleno de $infill (opacidad ${_f(solidity * 100, 0)} %).',
    'Viento: qb = ${_f(s.wind, 2)} kN/m², ce = ${_f(_ce(hgt), 1)}, cp = 1,3 (muro aislado) → ${_f(qw / 1.5, 2)} kN/m² característica.',
    'Postes en ménsula empotrados en la base (placa anclada a murete o zapata corrida).',
  ];
  final assembly = [
    'Murete o zapata corrida y replanteo de postes cada ${_f(sp, 2)} m.',
    'Fabricación de paños en taller (largueros + relleno).',
    'Anclaje y aplomado de postes; soldadura o atornillado de paños.',
    'Acabado (${s.finish}).',
  ];
  warnings.add(_warnValidate());
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
    footingSize: 0,
    frameX: nb <= 16 ? List.generate(nb + 1, (i) => i * sp) : [0, lx],
    gridY: const [0, 0.15],
    ridgeHeight: hgt,
    surfaces: surfaces,
  );
}

// ---------------------------------------------------------------------------
// PÓRTICO DE ELEVACIÓN (POLIPASTO)
// ---------------------------------------------------------------------------

Design _designPortico(StructureSpec s, String prompt) {
  final g = s.grade, fy = g.fy;
  final span = s.width, hgt = s.height, p = s.pointLoad;
  final checks = <Check>[];
  final warnings = <String>[...s.notes];
  final pd = 1.5 * 1.25 * p + 1.35 * 0.05 * p; // impacto 1,25 + peso del polipasto
  final beam = _choose([...ipeTable, ...hebTable], (b) {
    final med = pd * span / 4 + 1.35 * _self(b) * span * span / 8;
    // Pandeo lateral (EC3 6.3.2.2) con Mcr aproximado, C1 = 1,35
    final lMm = span * 1000;
    final it = (2 * b.b * math.pow(b.tf, 3) + (b.h - 2 * b.tf) * math.pow(b.tw, 3)) / 3;
    final izMm = b.iz * 1e4;
    final iw = izMm * math.pow(b.h - b.tf, 2) / 4;
    final mcr = 1.35 * math.pi * math.pi * _youngE * izMm / (lMm * lMm) *
        math.sqrt(iw / izMm + lMm * lMm * 81000 * it / (math.pi * math.pi * _youngE * izMm)) / 1e6;
    final lLT = math.sqrt(b.wply * 1000 * fy / (mcr * 1e6));
    final chiLT = _chi(lLT, b.h / b.b > 2 ? 0.34 : 0.21);
    final mb = chiLT * _mRd(b, fy);
    final defl = p * 1000 * math.pow(lMm, 3) / (48 * _youngE * b.iy * 1e4);
    return [
      Check('Viga carril ${b.name}', 'Flexión con pandeo lateral M/Mb,Rd', med / mb,
          'Pd = ${_f(pd, 1)} kN (impacto 1,25), MEd = ${_f(med, 1)} kN·m, Mcr = ${_f(mcr, 1)} kN·m, χLT = ${_f(chiLT, 2)}'),
      Check('Viga carril ${b.name}', 'Flecha ELS ≤ L/500', defl / (lMm / 500), 'δ = ${_f(defl)} mm con ${_f(p * 100, 0)} kg'),
      Check('Ala inferior ${b.name}', 'Flexión local del ala (carro)', (p * 1.5 * 1.25 / 2) * 1000 * 30 / (b.b * math.pow(b.tf, 2) / 4 * fy / gammaM0) , 'Reacción por rueda ${_f(p * 1.5 * 1.25 / 4, 1)} kN'),
    ];
  }, checks);
  final a = math.max(0.8, _roundUp(0.35 * hgt, 0.05));
  final legLen = math.sqrt(a * a + hgt * hgt);
  final cosB = hgt / legLen;
  final nLeg = (pd / 2 + 1.35 * _self(beam) * span / 2) / 2 / cosB + 0.5;
  final leg = _columnFor(shsTable.where((q) => q.b >= 60).toList(), 'Pata', nLeg, 0, legLen / 2, fy, checks);
  final thrust = nLeg * a / legLen;
  final tie = _tieFor('Tirante de base', thrust, fy, checks, cands: shsTable.where((q) => q.b >= 40).toList());
  final members = <Member>[];
  final footings = <Vec3>[];
  final zb = hgt;
  for (final y in [0.0, span]) {
    members.add(Member(role: MemberRole.column, profile: leg, a: Vec3(0, y, 0), b: Vec3(a, y, zb - beam.h / 1000)));
    members.add(Member(role: MemberRole.column, profile: leg, a: Vec3(2 * a, y, 0), b: Vec3(a, y, zb - beam.h / 1000)));
    members.add(Member(role: MemberRole.tie, profile: tie, a: Vec3(0, y, 0.15), b: Vec3(2 * a, y, 0.15)));
    members.add(Member(role: MemberRole.tie, profile: tie, a: Vec3(a / 2, y, zb / 2), b: Vec3(1.5 * a, y, zb / 2)));
    footings.addAll([Vec3(0, y, 0), Vec3(2 * a, y, 0)]);
  }
  members.add(Member(role: MemberRole.beam, profile: beam, a: Vec3(a, 0, zb - beam.h / 2000), b: Vec3(a, span, zb - beam.h / 2000)));
  final kb = math.min(0.8, span / 4);
  final knee = angleTable[2];
  // Jabalcones longitudinales: de cada pata a la viga (estabilidad fuera del plano de la A)
  final zTop = zb - beam.h / 1000;
  final zk = zTop - kb;
  final dxk = a * (1 - zk / zTop); // retranqueo de la pata a la altura zk
  for (final (y, yb) in [(0.0, kb), (span, span - kb)]) {
    for (final xk in [a - dxk, a + dxk]) {
      members.add(Member(role: MemberRole.brace, profile: knee, a: Vec3(xk, y, zk), b: Vec3(a, yb, zTop)));
    }
  }
  final plates = <PlatePiece>[
    PlatePiece(mark: 'PC1', description: 'Placa de cabeza (unión viga – patas)', w: _roundUp(beam.b + 60, 10), h: _roundUp(2 * leg.b + 120, 10), t: 15, qty: 2, notes: '4 M16 8.8'),
    PlatePiece(mark: 'PA1', description: 'Placa de pie de pata', w: 200, h: 200, t: 12, qty: 4, notes: '4 anclajes M12 o 2 ruedas con freno'),
    PlatePiece(mark: 'TO', description: 'Topes de final de carrera del carro', w: 80, h: _roundUp(beam.h * 0.6, 10), t: 10, qty: 2),
  ];
  final bolts = <BoltItem>[
    BoltItem('Viga – cabezas', 'M16 x 50 8.8', 8, 'PC1'),
    BoltItem('Anclaje de patas', 'M12 anclaje químico (o ruedas Ø150 con freno, ${_f(nLeg * 2, 1)} kN)', 16, 'PA1'),
    BoltItem('Carro portapolipasto', 'Carro de empuje para ala ${_f(beam.b, 0)} mm, ${_f(p * 100, 0)} kg', 1, 'Viga carril'),
  ];
  final welds = <WeldSpec>[
    WeldSpec(joint: 'Patas – placa de cabeza', type: 'En ángulo perimetral', throat: weldThroat(leg.tMin, 15, g), lengthPerJoint: 4 * leg.b * 1.2, count: 4),
    WeldSpec(joint: 'Patas – placa de pie', type: 'En ángulo perimetral', throat: weldThroat(leg.tMin, 12, g), lengthPerJoint: 4 * leg.b * 1.2, count: 4),
    WeldSpec(joint: 'Tirantes – patas', type: 'En ángulo perimetral', throat: weldThroat(tie.tMin, leg.tMin, g), lengthPerJoint: 4 * tie.b * 1.3, count: 8),
    WeldSpec(joint: 'Topes y jabalcones', type: 'En ángulo', throat: 4, lengthPerJoint: 2 * 80, count: 6),
  ];
  final hyp = [
    ..._commonHypotheses(s),
    'Pórtico para polipasto de ${_f(p * 100, 0)} kg: luz ${_f(span, 2)} m, altura bajo viga ${_f(hgt, 2)} m, patas en A con base ${_f(2 * a, 2)} m.',
    'Coeficiente dinámico 1,25 y peso del polipasto 5 % (EN 1991-3 simplificado). Flecha ≤ L/500.',
    'Pandeo lateral de la viga con carga en el ala inferior, sin arriostramiento intermedio (EC3 6.3.2.2).',
    'Rotular la carga máxima (CMU ${_f(p * 100, 0)} kg) en la viga. Prueba de carga 1,25·CMU antes de su uso (Directiva de Máquinas / RD 1215/1997).',
  ];
  final assembly = [
    'Fabricación de las A (patas + tirantes) y de la viga con topes.',
    'Presentación de las A, colocación de la viga y apriete de la unión PC1.',
    'Jabalcones, anclaje o ruedas con freno.',
    'Montaje del carro y polipasto; prueba de carga y señalización.',
  ];
  warnings.add(_warnValidate());
  warnings.add('Equipo de elevación: requiere marcado CE / certificado de conformidad y revisión periódica.');
  s.length = 2 * a;
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
    footingSize: 0,
    frameX: [0, a, 2 * a],
    gridY: [0, span],
    ridgeHeight: hgt,
  );
}

// ---------------------------------------------------------------------------
// POSTE / MÁSTIL / SOPORTE DE CARTEL
// ---------------------------------------------------------------------------

Design _designPoste(StructureSpec s, String prompt) {
  final g = s.grade, fy = g.fy;
  final bw = s.length, bh = s.width, hgt = s.height;
  final checks = <Check>[];
  final warnings = <String>[...s.notes];
  final sign = s.variant == 'cartel';
  final np = sign && bw > 2.0 ? 2 : 1;
  final top = hgt + bh;
  final cf = sign ? 1.8 : 1.2;
  final f = 1.5 * s.wind * _ce(top) * cf * bw * bh; // kN
  final ecc = np == 2 ? 1.25 : 1.0; // excentricidad ±B/4 (EN 1991-1-4 7.4.3)
  final mPost = f / np * ecc * (hgt + bh / 2);
  final selfPanel = sign ? 0.35 * bw * bh : 0.1;
  final post = _columnFor([...shsTable.where((p) => p.b >= 60), ...hebTable], sign ? 'Poste del cartel' : 'Mástil',
      1.35 * (selfPanel / np + 0.5), mPost, 2 * top, fy, checks);
  final members = <Member>[];
  final footings = <Vec3>[];
  final surfaces = <Surface>[];
  final xs = np == 2 ? [bw * 0.22, bw * 0.78] : [bw / 2];
  for (final x in xs) {
    members.add(Member(role: MemberRole.column, profile: post, a: Vec3(x, 0, 0), b: Vec3(x, 0, top)));
    footings.add(Vec3(x, 0, 0));
  }
  if (sign || bw > 0.3) {
    final fr = rhsTable.firstWhere((p) => p.name == (sign && bw > 3 ? 'RHS 80x40x3' : 'RHS 60x40x2'));
    final y = -post.b / 2000 - fr.b / 2000;
    final z0 = hgt, z1 = hgt + bh;
    members.add(Member(role: MemberRole.frame, profile: fr, a: Vec3(0, y, z0), b: Vec3(bw, y, z0)));
    members.add(Member(role: MemberRole.frame, profile: fr, a: Vec3(0, y, z1), b: Vec3(bw, y, z1)));
    final nv = math.max(1, (bw / 1.2).ceil());
    for (var k = 0; k <= nv; k++) {
      members.add(Member(role: MemberRole.frame, profile: fr, a: Vec3(bw * k / nv, y, z0), b: Vec3(bw * k / nv, y, z1), webDir: const Vec3(1, 0, 0)));
    }
    checks.add(Check('Bastidor ${fr.name}', 'Viento sobre panel entre montantes', (f / bw / 2) * math.pow(bw / nv, 2) / 8 / _mRd(fr, fy), 'F = ${_f(f, 1)} kN total'));
    surfaces.add(Surface(Vec3(0, y - 0.03, z0), Vec3(bw, y - 0.03, z0), Vec3(bw, y - 0.03, z1), Vec3(0, y - 0.03, z1), SurfaceKind.panel));
  }
  final pa = _basePlate(post, 1.35 * selfPanel / np, mPost, fy, checks, 'PA1', bolts: 4, minW: 250);
  final mk = mPost / 1.5;
  final fSize = math.max(0.8, _roundUp(math.pow(mk / 8, 1 / 3).toDouble(), 0.1));
  final plates = <PlatePiece>[
    PlatePiece(mark: 'PA1', description: 'Placa base de ${sign ? 'poste' : 'mástil'} con 4 cartelas', w: pa.w, h: pa.w, t: pa.t, qty: np, notes: '4 pernos ${pa.anchor} embebidos'),
    PlatePiece(mark: 'CA', description: 'Cartela de rigidización de base', w: 120, h: 200, t: 10, qty: np * 4),
    if (sign) PlatePiece(mark: 'PN', description: 'Panel del cartel (chapa 1,5 mm / composite)', w: bw * 1000, h: bh * 1000, t: 1.5, qty: 1),
  ];
  final bolts = <BoltItem>[
    BoltItem('Pernos de anclaje', '${pa.anchor} 8.8 con tuerca, contratuerca y plantilla', np * 4, 'PA1 embebidos en zapata'),
    if (sign) BoltItem('Fijación del panel', 'Remache / tornillo inox', (2 * (bw + bh) / 0.3).ceil(), 'Bastidor'),
  ];
  final welds = <WeldSpec>[
    WeldSpec(joint: 'Poste – placa base + cartelas', type: 'En ángulo perimetral', throat: weldThroat(post.tMin, pa.t, g),
        lengthPerJoint: (post.isHollow ? 4 * post.b : 2 * (2 * post.b + post.h)) + 4 * 2 * 200, count: np),
    if (sign) WeldSpec(joint: 'Bastidor del cartel y unión a postes', type: 'En ángulo perimetral', throat: 3, lengthPerJoint: 2 * (60 + 40), count: 8 + np * 2),
  ];
  final hyp = [
    ..._commonHypotheses(s),
    sign
        ? 'Cartel de ${_f(bw, 2)} x ${_f(bh, 2)} m a ${_f(hgt, 2)} m de altura libre sobre $np poste(s).'
        : '${s.variant[0].toUpperCase()}${s.variant.substring(1)} de ${_f(top, 2)} m con elemento de ${_f(bw, 2)} x ${_f(bh, 2)} m en cabeza.',
    'Viento: qb = ${_f(s.wind, 2)} kN/m², ce = ${_f(_ce(top), 1)}, cf = ${_f(cf, 1)}${np == 2 ? ', excentricidad ±B/4 (+25 %)' : ''}: F = ${_f(f / 1.5, 1)} kN característica.',
    'Poste en ménsula (Lk = 2·L). Momento en la base ${_f(mPost, 1)} kN·m por poste.',
    'Zapata orientativa ${_f(fSize, 1)} x ${_f(fSize, 1)} x 1,0 m por poste (vuelco con coeficiente 1,5; sin estudio geotécnico).',
  ];
  final assembly = [
    'Zapata con pernos embebidos mediante plantilla y nivelación.',
    'Izado del poste con grúa, aplomado y retacado con mortero sin retracción.',
    if (sign) 'Montaje del bastidor y del panel.',
    'Acabado (${s.finish}); revisar apriete a los 30 días.',
  ];
  warnings.add(_warnValidate());
  if (sign) warnings.add('Carteles publicitarios: suelen requerir licencia municipal y proyecto firmado.');
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
    footingSize: fSize,
    frameX: [0, bw],
    gridY: const [0, 0.3],
    ridgeHeight: top,
    surfaces: surfaces,
  );
}
