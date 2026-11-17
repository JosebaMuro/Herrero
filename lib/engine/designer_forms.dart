part of 'designer.dart';

// ===========================================================================
// Formas especiales: escalera de caracol, escala de gato, pasamanos a pared y
// reja de ventana. Mismo criterio que el resto: predimensionado simplificado.
// ===========================================================================

/// Cable de acero inoxidable 7x19 Ø6 (rellenos de barandilla).
const _cable6 = SteelProfile(
    name: 'Cable inox Ø6 7x19',
    family: ProfileFamily.round,
    h: 6,
    b: 6,
    tw: 3,
    tf: 3,
    area: 0.17,
    iy: 0.0064,
    wply: 0.036,
    iz: 0.0064,
    kgm: 0.15);

/// Rodapié de pletina 100x5 (EN ISO 14122-3: altura ≥ 100 mm).
const _toePlate = SteelProfile(
    name: 'Pletina 100x5',
    family: ProfileFamily.flat,
    h: 100,
    b: 5,
    tw: 5,
    tf: 5,
    area: 5.0,
    iy: 41.7,
    wply: 12.5,
    iz: 0.10,
    kgm: 3.93);

SteelProfile _flatNamed(String n) => flatTable.firstWhere((p) => p.name == n);
SteelProfile _chsMin(double d) => chsTable.firstWhere((p) => p.h >= d - 0.05);

// ---------------------------------------------------------------------------
// ESCALERA DE CARACOL
// ---------------------------------------------------------------------------

Design _designCaracol(StructureSpec s, String prompt) {
  final g = s.grade, fy = g.fy;
  final hTot = s.height, dia = s.width, q = s.liveLoad;
  final checks = <Check>[];
  final warnings = <String>[...s.notes];
  final members = <Member>[];
  final surfaces = <Surface>[];
  final rOut = dia / 2;
  final cx = rOut, cy = rOut; // eje del mástil
  Vec3 polar(double r, double a, double z) => Vec3(cx + r * math.cos(a), cy + r * math.sin(a), z);

  // Peldañeado (CTE DB-SUA 1 §4.2.1, uso restringido): C ≤ 20 cm, huella ≥ 22 cm
  // en la línea de huella (eje si el ancho < 1 m; a 50 cm del lado estrecho si no)
  // y ≤ 44 cm en el borde exterior; altura libre bajo la vuelta superior.
  final n = math.max(2, (hTot / 0.20 - 1e-9).ceil());
  final c = hTot / n;
  const r0e = 0.07; // radio del collarín sobre el mástil
  final width = rOut - r0e;
  final rw = r0e + (width < 1 ? width / 2 : 0.5);
  final thLo = 0.22 / rw, thHi = 0.44 / rOut, thHead = 2 * math.pi * c / 2.16;
  var th = math.min(thLo * 1.04, math.min(thHi, thHead));
  if (th < thLo) th = thLo;
  final perTurn = 2 * math.pi / th;
  final head = perTurn * c - 0.06;
  final nT = n - 1; // el último paso es la meseta de llegada
  checks.add(Check('Peldañeado', 'Contrahuella ≤ 20 cm (uso restringido)', c / 0.20,
      '$n contrahuellas de ${_f(c * 100)} cm; $nT peldaños de ${_f(th * 180 / math.pi)}° (${_f(perTurn)} por vuelta)'));
  checks.add(Check('Huella', 'Huella ≥ 22 cm en la línea de huella', 0.22 / (rw * th),
      '${_f(rw * th * 100)} cm a ${_f(rw, 2)} m del eje'));
  checks.add(Check('Huella', 'Huella ≤ 44 cm en el borde exterior', rOut * th / 0.44, '${_f(rOut * th * 100)} cm'));
  checks.add(Check('Paso libre', 'Altura libre ≥ 2,10 m bajo la vuelta superior', 2.10 / head, '${_f(head, 2)} m'));
  checks.add(Check('Anchura útil', 'Anchura ≥ 0,80 m (uso restringido)', 0.80 / width,
      '${_f(width, 2)} m entre el collarín y el borde exterior'));

  // Costilla de peldaño en voladizo desde el mástil
  final qPoint = q >= 4 ? 4.0 : 2.0;
  const gT = 0.45;
  final qd = 1.35 * gT + 1.5 * q;
  final lc = rOut - r0e;
  final mU = qd * th * (math.pow(rOut, 3) / 3 - r0e * rOut * rOut / 2 + math.pow(r0e, 3) / 6);
  final mP = 1.5 * qPoint * lc;
  final rib = _choose([...flatTable.where((p) => p.h >= 50 && p.b >= 8), ...rhsTable.where((p) => p.h <= 100)], (p) {
    final defl = qPoint * 1000 * math.pow(lc * 1000, 3) / (3 * _youngE * p.iy * 1e4);
    return [
      Check('Costilla de peldaño ${p.name}', 'Voladizo: uniforme ${_f(q, 0)} kN/m² y puntual ${_f(qPoint, 0)} kN en el borde',
          math.max(mU, mP) / _mRd(p, fy), 'Voladizo ${_f(lc, 2)} m, MEd = ${_f(math.max(mU, mP), 2)} kN·m'),
      Check('Costilla de peldaño ${p.name}', 'Flecha en punta ≤ L/150', defl / (lc * 1000 / 150), 'δ = ${_f(defl)} mm'),
    ];
  }, checks);

  // Mástil: compresión + flexión por sobrecarga en un cuarto de vuelta
  final aTread = th / 2 * (rOut * rOut - r0e * r0e);
  final aLand = math.pi / 4 * (rOut * rOut - r0e * r0e);
  final nEd = (1.35 * gT + 1.5 * q) * (aTread * nT + aLand / 2) + 1.35 * 0.15 * rOut * th * nT;
  final mEd = 0.5 * 1.5 * q * aLand * 0.55 * rOut;
  final mast = _columnFor(chsTable.where((p) => p.h >= 114).toList(), 'Mástil', nEd, mEd, hTot, fy, checks);
  final r0 = math.max(r0e, mast.h / 2000 + 0.012);

  // Geometría
  final handrail = _chsMin(42.4);
  final bal = shsTable.first;
  final nb = (rOut * th / 0.11).ceil(); // barrotes por peldaño (hueco ≤ 10 cm)
  const hr = 0.9;
  final rh = rOut - 0.03;
  members.add(Member(role: MemberRole.column, profile: mast, a: polar(0, 0, 0), b: polar(0, 0, hTot)));
  final floorKind = s.roofing.contains('tramex') ? SurfaceKind.grating : SurfaceKind.floor;
  for (var k = 1; k <= nT; k++) {
    final a0 = (k - 1) * th, a1 = k * th, z = k * c;
    final am = (a0 + a1) / 2;
    members.add(Member(role: MemberRole.tread, profile: rib, a: polar(r0, am, z - 0.005), b: polar(rOut - 0.01, am, z - 0.005)));
    surfaces.add(Surface(polar(r0, a0, z), polar(rOut, a0, z), polar(rOut, a1, z), polar(r0, a1, z), floorKind));
    // pasamanos helicoidal sobre la nariz del peldaño y barrotes
    final next = k < nT ? z + c : hTot;
    members.add(Member(role: MemberRole.handrail, profile: handrail, a: polar(rh, a0, z + hr), b: polar(rh, a1, next + hr)));
    for (var j = 0; j < nb; j++) {
      final f = j / nb;
      final a = a0 + th * f;
      members.add(Member(role: MemberRole.baluster, profile: bal, a: polar(rh, a, z), b: polar(rh, a, z + hr + (next - z) * f - 0.03)));
    }
  }
  // Meseta de llegada: cuarto de círculo anclado al borde del hueco del forjado
  final aE = nT * th;
  final landBeam = rhsTable[4];
  for (final a in [aE, aE + math.pi / 2]) {
    members.add(Member(role: MemberRole.beam, profile: landBeam, a: polar(r0, a, hTot - 0.04), b: polar(rOut, a, hTot - 0.04)));
  }
  const segs = 3;
  for (var i = 0; i < segs; i++) {
    final a0 = aE + math.pi / 2 * i / segs, a1 = aE + math.pi / 2 * (i + 1) / segs;
    surfaces.add(Surface(polar(r0, a0, hTot), polar(rOut, a0, hTot), polar(rOut, a1, hTot), polar(r0, a1, hTot), floorKind));
    members.add(Member(role: MemberRole.handrail, profile: handrail, a: polar(rh, a0, hTot + hr), b: polar(rh, a1, hTot + hr)));
    for (var j = 0; j < 3; j++) {
      final a = a0 + (a1 - a0) * j / 3;
      members.add(Member(role: MemberRole.baluster, profile: bal, a: polar(rh, a, hTot), b: polar(rh, a, hTot + hr - 0.03)));
    }
    members.add(Member(role: MemberRole.rail, profile: _flatNamed('Pletina 50x8'), a: polar(rOut, a0, hTot - 0.04), b: polar(rOut, a1, hTot - 0.04)));
  }
  members.add(Member(role: MemberRole.post, profile: handrail, a: polar(rh, aE + math.pi / 2, hTot), b: polar(rh, aE + math.pi / 2, hTot + hr)));

  final pa = _basePlate(mast, nEd, mEd, fy, checks, 'PA1');
  final nBal = nb * nT + segs * 3;
  final plates = <PlatePiece>[
    PlatePiece(mark: 'PA1', description: 'Placa base del mástil ${mast.name}', w: pa.w, h: pa.w, t: pa.t, qty: 1,
        notes: '4 anclajes químicos ${pa.anchor}'),
    PlatePiece(mark: 'PE', description: 'Peldaño en abanico de chapa lagrimada 5 mm (${_f(th * 180 / math.pi)}°)', w: (rOut - r0) * 1000,
        h: rOut * th * 1000 + 20, t: 5, qty: nT, notes: 'Con pestaña plegada en la nariz; soldado a costilla y collarín'),
    PlatePiece(mark: 'CL', description: 'Collarín de peldaño (tubo a medida sobre el mástil)', w: _roundUp(c * 1000, 5),
        h: _roundUp(math.pi * (mast.h + 12), 5), t: 6, qty: nT, notes: 'Desarrollo; se apilan y se fijan con tornillo prisionero'),
    PlatePiece(mark: 'ME', description: 'Meseta de llegada en cuarto de círculo (chapa lagrimada 5 mm)', w: rOut * 1000, h: rOut * 1000, t: 5, qty: 1),
    PlatePiece(mark: 'PT1', description: 'Pletina de anclaje de la meseta al forjado', w: 200, h: 100, t: 10, qty: 2, notes: '2 anclajes químicos M12'),
  ];
  final bolts = <BoltItem>[
    BoltItem('Anclaje del mástil', '${pa.anchor} varilla 8.8 + resina epoxi', 4, 'PA1 sobre solera'),
    BoltItem('Anclaje de la meseta', 'M12 anclaje químico', 4, 'PT1 al borde del forjado'),
    BoltItem('Prisioneros de collarín', 'M10 x 20 allen', nT, 'Collarín – mástil'),
  ];
  final welds = <WeldSpec>[
    WeldSpec(joint: 'Mástil – placa base', type: 'En ángulo perimetral', throat: weldThroat(mast.tMin, pa.t, g),
        lengthPerJoint: math.pi * mast.h, count: 1),
    WeldSpec(joint: 'Costilla – collarín y peldaño', type: 'En ángulo', throat: 4, lengthPerJoint: 2 * rib.h + (rOut - r0) * 1000, count: nT),
    WeldSpec(joint: 'Barandilla helicoidal: barrotes y pasamanos', type: 'En ángulo perimetral (tubo)', throat: 3, lengthPerJoint: 80,
        count: nBal * 2 + nT + segs, process: '135 (MAG) hilo 0,8 mm / 141 (TIG) en acabados vistos', position: 'PA/PB taller'),
  ];
  final hyp = [
    ..._commonHypotheses(s),
    'Escalera de caracol de Ø ${_f(dia, 2)} m y ${_f(hTot, 2)} m de altura: $n contrahuellas de ${_f(c * 100)} cm y $nT peldaños en abanico de ${_f(th * 180 / math.pi)}° sobre mástil ${mast.name}.',
    'Huella de ${_f(rw * th * 100)} cm en la línea de huella (a ${_f(rw, 2)} m del eje) y ${_f(rOut * th * 100)} cm en el borde exterior '
        '(CTE DB-SUA 1 §4.2.1, uso restringido: C ≤ 20 cm, H ≥ 22 cm, anchura ≥ 0,80 m).',
    'Peldaños en voladizo desde el mástil con costilla ${rib.name}; sobrecarga ${_f(q, 0)} kN/m² y puntual ${_f(qPoint, 0)} kN en el borde exterior.',
    'Mástil empotrado en la base y sujeto arriba por la meseta anclada al forjado; flexión por sobrecarga en un cuarto de vuelta.',
    'Barandilla helicoidal de ${_f(hr, 2)} m con pasamanos ${handrail.name} y $nb barrotes por peldaño (hueco ≤ 10 cm).',
    'Hueco en el forjado de Ø ≥ ${_f(dia + 0.05, 2)} m; en el lado del mástil la huella es mínima (casquillo o collarín de ≥ 14 cm).',
  ];
  final assembly = [
    'Replanteo del eje bajo el hueco del forjado; comprobar la altura real entre acabados.',
    'Anclaje de la placa base y aplomado del mástil.',
    'Ensartado de los peldaños con su collarín, de abajo hacia arriba, girando cada uno ${_f(th * 180 / math.pi)}°.',
    'Fijación de la meseta de llegada al forjado (PT1) y al mástil.',
    'Montaje de barrotes y del pasamanos helicoidal curvado en taller; repaso de soldaduras y acabado (${s.finish}).',
  ];
  warnings.add('Escalera de caracol: el CTE solo la admite en uso restringido (vivienda, altillo, mantenimiento). '
      'Para uso público hace falta una escalera de tramos rectos (huella ≥ 28 cm y anchura ≥ 1,00 m).');
  warnings.add(_warnValidate());
  if (s.variant.contains('exterior')) warnings.add('Escalera exterior: galvanizado en caliente recomendado y peldaños antideslizantes con drenaje.');
  return Design(
    spec: s..length = dia,
    prompt: prompt,
    members: members,
    plates: plates,
    bolts: bolts,
    welds: welds,
    checks: checks,
    hypotheses: hyp,
    assembly: assembly,
    warnings: warnings,
    footings: [polar(0, 0, 0)],
    footingSize: 0,
    frameX: [0, dia],
    gridY: [0, dia],
    ridgeHeight: hTot,
    surfaces: surfaces,
  );
}

// ---------------------------------------------------------------------------
// ESCALA DE GATO (escala fija con jaula, EN ISO 14122-4)
// ---------------------------------------------------------------------------

Design _designEscalaGato(StructureSpec s, String prompt) {
  final g = s.grade, fy = g.fy;
  final hTot = s.height, w = s.width;
  final checks = <Check>[];
  final warnings = <String>[...s.notes];
  final members = <Member>[];
  final surfaces = <Surface>[];
  const off = 0.2; // separación de los peldaños al paramento (≥ 200 mm)
  const ext = 1.1; // prolongación de los largueros sobre el desembarco
  final hTop = hTot + ext;
  final nR = math.max(1, (hTot / 0.28).round());
  final pitch = hTot / nR;
  final users = math.max(1, (hTot / 6).ceil());
  final nBr = math.max(2, ((hTot + 0.9) / 2.0).ceil());
  final lb = (hTot + 0.9) / nBr; // separación de soportes a pared
  checks.add(Check('Geometría', 'Peldaños equidistantes 225–300 mm', pitch / 0.30, '$nR peldaños cada ${_f(pitch * 1000, 0)} mm'));
  checks.add(Check('Geometría', 'Ancho libre entre largueros 400–600 mm', math.max(w / 0.6, 0.4 / w), '${_f(w * 1000, 0)} mm'));

  // Peldaño: 1,5 kN en el centro (EN ISO 14122-4)
  final rung = _choose(roundTable.where((p) => p.h >= 20).toList(), (p) {
    final med = 1.5 * 1.5 * w / 4;
    final defl = 1.5 * 1000 * math.pow(w * 1000, 3) / (48 * _youngE * p.iy * 1e4);
    return [
      Check('Peldaño ${p.name}', 'Carga puntual 1,5 kN en el centro', med / _mRd(p, fy), 'MEd = ${_f(med, 2)} kN·m, luz ${_f(w, 2)} m'),
      Check('Peldaño ${p.name}', 'Flecha ≤ L/200', defl / (w * 1000 / 200), 'δ = ${_f(defl, 2)} mm'),
    ];
  }, checks);
  // Larguero: compresión + flexión entre soportes (los peldaños arriostran el eje débil)
  final stile = _choose(flatTable.where((p) => p.h >= 60 && p.b >= 10).toList(), (p) {
    final lr = _lambdaBar(lb * 1000, p.ry, fy);
    final nb = _chi(lr, 0.49) * p.area * fy / gammaM1 / 10;
    final ned = 1.5 * 1.5 * users / 2 + 1.35 * _self(p) * hTop;
    final med = 1.5 * 0.5 * lb / 4;
    return [
      Check('Larguero ${p.name}', 'Flexocompresión N/Nb + M/Mc ≤ 1', ned / nb + med / _mRd(p, fy),
          'NEd = ${_f(ned, 2)} kN ($users persona${users > 1 ? 's' : ''}), MEd = ${_f(med, 2)} kN·m, soportes cada ${_f(lb, 2)} m'),
    ];
  }, checks);
  // Soporte a pared: ménsula de 200 mm con anclaje
  final vEd = 1.5 * 1.5 * users / 2;
  final brk = _flatNamed('Pletina 60x8');
  final mBr = vEd * off;
  final tAnchor = mBr / 0.08 + 0.5;
  final anc = _anchorFor(tAnchor);
  checks.add(Check('Soporte a pared ${brk.name}', 'Ménsula de ${_f(off * 1000, 0)} mm (pletina de canto)', mBr / _mRd(brk, fy),
      'VEd = ${_f(vEd, 2)} kN, MEd = ${_f(mBr, 2)} kN·m'));
  checks.add(Check('Anclaje de soporte ${anc.$1}', 'Tracción en el anclaje superior', tAnchor / anc.$2, 'NEd = ${_f(tAnchor, 2)} kN'));

  // Geometría: pared en x = 0, peldaños en x = off, subida en z
  surfaces.add(Surface(Vec3(-0.02, -0.4, 0), Vec3(-0.02, w + 0.4, 0), Vec3(-0.02, w + 0.4, hTot), Vec3(-0.02, -0.4, hTot), SurfaceKind.wall));
  surfaces.add(Surface(Vec3(-0.02, -0.4, hTot), Vec3(-0.02, w + 0.4, hTot), Vec3(-0.6, w + 0.4, hTot), Vec3(-0.6, -0.4, hTot), SurfaceKind.floor));
  for (final y in [0.0, w]) {
    members.add(Member(role: MemberRole.rail, profile: stile, a: Vec3(off, y, 0), b: Vec3(off, y, hTop), webDir: const Vec3(1, 0, 0)));
  }
  for (var k = 1; k <= nR; k++) {
    final z = k * pitch;
    members.add(Member(role: MemberRole.tread, profile: rung, a: Vec3(off, 0, z), b: Vec3(off, w, z)));
  }
  for (var j = 1; j <= nBr; j++) {
    final z = j * lb;
    for (final y in [0.0, w]) {
      members.add(Member(role: MemberRole.bracket, profile: brk, a: Vec3(0, y, z), b: Vec3(off, y, z)));
    }
  }
  // Prolongación: unión del larguero al borde del desembarco
  for (final y in [0.0, w]) {
    members.add(Member(role: MemberRole.bracket, profile: brk, a: Vec3(0, y, hTop - 0.1), b: Vec3(off, y, hTop - 0.1)));
  }
  // Jaula de protección si la caída supera 3 m (aros cada ≤ 1,2 m desde 2,5 m)
  final cage = hTot > 3.0;
  var nHoops = 0;
  if (cage) {
    final hoop = _flatNamed('Pletina 50x8');
    final vbar = _flatNamed('Pletina 40x5');
    const r = 0.36, xc = off + 0.7 - r;
    final yc = w / 2;
    List<Vec3> ring(double z) {
      final pts = <Vec3>[Vec3(off, 0, z), Vec3(off, yc - r, z)];
      for (var i = 0; i <= 8; i++) {
        final a = -math.pi / 2 + math.pi * i / 8;
        pts.add(Vec3(xc + r * math.cos(a), yc + r * math.sin(a), z));
      }
      pts.addAll([Vec3(off, yc + r, z), Vec3(off, w, z)]);
      return pts;
    }

    const z0 = 2.5;
    final nh = math.max(1, ((hTop - z0) / 1.2).ceil());
    for (var i = 0; i <= nh; i++) {
      final z = z0 + (hTop - z0) * i / nh;
      final pts = ring(z);
      for (var k = 0; k < pts.length - 1; k++) {
        members.add(Member(role: MemberRole.frame, profile: hoop, a: pts[k], b: pts[k + 1]));
      }
      nHoops++;
    }
    final lo = ring(z0), hi = ring(hTop);
    for (final k in [1, 2, 4, 6, 8, 10, 11]) {
      final a = lo[k] + (lo[k + 1] - lo[k]) * (k == 1 ? 0.5 : 0);
      final b = hi[k] + (hi[k + 1] - hi[k]) * (k == 1 ? 0.5 : 0);
      members.add(Member(role: MemberRole.baluster, profile: vbar, a: a, b: b));
    }
  }

  final plates = <PlatePiece>[
    PlatePiece(mark: 'PA1', description: 'Pie de larguero (placa de apoyo)', w: 120, h: 120, t: 8, qty: 2, notes: '2 anclajes químicos M10'),
    PlatePiece(mark: 'SP', description: 'Placa de soporte a pared', w: 120, h: 80, t: 8, qty: (nBr + 1) * 2, notes: '2 anclajes químicos ${anc.$1}'),
  ];
  final bolts = <BoltItem>[
    BoltItem('Anclaje de pies', 'M10 varilla 8.8 + resina', 4, 'PA1'),
    BoltItem('Anclaje de soportes', '${anc.$1} varilla 8.8 + resina', (nBr + 1) * 4, 'SP a muro de hormigón o fábrica maciza'),
  ];
  final welds = <WeldSpec>[
    WeldSpec(joint: 'Peldaño – larguero (pasante)', type: 'En ángulo perimetral', throat: 3, lengthPerJoint: math.pi * rung.h, count: nR * 2),
    WeldSpec(joint: 'Soporte – larguero y placa', type: 'En ángulo', throat: 4, lengthPerJoint: 2 * brk.h, count: (nBr + 1) * 4),
    if (cage)
      WeldSpec(joint: 'Jaula: aros y pletinas verticales', type: 'En ángulo', throat: 3, lengthPerJoint: 40, count: nHoops * 9,
          process: '135 (MAG) hilo 0,8 mm', position: 'PA/PB taller'),
  ];
  final hyp = [
    ..._commonHypotheses(s),
    'Escala fija (de gato) de ${_f(hTot, 2)} m de subida y ${_f(w * 1000, 0)} mm entre largueros ${stile.name}, peldaños ${rung.name} cada ${_f(pitch * 1000, 0)} mm '
        'a ${_f(off * 1000, 0)} mm del paramento (EN ISO 14122-4).',
    'Largueros prolongados ${_f(ext, 2)} m sobre el desembarco como asidero; soportes a pared cada ${_f(lb, 2)} m.',
    'Carga de cálculo: 1,5 kN por peldaño y $users usuario${users > 1 ? 's' : ''} a la vez (uno por cada 6 m de subida).',
    if (cage)
      'Jaula de protección desde 2,50 m: $nHoops aros de pletina 50x8 (Ø libre 720 mm, a ≤ 1,2 m) y 7 pletinas verticales 40x5 (separación ≤ 300 mm).'
    else
      'Subida ≤ 3 m: no necesita jaula (EN ISO 14122-4).',
  ];
  final assembly = [
    'Replanteo en el paramento: verticalidad y posición del desembarco.',
    'Fabricación en taller de la escala (largueros taladrados, peldaños pasantes soldados) en tramos de ≤ 6 m.',
    'Anclaje de pies y soportes a pared; aplomado.',
    if (cage) 'Montaje de aros y pletinas verticales de la jaula.',
    'Puerta o cadena de seguridad en el desembarco; acabado (${s.finish}).',
  ];
  if (hTot > 6) warnings.add('Más de 6 m de subida: intercala plataformas de descanso o usa un sistema anticaídas (línea de vida vertical) según EN ISO 14122-4 / EN 353-1.');
  warnings.add('Para uso industrial o de mantenimiento; no es una escalera de evacuación ni de uso público.');
  warnings.add(_warnValidate());
  return Design(
    spec: s..length = off + (cage ? 0.7 : 0.1),
    prompt: prompt,
    members: members,
    plates: plates,
    bolts: bolts,
    welds: welds,
    checks: checks,
    hypotheses: hyp,
    assembly: assembly,
    warnings: warnings,
    footings: [Vec3(off, 0, 0), Vec3(off, w, 0)],
    footingSize: 0,
    frameX: [0, off],
    gridY: [0, w],
    ridgeHeight: hTop,
    surfaces: surfaces,
  );
}

// ---------------------------------------------------------------------------
// PASAMANOS A PARED
// ---------------------------------------------------------------------------

Design _designPasamanosPared(StructureSpec s, String prompt) {
  final g = s.grade, fy = g.fy;
  final lx = s.length, hr = s.height, ql = s.liveLoad;
  final checks = <Check>[];
  final warnings = <String>[...s.notes];
  final members = <Member>[];
  final t = normalize(prompt);
  final twoRails = RegExp(r'accesib|doble|minusvalid|silla de ruedas|movilidad reducida|dos alturas').hasMatch(t);
  const gapWall = 0.05; // separación libre al paramento (≥ 4 cm)
  final rail = _choose(chsTable.where((p) => p.h >= 33 && p.h <= 50).toList(), (p) {
    final sp = 1.2;
    final med = 1.5 * ql * sp * sp / 10 + 1.5 * 1.0 * sp / 6;
    return [
      Check('Pasamanos ${p.name}', 'Flexión: ${_f(ql, 1)} kN/m y 1 kN puntual entre soportes', med / _mRd(p, fy),
          'Soportes cada ≤ ${_f(sp, 2)} m, MEd = ${_f(med, 2)} kN·m'),
    ];
  }, checks);
  final nSp = math.max(1, (lx / 1.2).ceil());
  final sp = lx / nSp;
  final yAxis = gapWall + rail.h / 2000;
  final vEd = 1.5 * (ql * sp + 1.0);
  final mB = vEd * yAxis;
  final brk = roundTable.firstWhere((p) => p.h >= 16 && mB / _mRd(p, fy) <= _limit, orElse: () => roundTable.last);
  final anc = _anchorFor(mB / 0.03 + vEd / 2);
  checks.add(Check('Soporte ${brk.name}', 'Ménsula de ${_f(yAxis * 1000, 0)} mm', mB / _mRd(brk, fy), 'VEd = ${_f(vEd, 2)} kN, MEd = ${_f(mB, 3)} kN·m'));
  checks.add(Check('Anclaje ${anc.$1}', 'Tracción en la roseta (brazo 30 mm)', (mB / 0.03 + vEd / 2) / anc.$2,
      'NEd = ${_f(mB / 0.03 + vEd / 2, 2)} kN'));

  final heights = [hr, if (twoRails) 0.70];
  for (final z in heights) {
    // pared en y = 0; el pasamanos queda delante (y < 0)
    members.add(Member(role: MemberRole.handrail, profile: rail, a: Vec3(0, -yAxis, z), b: Vec3(lx, -yAxis, z)));
    // remates curvados hacia la pared
    members.add(Member(role: MemberRole.handrail, profile: rail, a: Vec3(0, -yAxis, z), b: Vec3(0, 0, z)));
    members.add(Member(role: MemberRole.handrail, profile: rail, a: Vec3(lx, -yAxis, z), b: Vec3(lx, 0, z)));
    for (var i = 0; i <= nSp; i++) {
      final x = (i * sp).clamp(0.1, lx - 0.1).toDouble();
      members.add(Member(role: MemberRole.bracket, profile: brk, a: Vec3(x, 0, z - 0.06), b: Vec3(x, -yAxis, z - rail.h / 2000)));
    }
  }
  final surfaces = [Surface(const Vec3(-0.3, 0.01, 0), Vec3(lx + 0.3, 0.01, 0), Vec3(lx + 0.3, 0.01, hr + 0.4), Vec3(-0.3, 0.01, hr + 0.4), SurfaceKind.wall)];
  final nBr = (nSp + 1) * heights.length;
  final plates = <PlatePiece>[
    PlatePiece(mark: 'RS', description: 'Roseta de soporte (Ø 60 mm)', w: 60, h: 60, t: 6, qty: nBr, notes: '2 anclajes ${anc.$1} (taco químico en fábrica hueca)'),
  ];
  final bolts = <BoltItem>[
    BoltItem('Anclaje de soportes', '${anc.$1} tornillo + taco (químico en ladrillo hueco)', nBr * 2, 'RS a muro'),
    BoltItem('Tapones / remates', 'Remate curvo soldado', heights.length * 2, 'Extremos del pasamanos'),
  ];
  final welds = <WeldSpec>[
    WeldSpec(joint: 'Soporte – pasamanos y roseta', type: 'En ángulo perimetral', throat: 3, lengthPerJoint: math.pi * brk.h, count: nBr * 2,
        process: '141 (TIG) en acabados vistos', position: 'PA/PB taller'),
  ];
  final hyp = [
    ..._commonHypotheses(s),
    'Pasamanos a pared de ${_f(lx, 2)} m, ${rail.name} a ${_f(hr, 2)} m${twoRails ? ' y otro a 0,70 m (accesibilidad)' : ''}, '
        'separado ${_f(gapWall * 100, 0)} cm del paramento, con soportes cada ${_f(sp, 2)} m.',
    'Empuje ${_f(ql, 1)} kN/m y 1 kN puntual (DB-SE-AE 3.2.1); soportes ${brk.name} con roseta y anclaje ${anc.$1}.',
    'CTE DB-SUA 1 §4.2.4: pasamanos firme y fácil de asir, a 0,90–1,10 m; en escaleras de ≥ 1,20 m de ancho, a ambos lados.',
    'Accesibilidad (DB-SUA 9): otro pasamanos a 0,65–0,75 m, prolongado 30 cm en los extremos y sin cortes en el recorrido.',
  ];
  final assembly = [
    'Replanteo de la altura sobre la línea de peldaños o el suelo y de los soportes.',
    'Curvado de remates y soldadura de soportes en taller; acabado.',
    'Taladro y anclaje de rosetas; presentación y nivelado del pasamanos.',
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
    footings: const [],
    footingSize: 0,
    frameX: [0, lx],
    gridY: [-yAxis, 0],
    ridgeHeight: hr,
    surfaces: surfaces,
  );
}

// ---------------------------------------------------------------------------
// REJA DE VENTANA
// ---------------------------------------------------------------------------

Design _designReja(StructureSpec s, String prompt) {
  final g = s.grade, fy = g.fy;
  final lx = s.length, hz = s.height;
  final checks = <Check>[];
  final warnings = <String>[...s.notes];
  final members = <Member>[];
  final t = normalize(prompt);
  final solid = RegExp(r'forja|macizo|seguridad|antirrobo|cuadradillo').hasMatch(t);
  final frame = _flatNamed('Pletina 40x8');
  final bar = solid ? roundTable.firstWhere((p) => p.h >= 16) : shsTable.first;
  final nCross = math.max<int>(1, (hz / 0.45).ceil() - 1); // pletinas horizontales intermedias
  final lBar = hz / (nCross + 1);
  final nBars = math.max<int>(1, (lx / 0.11).ceil() - 1);
  final gap = lx / (nBars + 1) - bar.b / 1000;
  checks.add(Check('Barrotes', 'Hueco libre ≤ 10 cm', gap / 0.10, '${_f(gap * 100)} cm entre barrotes'));
  final med = 1.5 * 1.0 * lBar / 4;
  checks.add(Check('Barrote ${bar.name}', 'Empuje o palanca de 1 kN en el centro', med / _mRd(bar, fy),
      'Luz entre pletinas ${_f(lBar, 2)} m, MEd = ${_f(med, 3)} kN·m'));
  final nG = 2 * math.max<int>(2, (hz / 0.6).ceil()) + (lx > 1.2 ? 2 : 0);
  final vG = 1.5 * 1.0 * 2 / nG + 0.3;
  checks.add(Check('Garras de empotrar', 'Arrancamiento y cortante (≈ 3 kN por garra recibida con mortero)', vG / 3.0,
      '$nG garras, VEd = ${_f(vG, 2)} kN por garra'));

  // Bastidor en el plano y = 0 (x = ancho del hueco, z = alto)
  final corners = [const Vec3(0, 0, 0), Vec3(lx, 0, 0), Vec3(lx, 0, hz), Vec3(0, 0, hz)];
  for (var i = 0; i < 4; i++) {
    members.add(Member(role: MemberRole.frame, profile: frame, a: corners[i], b: corners[(i + 1) % 4], webDir: const Vec3(0, 1, 0)));
  }
  for (var k = 1; k <= nCross; k++) {
    final z = hz * k / (nCross + 1);
    members.add(Member(role: MemberRole.rail, profile: frame, a: Vec3(0, 0, z), b: Vec3(lx, 0, z), webDir: const Vec3(0, 1, 0)));
  }
  for (var k = 1; k <= nBars; k++) {
    final x = lx * k / (nBars + 1);
    members.add(Member(role: MemberRole.baluster, profile: bar, a: Vec3(x, 0, 0), b: Vec3(x, 0, hz)));
  }
  for (var k = 0; k < nG; k++) {
    final left = k.isEven;
    final z = hz * ((k ~/ 2) + 1) / ((nG ~/ 2) + 1);
    final x = left ? 0.0 : lx;
    members.add(Member(role: MemberRole.bracket, profile: _flatNamed('Pletina 30x5'), a: Vec3(x, 0, z), b: Vec3(x + (left ? -0.08 : 0.08), 0, z)));
  }
  // muro alrededor del hueco
  const m = 0.35;
  final surfaces = [
    Surface(Vec3(-m, 0.03, -m), Vec3(lx + m, 0.03, -m), Vec3(lx + m, 0.03, 0), Vec3(-m, 0.03, 0), SurfaceKind.wall),
    Surface(Vec3(-m, 0.03, hz), Vec3(lx + m, 0.03, hz), Vec3(lx + m, 0.03, hz + m), Vec3(-m, 0.03, hz + m), SurfaceKind.wall),
    Surface(Vec3(-m, 0.03, 0), const Vec3(0, 0.03, 0), Vec3(0, 0.03, hz), Vec3(-m, 0.03, hz), SurfaceKind.wall),
    Surface(Vec3(lx, 0.03, 0), Vec3(lx + m, 0.03, 0), Vec3(lx + m, 0.03, hz), Vec3(lx, 0.03, hz), SurfaceKind.wall),
  ];
  final plates = <PlatePiece>[
    PlatePiece(mark: 'GA', description: 'Garra de empotrar (pletina 30x5 abierta en cola de milano)', w: 120, h: 30, t: 5, qty: nG,
        notes: 'Recibida con mortero de cemento o sustituida por anclaje químico M8'),
  ];
  final bolts = <BoltItem>[
    BoltItem('Fijación alternativa', 'M8 anclaje químico a la mocheta', nG, 'Si no se empotran garras'),
  ];
  final welds = <WeldSpec>[
    WeldSpec(joint: 'Bastidor (esquinas a inglete)', type: 'A tope / en ángulo', throat: 4, lengthPerJoint: 2 * frame.h, count: 4 + nCross * 2),
    WeldSpec(joint: 'Barrotes – bastidor y pletinas', type: 'En ángulo perimetral', throat: 3, lengthPerJoint: 4 * bar.b,
        count: nBars * (2 + nCross), process: '135 (MAG) hilo 0,8 mm', position: 'PA/PB taller'),
    WeldSpec(joint: 'Garras – bastidor', type: 'En ángulo', throat: 3, lengthPerJoint: 60, count: nG),
  ];
  final hyp = [
    ..._commonHypotheses(s),
    'Reja de ventana para un hueco de ${_f(lx, 2)} x ${_f(hz, 2)} m: bastidor ${frame.name}, $nBars barrotes ${solid ? 'macizos ' : ''}${bar.name} '
        'y $nCross pletina${nCross > 1 ? 's' : ''} horizontal${nCross > 1 ? 'es' : ''}.',
    'Hueco libre entre barrotes ≤ 10 cm (seguridad de niños y anti-intrusión).',
    'Fijación con $nG garras empotradas en la mocheta o anclajes químicos M8.',
  ];
  final assembly = [
    'Medir el hueco real entre mochetas (descontar 1 cm de holgura por lado).',
    'Fabricación en taller: bastidor, punzonado de pletinas y barrotes pasantes soldados.',
    'Abrir cajeados para las garras, presentar, nivelar y recibir con mortero (o anclaje químico).',
    'Acabado (${s.finish}).',
  ];
  warnings.add('Si es la única ventana de una estancia, valora hacer la reja practicable (abatible con cerradura) para poder salir en caso de incendio.');
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
    footings: const [],
    footingSize: 0,
    frameX: [0, lx],
    gridY: const [0, 0.05],
    ridgeHeight: hz,
    surfaces: surfaces,
  );
}
