import '../engine/model.dart';

/// Datos que el modelo de visión (VLM) describe de un croquis, en inglés,
/// traducidos al vocabulario del oficio.
class VisionHints {
  final StructureType? type;
  final List<double> dims; // metros, de mayor a menor
  final List<String> words; // cubierta / material en español
  final int? columns;
  const VisionHints(this.type, this.dims, this.words, this.columns);
  bool get isEmpty => type == null && dims.isEmpty && words.isEmpty;
}

const _typeWords = <String, StructureType>{
  'carport': StructureType.marquesina,
  'canopy': StructureType.marquesina,
  'awning': StructureType.marquesina,
  'shelter': StructureType.marquesina,
  'car park': StructureType.marquesina,
  'parking': StructureType.marquesina,
  'warehouse': StructureType.nave,
  'industrial building': StructureType.nave,
  'shed': StructureType.nave,
  'hangar': StructureType.nave,
  'barn': StructureType.nave,
  'gable': StructureType.nave,
  'staircase': StructureType.escalera,
  'stairs': StructureType.escalera,
  'stair': StructureType.escalera,
  'steps': StructureType.escalera,
  'railing': StructureType.barandilla,
  'handrail': StructureType.barandilla,
  'balustrade': StructureType.barandilla,
  'guardrail': StructureType.barandilla,
  'gate': StructureType.cancela,
  'mezzanine': StructureType.entreplanta,
  'platform': StructureType.entreplanta,
  'pergola': StructureType.marquesina,
  'footbridge': StructureType.pasarela,
  'walkway': StructureType.pasarela,
  'bridge': StructureType.pasarela,
  'tower': StructureType.torre,
  'truss': StructureType.cercha,
  'shelving': StructureType.estanteria,
  'shelf': StructureType.estanteria,
  'rack': StructureType.estanteria,
  'fence': StructureType.valla,
  'pole': StructureType.poste,
  'post': StructureType.poste,
  'mast': StructureType.poste,
  'portal frame': StructureType.portico,
  'frame': StructureType.portico,
};

const _numberWords = {'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'eight': 8};

/// Traduce la descripción del VLM a datos aprovechables. Busca primero las
/// palabras más específicas (carport antes que frame).
VisionHints visionHints(String text) {
  final t = text.toLowerCase();
  StructureType? typeIn(String x) {
    StructureType? type;
    var bestPos = 1 << 30;
    var bestLen = 0;
    for (final e in _typeWords.entries) {
      final m = RegExp('(?<![a-z])${RegExp.escape(e.key)}s?(?![a-z])').firstMatch(x);
      if (m == null) continue;
      // lo que aparece antes; a igualdad, la palabra más larga
      if (m.start < bestPos - 20 || (m.start < bestPos + 20 && e.key.length > bestLen)) {
        bestPos = m.start;
        bestLen = e.key.length;
        type = e.value;
      }
    }
    return type;
  }

  int kinds(String x) => {
        for (final e in _typeWords.entries)
          if (RegExp('(?<![a-z])${RegExp.escape(e.key)}s?(?![a-z])').hasMatch(x)) e.value
      }.length;

  // Si el modelo repite la lista de opciones de la pregunta, se usa la primera
  // frase que nombra una o dos tipologías.
  StructureType? type;
  if (kinds(t) >= 4) {
    for (final sentence in t.split(RegExp(r'[.;\n]'))) {
      final k = kinds(sentence);
      if (k >= 1 && k <= 2) {
        type = typeIn(sentence);
        break;
      }
    }
  } else {
    type = typeIn(t);
  }
  final dims = <double>[];
  for (final m in RegExp(r'(\d{1,3}(?:[.,]\d{1,2})?)\s*(mm|cm|m|meters|metres)?(?![\d])').allMatches(t)) {
    var v = double.tryParse(m[1]!.replaceAll(',', '.'));
    if (v == null) continue;
    final u = m[2];
    if (u == 'mm') v /= 1000;
    if (u == 'cm') v /= 100;
    if (u == null && !m[1]!.contains(RegExp('[.,]'))) continue; // enteros sueltos: recuentos, no cotas
    if (v >= 0.5 && v <= 80 && !dims.contains(v)) dims.add(v);
  }
  dims.sort((a, b) => b.compareTo(a));
  final words = <String>[];
  if (t.contains('sandwich')) {
    words.add('panel sándwich');
  } else if (t.contains('polycarbonate')) {
    words.add('policarbonato');
  } else if (t.contains('corrugated') || t.contains('metal sheet') || t.contains('steel sheet')) {
    words.add('chapa grecada');
  } else if (RegExp(r'(?<![a-z])tiles?(?![a-z])').hasMatch(t)) {
    words.add('teja');
  } else if (t.contains('glass')) {
    words.add('vidrio');
  }
  int? cols;
  final cm = RegExp(r'(\d+|one|two|three|four|five|six|eight)\s+(?:vertical\s+)?(?:columns|posts|pillars|legs)').firstMatch(t);
  if (cm != null) cols = int.tryParse(cm[1]!) ?? _numberWords[cm[1]!];
  return VisionHints(type, dims, words, cols);
}
