// Ayudas a la comprensión de la petición, sin modelos:
//  1. Extracción en dos pasos: las reglas leen cifras y unidades con su
//     sentido («24 m de luz», «7 m al alero», «500 kg por metro cuadrado») y el
//     LLM recibe esos datos ya leídos para interpretar solo lo dudoso.
//  2. Glosario del oficio: definiciones del diccionario de la app para los
//     términos que aparecen en la petición.
//  3. Ejemplos resueltos (few-shot) elegidos por parecido con la petición,
//     incluidos los que salen de las correcciones del usuario.
//  4. Comprobación de coherencia de la ficha.
//  5. Preguntas de aclaración cuando falta un dato clave.
import 'dart:convert';
import 'dart:math' as math;

import 'material_catalog.dart';
import 'model.dart';
import 'parser.dart';
import 'vocabulary.dart';

// ---------------------------------------------------------------------------
// 1. Datos leídos por reglas
// ---------------------------------------------------------------------------

/// Dato con su sentido leído del texto.
class Fact {
  final String label; // luz, fondo, alero, cumbrera, altura, separación, carga…
  final String? field; // campo de la ficha que fija (length, width, height, liveLoad) o null
  final double value;
  final String unit; // m, mm, kg/m2, %
  final String quote; // trozo del texto
  const Fact(this.label, this.field, this.value, this.unit, this.quote);

  String get line => unit.isEmpty ? '$label: «$quote»' : '$label: ${_fmt(value)} $unit («$quote»)';

  @override
  String toString() => line;
}

String _fmt(double v) =>
    v.toStringAsFixed(v % 1 == 0 ? 0 : ((v * 100 - (v * 100).round()).abs() < 1e-6 ? 2 : 3)).replaceAll('.', ',');

const _n = r'(\d+(?:[.,]\d+)?)';
const _m = r'\s*(?:m|mts?|metros?)?';

/// Patrón -> (etiqueta, campo, unidad). El número es el grupo 1.
final _factRules = <(RegExp, String, String?, String)>[
  (RegExp('$_n$_m\\s+de\\s+luz'), 'luz (ancho)', 'width', 'm'),
  (RegExp('luz\\s+(?:libre\\s+)?(?:de\\s+)?$_n'), 'luz (ancho)', 'width', 'm'),
  (RegExp('(?:por|x)\\s+$_n$_m\\s+de\\s+(?:fondo|largo|longitud|profundidad)'), 'fondo (largo)', 'length', 'm'),
  (RegExp('$_n$_m\\s+de\\s+(?:fondo|largo|longitud|profundidad)'), 'fondo (largo)', 'length', 'm'),
  (RegExp('$_n$_m\\s+de\\s+ancho'), 'ancho', 'width', 'm'),
  (RegExp('$_n$_m\\s+(?:al|de|en el|en)\\s+alero'), 'altura al alero', 'height', 'm'),
  (RegExp('alero\\s+(?:a|de|en)\\s+$_n'), 'altura al alero', 'height', 'm'),
  (RegExp('cumbrera\\s+(?:a|de|en)\\s+$_n'), 'altura a cumbrera', null, 'm'),
  (RegExp('$_n$_m\\s+(?:a|en)\\s+(?:la\\s+)?cumbrera'), 'altura a cumbrera', null, 'm'),
  (RegExp('a\\s+$_n$_m\\s+del\\s+suelo'), 'altura sobre el suelo', 'height', 'm'),
  (RegExp('$_n$_m\\s+de\\s+(?:alto|altura)(?:\\s+libre)?'), 'altura', 'height', 'm'),
  (RegExp('(?:parte\\s+)?(?:mas\\s+)?alta\\s+(?:que\\s+quede\\s+)?(?:a|de)\\s+$_n'), 'altura en la parte alta', 'height', 'm'),
  (RegExp('(?:parte\\s+)?(?:mas\\s+)?baja\\s+(?:que\\s+quede\\s+)?(?:a|de)\\s+$_n'), 'altura en la parte baja', null, 'm'),
  (RegExp('(?:porticos|cerchas|pilares|vanos)\\s+cada\\s+$_n'), 'separación entre pórticos', null, 'm'),
  (RegExp('$_n\\s*(?:kg|kilos?)\\s*(?:/\\s*m2|/\\s*m²|por\\s+metro\\s+cuadrado|por\\s+m2|el\\s+metro\\s+cuadrado|/m)'),
      'carga de uso', 'liveLoad', 'kg/m2'),
  (RegExp('$_n\\s*%\\s*(?:de\\s+)?(?:pendiente|caida)'), 'pendiente', null, '%'),
  (RegExp('pendiente\\s+(?:del?\\s+)?$_n\\s*%'), 'pendiente', null, '%'),
  (RegExp('(?:panel|sandwich|chapa)[a-z ]{0,20}?\\s+de\\s+$_n\\s*mm'), 'espesor de la cubierta', null, 'mm'),
];

/// Medidas «A por B» o «A x B» sin decir cuál es cuál.
final _pair = RegExp('$_n$_m\\s*(?:por|x)\\s*$_n$_m(?!\\s+de\\s+(?:fondo|largo|longitud|luz|ancho|alto))');

/// Lee del texto los datos con su sentido (sin repetir el mismo trozo).
List<Fact> readFacts(String prompt) {
  final raw = normalize(prompt);
  // las secciones de perfil («llanta de 30x5 mm») no son medidas de la estructura
  final t = maskSections(raw);
  final out = <Fact>[];
  final used = <int>{};
  for (final m in RegExp(r'(?<![a-z])(llantas?|pletinas?|liston(?:es)?|tubos?|angular(?:es)?|cuadradillos?|redondos?|perfil(?:es)?)'
          r'[a-z ]{0,20}?(\d+(?:[.,]\d+)?\s*x\s*\d+(?:[.,]\d+)?(?:\s*x\s*\d+(?:[.,]\d+)?)?)\s*(?:mm)?')
      .allMatches(raw)) {
    out.add(Fact('sección de ${m[1]} (no es medida de la estructura)', null, 0, '', m[0]!.trim()));
  }
  final rail = readParapetRail(raw);
  if (rail != null) {
    out.add(Fact('altura que sobresale por fuera del peto', null, rail.outer * 1000, 'mm', 'altura exterior'));
    out.add(Fact('altura de la cara interior (alto_m de la pieza)', 'height', rail.inner, 'm', 'interior'));
    out.add(Fact('vuelo hacia el interior', null, rail.depth * 1000, 'mm', 'hacia el interior'));
  }
  double num(String s) => double.parse(s.replaceAll(',', '.'));
  for (final (re, label, field, unit) in _factRules) {
    for (final m in re.allMatches(t)) {
      final at = m.start + m[0]!.indexOf(m[1]!);
      if (!used.add(at)) continue;
      out.add(Fact(label, field, num(m[1]!), unit, m[0]!.trim()));
    }
  }
  for (final m in _pair.allMatches(t)) {
    final a = m.start + m[0]!.indexOf(m[1]!);
    if (used.contains(a)) continue;
    used.add(a);
    final x = num(m[1]!), y = num(m[2]!);
    out.add(Fact('medidas en planta (mayor = largo)', null, math.max(x, y), 'm', m[0]!.trim()));
  }
  return out;
}

/// Texto de los datos ya leídos para el LLM (vacío si no hay).
String factsForLlm(List<Fact> facts) => facts.isEmpty
    ? ''
    : '\nDatos ya leídos por la app (úsalos tal cual):\n${facts.map((f) => '- ${f.line}').join('\n')}';

// ---------------------------------------------------------------------------
// 2. Glosario del oficio
// ---------------------------------------------------------------------------

/// Términos clave del cálculo que el modelo confunde, aunque no estén en el
/// diccionario de la app con esta redacción.
const _coreTerms = <(String, String)>[
  ('luz', 'distancia libre entre apoyos de un pórtico o viga: es el ancho (ancho_m)'),
  ('fondo', 'longitud de la nave en el sentido de los pórticos: es el largo (largo_m)'),
  ('alero', 'borde bajo de la cubierta; «al alero» es la altura de los pilares (alto_m)'),
  ('cumbrera', 'punto más alto de la cubierta a dos aguas; no es alto_m'),
  ('portico', 'pilares y dintel que se repiten a lo largo de la nave; «cada 5 m» es su separación'),
  ('tramex', 'rejilla electrosoldada para suelos: en altillos y pasarelas va en «cubierta»'),
  ('sobrecarga', 'carga de uso en kg/m² (carga_kg_m2)'),
  ('altillo', 'entreplanta: alto_m es la altura del suelo del altillo'),
];

/// Definiciones de los términos que aparecen en la petición (como mucho [max]).
List<(String, String)> glossaryFor(String prompt, {int max = 6}) {
  final t = ' ${normalize(prompt)} ';
  bool has(String w) {
    final k = normalize(w);
    return k.length >= 3 && RegExp('(?<![a-z])${RegExp.escape(k)}').hasMatch(t);
  }

  final out = <(String, String)>[];
  for (final (w, d) in _coreTerms) {
    if (has(w)) out.add((w, d));
  }
  // lo que ya explica el catálogo de materiales no se repite en el glosario
  final mats = materialsIn(prompt);
  for (final g in glossary) {
    if (out.length >= max) break;
    if (mats.isNotEmpty && materialsIn(g.term).any(mats.contains)) continue;
    // «Cordón superior / inferior» -> «cordón superior», «cordón inferior» (no «inferior» suelto)
    final split = g.term.split(RegExp(r'\s*/\s*'));
    final head = split.first.split(' ');
    final names = [
      for (final p in split) head.length > 1 && !p.contains(' ') && p != split.first ? '${head.first} $p' : p,
      ...g.aka,
    ].where((w) => w.length >= 4);
    if (out.any((e) => normalize(e.$1) == normalize(g.term))) continue;
    if (names.any(has)) {
      final m = g.meaning.split(RegExp(r'(?<=\.)\s')).first;
      out.add((g.term, m.length > 140 ? '${m.substring(0, 137)}…' : m));
    }
  }
  return out.take(max).toList();
}

String glossaryForLlm(String prompt) {
  final g = glossaryFor(prompt);
  return g.isEmpty ? '' : '\nGlosario del oficio:\n${g.map((e) => '- ${e.$1}: ${e.$2}').join('\n')}';
}

// ---------------------------------------------------------------------------
// 3. Ejemplos resueltos
// ---------------------------------------------------------------------------

/// Ejemplos (petición, ficha) para enseñar al LLM. Se eligen los más
/// parecidos a la petición; las correcciones del usuario se añaden aquí.
const llmExamplePool = <(String, String)>[
  (
    'Quiero un tejadillo para meter 3 coches en mi casa de Burgos, que no pase de 2,5 de alto',
    '{"tipo": "marquesina", "largo_m": 7.5, "ancho_m": 5, "alto_m": 2.5, "ubicacion": "Burgos", '
        '"uso": "aparcamiento de 3 coches"}'
  ),
  (
    'altillo de ocho por cuatro metros para oficina, con suelo de tramex y todo galvanizado',
    '{"tipo": "entreplanta", "largo_m": 8, "ancho_m": 4, "cubierta": "tramex", "acabado": "galvanizado", '
        '"uso": "oficina"}'
  ),
  (
    'nave de 20 m de luz y 50 de fondo, pórticos cada 6 m, 8 m al alero y cumbrera a 10, chapa grecada, en Soria',
    '{"tipo": "nave", "largo_m": 50, "ancho_m": 20, "alto_m": 8, "cubierta": "chapa grecada", "ubicacion": "Soria"}'
  ),
  (
    'plataforma de 5 x 3 a 2,8 m del suelo para maquinaria de 750 kg/m2, en acero S355',
    '{"tipo": "entreplanta", "largo_m": 5, "ancho_m": 3, "alto_m": 2.8, "carga_kg_m2": 750, "acero": "S355JR", '
        '"uso": "maquinaria"}'
  ),
  (
    'pérgola de 4 por 3 en la terraza, la parte alta a 2,7 y la baja a 2,3, policarbonato y lacada en blanco',
    '{"tipo": "marquesina", "largo_m": 4, "ancho_m": 3, "alto_m": 2.7, "cubierta": "policarbonato", '
        '"acabado": "lacado", "uso": "terraza"}'
  ),
  (
    'estantería para palets de 9 m de largo con 4 niveles y 1000 kg por nivel',
    '{"tipo": "estanteria", "largo_m": 9, "niveles": 4, "uso": "palets"}'
  ),
  (
    'pasarela de 12 m entre dos naves, 1,5 de ancho, a 4 m de altura, suelo de tramex galvanizado',
    '{"tipo": "pasarela", "largo_m": 12, "ancho_m": 1.5, "alto_m": 4, "cubierta": "tramex", "acabado": "galvanizado"}'
  ),
  (
    'escalera recta para subir 3,2 m al altillo, de 1 m de ancho, pintada',
    '{"tipo": "escalera", "alto_m": 3.2, "ancho_m": 1, "acabado": "pintado", "uso": "acceso al altillo"}'
  ),
];

int _sharedWords(String a, String b) {
  Set<String> w(String s) => normalize(s).split(RegExp(r'[^a-z0-9]+')).where((x) => x.length >= 4).toSet();
  return w(a).intersection(w(b)).length;
}

/// Los [k] ejemplos más parecidos a [prompt]: por [similarity] (embeddings)
/// si se da, si no por palabras en común; la tipología igual suma.
List<(String, String)> pickExamples(String prompt, StructureType type,
    {List<(String, String)> pool = llmExamplePool, int k = 3, double Function(String example)? similarity}) {
  if (pool.length <= k) return pool;
  double score((String, String) e) {
    final sameType = e.$2.contains('"tipo": "${type.name}"') ? 1.0 : 0.0;
    final s = similarity != null ? similarity(e.$1) : _sharedWords(prompt, e.$1) / 6;
    return s + 0.3 * sameType;
  }

  final scored = [for (final e in pool) (e, score(e))]..sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final s in scored.take(k)) s.$1];
}

// ---------------------------------------------------------------------------
// 4. Coherencia y 5. preguntas de aclaración
// ---------------------------------------------------------------------------

/// Avisos de datos que no cuadran entre sí.
List<String> coherenceWarnings(StructureSpec s, List<Fact> facts) {
  final w = <String>[];
  double? f(String label) => facts.where((x) => x.label.startsWith(label)).map((x) => x.value).firstOrNull;
  final ridge = f('altura a cumbrera'), eave = f('altura al alero');
  if (ridge != null && eave != null && ridge <= eave) {
    w.add('La cumbrera (${_fmt(ridge)} m) queda por debajo o igual que el alero (${_fmt(eave)} m): revisa las alturas.');
  }
  final low = f('altura en la parte baja'), high = f('altura en la parte alta');
  if (low != null && high != null && low > high) {
    w.add('La parte baja (${_fmt(low)} m) es más alta que la alta (${_fmt(high)} m): ¿están cambiadas?');
  }
  if (s.type == StructureType.nave && s.width > s.length * 1.2 && s.length > 0) {
    w.add('La luz (${_fmt(s.width)} m) es mayor que el fondo (${_fmt(s.length)} m), lo que es raro en una nave: '
        '¿están cambiados largo y ancho?');
  }
  if ((s.type == StructureType.marquesina) && s.height > 6) {
    w.add('Una marquesina de ${_fmt(s.height)} m de alto es poco habitual: comprueba la altura.');
  }
  if (s.type == StructureType.entreplanta && s.height > 0 && (s.height < 2.1 || s.height > 6)) {
    w.add('Un altillo a ${_fmt(s.height)} m del suelo es poco habitual (lo normal es 2,5–4 m).');
  }
  if (s.liveLoad > 15) {
    w.add('La sobrecarga de ${_fmt(s.liveLoad * 100)} kg/m² es muy alta: confirma la carga.');
  }
  if (s.length <= 0 || s.width <= 0 || s.height <= 0) {
    w.add('Hay medidas a cero: completa largo, ancho y alto.');
  }
  return w;
}

/// Pregunta para un dato clave que no dice el texto.
class Question {
  final String field; // campo de la ficha
  final String text;
  final List<(String, Object)> options; // (etiqueta, valor para la ficha)
  const Question(this.field, this.text, this.options);
}

const _roofOptions = <(String, Object)>[
  ('Chapa grecada', 'chapa grecada'),
  ('Panel sándwich', 'panel sándwich'),
  ('Policarbonato', 'policarbonato'),
  ('Sin cubierta', 'sin cubierta'),
];
const _loadOptions = <(String, Object)>[
  ('200 kg/m² (oficina, trastero)', 200.0),
  ('300 kg/m² (almacén ligero)', 300.0),
  ('500 kg/m² (almacén)', 500.0),
  ('750 kg/m² (maquinaria)', 750.0),
];
const _finishOptions = <(String, Object)>[
  ('Galvanizado', 'galvanizado'),
  ('Pintado', 'pintado'),
  ('Lacado', 'lacado'),
];

/// Preguntas por los datos clave que se han supuesto ([assumed]: campos con
/// valor habitual). Como mucho tres, las más importantes primero.
List<Question> clarifyingQuestions(StructureType type, Set<String> assumed) {
  final q = <Question>[];
  final roofed = type == StructureType.nave || type == StructureType.marquesina || type == StructureType.cercha;
  final floored = type == StructureType.entreplanta || type == StructureType.pasarela;
  if (floored && assumed.contains('liveLoad')) {
    q.add(const Question('liveLoad', '¿Qué carga tendrá encima?', _loadOptions));
  }
  if (roofed && assumed.contains('roofing')) {
    q.add(const Question('roofing', '¿De qué será la cubierta?', _roofOptions));
  }
  if (assumed.contains('finish')) {
    q.add(const Question('finish', '¿Qué acabado lleva el acero?', _finishOptions));
  }
  return q.take(3).toList();
}

// ---------------------------------------------------------------------------
// 6. Aprender de las correcciones
// ---------------------------------------------------------------------------

/// Ficha JSON (formato del LLM) con los datos que el usuario ha dado por buenos.
String fichaJson(StructureType type, Map<String, Object> values) {
  const keys = {
    'length': 'largo_m',
    'width': 'ancho_m',
    'height': 'alto_m',
    'roofing': 'cubierta',
    'grade': 'acero',
    'finish': 'acabado',
    'city': 'ubicacion',
    'use': 'uso',
    'liveLoad': 'carga_kg_m2',
    'levels': 'niveles',
  };
  final m = <String, Object>{'tipo': type.name};
  values.forEach((f, v) {
    final k = keys[f];
    if (k == null) return;
    if (v is String && v.trim().isEmpty) return;
    m[k] = v is double && v % 1 == 0 ? v.toInt() : v;
  });
  return jsonEncode(m).replaceAll('":', '": ').replaceAll(',"', ', "');
}
