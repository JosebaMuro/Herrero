import 'dart:math' as math;

import '../engine/catalog.dart';
import '../engine/model.dart';
import '../engine/parser.dart';
import '../engine/vocabulary.dart';
import 'plan_token.dart';
import 'vision_hints.dart';

/// Dato detectado en el plano, para revisarlo antes de calcular.
class PlanFinding {
  final String label;
  final String value;
  final bool guessed; // deducido (no rotulado): conviene revisarlo
  const PlanFinding(this.label, this.value, {this.guessed = false});
}

class PlanAnalysis {
  final String prompt;
  final List<PlanFinding> findings;
  final List<String> warnings;
  final String rawText;
  const PlanAnalysis(this.prompt, this.findings, this.warnings, this.rawText);
}

String _f(double v) {
  if ((v - v.roundToDouble()).abs() < 1e-9) return v.round().toString();
  return v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll('.', ',');
}

/// Convierte los textos de un plano en una descripción para el intérprete.
/// [vision] es la descripción del croquis hecha por el VLM local (en inglés):
/// completa la tipología, las cotas o la cubierta que el texto no da.
PlanAnalysis analyzePlan(PlanReading r, {String? vision}) {
  final vh = vision == null || vision.trim().isEmpty ? null : visionHints(vision);
  final findings = <PlanFinding>[];
  final warnings = <String>[];

  // Texto ordenado por líneas (y) y columnas (x)
  final toks = [...r.tokens]..sort((a, b) {
      final dy = a.cy - b.cy;
      if (dy.abs() > math.max(a.h, b.h) * 0.5) return dy.sign.toInt();
      return a.x0.compareTo(b.x0);
    });
  final lines = <String>[];
  var line = StringBuffer();
  PlanToken? prev;
  for (final t in toks) {
    if (prev != null && (t.cy - prev.cy).abs() > math.max(t.h, prev.h) * 0.5) {
      lines.add(line.toString());
      line = StringBuffer();
    }
    if (line.isNotEmpty) line.write('  ');
    line.write(t.text);
    prev = t;
  }
  if (line.isNotEmpty) lines.add(line.toString());
  final raw = lines.join('\n');
  final norm = canonicalize(normalize(raw));

  // --- Tipología ---------------------------------------------------------
  StructureType? type;
  var bestScore = -1.0;
  for (final ty in typologies) {
    for (final e in ty.keywords.entries) {
      final m = RegExp('(?<![a-z])${RegExp.escape(e.key)}(?![a-z])').firstMatch(norm);
      if (m == null) continue;
      final score = e.value * 1000.0 + e.key.length * 10 - m.start * 0.01;
      if (score > bestScore) {
        bestScore = score;
        type = ty.type;
      }
    }
  }

  var typeByVision = false;
  if (type == null && vh?.type != null) {
    type = vh!.type;
    typeByVision = true;
  }

  // --- Unidades de las cotas --------------------------------------------
  String? unit;
  final um = RegExp(r'(?:cotas|medidas|unidades|dimensiones)\s*(?:en|:)?\s*(mm|cm|m)\b|\((mm|cm|m)\)').firstMatch(norm);
  if (um != null) unit = um[1] ?? um[2];

  // --- Cotas numéricas ----------------------------------------------------
  final numRe = RegExp(r'^\s*([+-]?)\s*(\d{1,6}(?:[.,]\d{1,3})?)\s*(mm|cm|m)?\s*$');
  final levelRe = RegExp(r'^\s*(?:n\s*)?([+-])\s*(\d{1,3}(?:[.,]\d{1,3})?)\s*(m)?\s*$');
  final dims = <(double, bool, String?)>[]; // (valor bruto, vertical, unidad)
  final levels = <double>[];
  for (final t in r.tokens) {
    final s = t.text.toLowerCase().replaceAll(' ', '');
    final lv = levelRe.firstMatch(s);
    if (lv != null && s.contains(RegExp(r'[.,]'))) {
      final v = double.parse(lv[2]!.replaceAll(',', '.')) * (lv[1] == '-' ? -1 : 1);
      levels.add(v);
      continue;
    }
    final m = numRe.firstMatch(s);
    if (m == null || m[1]!.isNotEmpty) continue;
    final txt = m[2]!;
    // 1.500 / 1,500 como miles en cotas en mm
    final v = RegExp(r'^\d{1,3}[.]\d{3}$').hasMatch(txt)
        ? double.parse(txt.replaceAll('.', ''))
        : double.parse(txt.replaceAll(',', '.'));
    if (v <= 0) continue;
    dims.add((v, t.vertical, m[3]));
  }
  // Unidad por defecto según el aspecto de las cifras
  if (unit == null && dims.isNotEmpty) {
    final ints = dims.where((d) => d.$1 % 1 == 0 && d.$3 == null).map((d) => d.$1).toList();
    final decs = dims.where((d) => d.$1 % 1 != 0 && d.$3 == null).length;
    if (ints.length > decs && ints.isNotEmpty) {
      ints.sort();
      final med = ints[ints.length ~/ 2];
      unit = med >= 300 ? 'mm' : (med >= 30 ? 'cm' : 'm');
    } else {
      unit = 'm';
    }
    findings.add(PlanFinding('Unidades de las cotas', unit, guessed: true));
  } else if (unit != null) {
    findings.add(PlanFinding('Unidades de las cotas', unit));
  }
  double toM(double v, String? u) {
    switch (u ?? unit) {
      case 'mm':
        return v / 1000;
      case 'cm':
        return v / 100;
      default:
        return v;
    }
  }

  final values = [
    for (final d in dims)
      if (toM(d.$1, d.$3) >= 0.3 && toM(d.$1, d.$3) <= 200) (toM(d.$1, d.$3), d.$2)
  ];

  // --- Dimensiones principales ---------------------------------------------
  double? length, width, bay, height, ridge;
  if (values.isNotEmpty) {
    final all = values.map((e) => e.$1).toList()..sort();
    length = all.last;
    final lVertical = values.firstWhere((e) => e.$1 == length).$2;
    final other = values.where((e) => e.$2 != lVertical).map((e) => e.$1).toList()..sort();
    // repetición -> modulación
    final counts = <double, int>{};
    for (final v in all) {
      final k = double.parse(v.toStringAsFixed(2));
      counts[k] = (counts[k] ?? 0) + 1;
    }
    final reps = counts.entries.where((e) => e.value >= 2 && e.key >= 1.5 && e.key < length!).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in reps) {
      final n = length / e.key;
      if ((n - n.round()).abs() < 0.04 && n.round() >= 2) {
        bay = e.key;
        break;
      }
    }
    if (other.isNotEmpty && other.last < length) {
      width = other.last;
    } else {
      final cand = all.reversed.where((v) => v < length! * 0.999 && v != bay).toList();
      if (cand.isNotEmpty) width = cand.first;
    }
  }

  // Sin cotas legibles: las que haya leído la visión (mayor = longitud,
  // menor = altura si es razonable, la intermedia = ancho)
  var dimsByVision = false;
  if (length == null && vh != null && vh.dims.isNotEmpty) {
    final d = vh.dims;
    length = d.first;
    if (d.length >= 3) {
      width = d[1];
    } else if (d.length == 2 && d[1] > 6) {
      width = d[1];
    }
    dimsByVision = true;
  }

  // Alturas rotuladas o por niveles (+5,00 / +7,10)
  final hm = RegExp(r'(?:altura(?: libre| al alero| de alero)?|alero|h\s*=|h libre)\s*(?:de|:|=)?\s*(\d+(?:\.\d+)?)\s*(mm|cm|m)?').firstMatch(norm);
  if (hm != null) {
    height = toM(double.parse(hm[1]!), hm[2]);
    findings.add(PlanFinding('Altura', '${_f(height)} m'));
  } else {
    final pos = levels.where((v) => v >= 1.8 && v <= 40).toList()..sort();
    if (pos.isNotEmpty) {
      height = pos.first;
      if (pos.length > 1 && pos.last > height + 0.2) ridge = pos.last;
      findings.add(PlanFinding('Altura (por cota de nivel)', '${_f(height)} m', guessed: true));
      if (ridge != null) findings.add(PlanFinding('Cumbrera (por cota de nivel)', '${_f(ridge)} m', guessed: true));
    }
  }
  if (height == null && dimsByVision && vh!.dims.length >= 2 && vh.dims.last <= 8 && vh.dims.last >= 1.8) {
    height = vh.dims.last;
    findings.add(PlanFinding('Altura (visión IA)', '${_f(height)} m', guessed: true));
  }

  // --- Datos rotulados ---------------------------------------------------
  final spec = parsePrompt(norm);
  final words = <String>[];
  if (RegExp(r'sandwich').hasMatch(norm)) {
    final e = RegExp(r'sandwich\D{0,12}(\d{2,3})\s*mm').firstMatch(norm);
    words.add('panel sándwich${e != null ? ' de ${e[1]} mm' : ''}');
  } else if (RegExp(r'chapa grecada').hasMatch(norm)) {
    words.add('chapa grecada');
  } else if (RegExp(r'policarbonato').hasMatch(norm)) {
    words.add('policarbonato');
  } else if (RegExp(r'(?<![a-z])teja').hasMatch(norm)) {
    words.add('teja');
  }
  if (RegExp(r'tramex').hasMatch(norm)) words.add('tramex');
  if (RegExp(r'lagrimada').hasMatch(norm)) words.add('chapa lagrimada');
  if (RegExp(r'colaborante').hasMatch(norm)) words.add('chapa colaborante');
  if (vh != null && !words.any((w) => w.startsWith('panel') || w.startsWith('chapa') || w == 'policarbonato' || w == 'teja')) {
    words.addAll(vh.words);
  }
  for (final f in ['galvanizado', 'lacado', 'corten', 'inox', 'aluminio']) {
    if (norm.contains(f)) words.add(f == 'inox' ? 'acero inoxidable' : f);
  }
  for (final g in ['s235', 's275', 's355']) {
    if (norm.contains(g)) words.add(g.toUpperCase());
  }
  final city = cityIn(norm);
  final slope = RegExp(r'pendiente\s*(?:de|del|:)?\s*(\d+(?:\.\d+)?)\s*(%|grados)').firstMatch(norm);

  // Perfiles rotulados y a qué parte pertenecen (misma línea)
  final profiles = <String>{};
  final parts = <String>[];
  const partWords = {
    'pilar': 'pilares', 'soporte': 'pilares', 'columna': 'pilares', 'viga': 'vigas', 'dintel': 'vigas',
    'correa': 'correas', 'tirante': 'tirantes', 'arriostr': 'arriostramientos', 'cruz': 'arriostramientos',
    'zanca': 'zancas', 'vigueta': 'viguetas', 'montante': 'montantes', 'poste': 'postes',
  };
  final profRe = RegExp(r'(?<![a-z])(ipe|heb|hea|hem|upn|upe|ipn|shs|rhs|chs|tubo|l)\s*(\d{2,3}(?:\s*x\s*\d{1,3}(?:[.,]\d)?){0,2})');
  for (final l in lines) {
    final ln = canonicalize(normalize(l));
    for (final m in profRe.allMatches(ln)) {
      if (m[1] == 'l' && !m[2]!.contains('x')) continue;
      final p = '${m[1]!.toUpperCase()} ${m[2]!.replaceAll(' ', '')}';
      profiles.add(p);
      for (final e in partWords.entries) {
        if (ln.contains(e.key)) {
          if (!parts.any((x) => x.startsWith('${e.value} '))) parts.add('${e.value} $p');
          break;
        }
      }
    }
  }

  // --- Composición del prompt -------------------------------------------------
  final ty = type ?? (width != null && width > 4 ? StructureType.nave : StructureType.marquesina);
  if (type == null) {
    warnings.add('El plano no nombra la tipología: se propone «${ty.label}». Cámbiala si no es correcta.');
  } else if (typeByVision) {
    warnings.add('La tipología la ha deducido la visión IA del dibujo: compruébala.');
  }
  if (dimsByVision) {
    warnings.add('Las medidas las ha leído la visión IA: revísalas con el croquis.');
  }
  findings.insert(0, PlanFinding(typeByVision ? 'Tipología (visión IA)' : 'Tipología', ty.label,
      guessed: type == null || typeByVision));
  final sb = StringBuffer(ty.label.split(' / ').first);
  if (length != null && width != null) {
    sb.write(' de ${_f(length)} x ${_f(width)} m');
    findings.add(PlanFinding('Dimensiones en planta', '${_f(length)} x ${_f(width)} m', guessed: true));
  } else if (length != null) {
    sb.write(' de ${_f(length)} m de longitud');
    findings.add(PlanFinding('Longitud', '${_f(length)} m', guessed: true));
  } else {
    warnings.add('No se han encontrado cotas legibles: escribe las medidas en la descripción.');
  }
  if (height != null) {
    sb.write(', ${ty.hasRoof ? 'altura al alero' : 'altura'} ${_f(height)} m');
  } else {
    warnings.add('No se ha encontrado la altura: añádela a la descripción.');
  }
  if (ridge != null && ty.hasRoof) sb.write(', altura a cumbrera ${_f(ridge)} m');
  if (bay != null) {
    sb.write(', ${ty == StructureType.cercha ? 'cerchas' : 'pórticos'} cada ${_f(bay)} m');
    findings.add(PlanFinding('Modulación', '${_f(bay)} m', guessed: true));
  }
  if (slope != null) {
    final sv = '${_f(double.parse(slope[1]!))} ${slope[2]}';
    sb.write(', pendiente $sv');
    findings.add(PlanFinding('Pendiente', sv));
  }
  if (words.isNotEmpty) {
    sb.write(', ${words.join(', ')}');
    findings.add(PlanFinding('Materiales y acabados', words.join(', ')));
  }
  if (parts.isNotEmpty) {
    sb.write(', ${parts.toSet().join(', ')}');
    findings.add(PlanFinding('Perfiles por parte', parts.toSet().join(', ')));
  } else if (profiles.isNotEmpty) {
    findings.add(PlanFinding('Perfiles rotulados', profiles.join(', ')));
  }
  if (spec.levels > 0 && (ty == StructureType.estanteria || ty == StructureType.torre)) {
    sb.write(', ${spec.levels} niveles');
  }
  if (city != null) {
    final name = city[0].toUpperCase() + city.substring(1);
    sb.write(', en $name');
    findings.add(PlanFinding('Emplazamiento', name));
  }
  if (r.tokens.length < 5) {
    warnings.add('Se ha leído muy poco texto. Si es una foto, acércate al plano y evita sombras y reflejos.');
  }
  return PlanAnalysis(sb.toString(), findings, warnings, raw);
}
