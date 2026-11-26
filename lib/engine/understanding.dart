import 'dart:convert';
import 'dart:math' as math;

import 'comprehension_aids.dart';
import 'material_catalog.dart';
import 'model.dart';
import 'parser.dart';
import 'reasoning.dart';
import 'spanish.dart';
import 'vocabulary.dart';

/// De dónde sale cada dato de la ficha de interpretación.
enum DataSource { text, deduced, ai, assumed, user }

extension DataSourceLabel on DataSource {
  String get label => switch (this) {
        DataSource.text => 'de tu texto',
        DataSource.deduced => 'deducido',
        DataSource.ai => 'leído por la IA',
        DataSource.assumed => 'valor habitual',
        DataSource.user => 'cambiado por ti',
      };
}

/// Resultado de la comprensión: especificación lista para calcular, con el
/// origen de cada dato y las explicaciones para el usuario.
class Understanding {
  final String prompt;
  final StructureType type;
  final DataSource typeSource;
  final List<(StructureType, double)> ranking; // similitud semántica (embeddings)
  final Map<String, dynamic>? llm; // ficha que devolvió el LLM
  final StructureSpec spec;
  final Map<String, DataSource> sources;
  final List<String> notes; // explicaciones (tipología, deducciones, avisos)
  final String enriched; // texto que se ha calculado (petición + datos añadidos)
  final List<Fact> facts; // cifras con su sentido leídas por reglas
  final List<String> warnings; // datos que no cuadran entre sí
  final List<Question> questions; // datos clave que faltan
  Understanding(this.prompt, this.type, this.typeSource, this.ranking, this.llm, this.spec, this.sources, this.notes,
      this.enriched, {this.facts = const [], this.warnings = const [], this.questions = const []});
}

/// Instrucciones del LLM. La tipología ya viene decidida en la respuesta.
String llmSystem() => 'Eres el asistente de una oficina técnica de estructuras metálicas. Lee la petición del '
    'cliente y completa la ficha JSON con lo que diga el texto. Omite lo que no diga.\n'
    'Campos: largo_m, ancho_m, alto_m (metros); cubierta (panel sándwich, chapa grecada, chapa ondulada, policarbonato, '
    'teja, vidrio, tramex, chapa lagrimada o sin cubierta); acero (S235JR, S275JR, S355JR, corten, inoxidable o aluminio); acabado '
    '(galvanizado, pintado o lacado); ubicacion (ciudad o provincia); uso (para qué es); carga_kg_m2; niveles.';

/// Ejemplos (petición, ficha) de serie que se dan al LLM antes de la petición
/// real cuando no se eligen por parecido.
final llmExamples = llmExamplePool.take(2).toList();

/// Mensaje del usuario: la petición, los datos que ya han leído las reglas
/// (extracción en dos pasos) y el glosario de los términos que usa.
String llmUser(String prompt) =>
    'Petición: ${prompt.trim()}${factsForLlm(readFacts(prompt))}${glossaryForLlm(prompt)}${materialsForLlm(prompt, max: 3)}';

/// Instrucciones y ejemplos resueltos (sin razonamiento).
String llmPrefix([List<(String, String)>? examples]) {
  final b = StringBuffer('<|im_start|>system\n${llmSystem()}<|im_end|>\n');
  for (final (q, a) in examples ?? llmExamples) {
    b.write('<|im_start|>user\n${llmUser(q)}<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n$a<|im_end|>\n');
  }
  return b.toString();
}

/// Conversación completa en el formato de chat de Qwen3, sin modo de
/// pensamiento y con la respuesta ya empezada con la tipología decidida.
String llmChat(String prompt, StructureType type, [List<(String, String)>? examples]) =>
    '${llmPrefix(examples ?? pickExamples(prompt, type))}<|im_start|>user\n${llmUser(prompt)}<|im_end|>\n'
    '<|im_start|>assistant\n<think>\n\n</think>\n\n${llmSeed(type)}';

/// Conversación para un LLM que razona (Qwen3-4B-Thinking): piensa en
/// castellano antes de rellenar la ficha. Termina en `<think>\n` y
/// [llmThinkStart]; al acabar de pensar se fuerza `</think>` y [llmSeed].
String llmThinkChat(String prompt, StructureType type, [List<(String, String)>? examples]) {
  final b = StringBuffer('<|im_start|>system\n${llmSystem()}\n$llmThinkHint<|im_end|>\n');
  for (final (q, a) in examples ?? pickExamples(prompt, type)) {
    b.write('<|im_start|>user\n${llmUser(q)}<|im_end|>\n<|im_start|>assistant\n$a<|im_end|>\n');
  }
  b.write('<|im_start|>user\n${llmUser(prompt)}<|im_end|>\n<|im_start|>assistant\n<think>\n$llmThinkStart');
  return b.toString();
}

/// Qué tiene que razonar el modelo antes de responder.
const llmThinkHint = 'Antes de responder, razona en castellano y en pocas líneas: qué medida es cada número, '
    'las unidades y qué dato no aparece. En naves y pórticos la luz es el ancho_m y el fondo o la longitud '
    'es el largo_m; alto_m es la altura libre o al alero. Luego escribe solo la ficha JSON.';

/// Comienzo forzado del razonamiento: así piensa en castellano y dato a dato.
const llmThinkStart = 'Razono en castellano, dato a dato:\n-';

/// Inicio forzado de la respuesta: la tipología ya está decidida.
String llmSeed(StructureType type) => '{"tipo": "${type.name}", "';

/// Extrae la ficha JSON de la respuesta del LLM (tolerante: cierra llaves y
/// comillas que falten, acepta comas decimales). [seed] es el inicio forzado.
Map<String, dynamic>? parseLlmJson(String text, [String seed = '']) {
  var s = (seed + text).trim();
  final start = s.indexOf('{');
  if (start < 0) return null;
  s = s.substring(start);
  var depth = 0, end = -1;
  var inStr = false;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == '"' && (i == 0 || s[i - 1] != '\\')) inStr = !inStr;
    if (inStr) continue;
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) {
        end = i;
        break;
      }
    }
  }
  if (end >= 0) {
    s = s.substring(0, end + 1);
  } else {
    if (inStr) s += '"';
    s = s.replaceAll(RegExp(r',\s*"[^"]*"?\s*:?\s*$'), '');
    s += '}' * math.max(1, depth);
  }
  s = s.replaceAllMapped(RegExp(r'(\d),(\d)'), (m) => '${m[1]}.${m[2]}');
  try {
    final j = jsonDecode(s);
    return j is Map<String, dynamic> ? j : null;
  } catch (_) {
    return null;
  }
}

double? _num(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '.').replaceAll(RegExp(r'[^\d.]'), ''));
  return null;
}

String _f(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 2).replaceAll('.', ',');

/// Valores en metros de las medidas que aparecen escritas en el texto.
Set<double> mentionedLengths(String prompt) {
  final t = normalize(prompt);
  final out = <double>{};
  for (final m in RegExp(r'(\d+(?:[.,]\d+)?)\s*(mm|cm|m(?:etros?|ts?)?)?(?![\d])').allMatches(t)) {
    final v = double.tryParse(m[1]!.replaceAll(',', '.'));
    if (v == null) continue;
    final u = m[2] ?? '';
    out.add(v);
    if (u == 'mm') out.add(v / 1000);
    if (u == 'cm') out.add(v / 100);
  }
  // números escritos con letra
  const words = {
    'uno': 1, 'dos': 2, 'tres': 3, 'cuatro': 4, 'cinco': 5, 'seis': 6, 'siete': 7, 'ocho': 8, 'nueve': 9,
    'diez': 10, 'once': 11, 'doce': 12, 'quince': 15, 'veinte': 20, 'treinta': 30, 'cuarenta': 40, 'cincuenta': 50,
  };
  for (final e in words.entries) {
    if (RegExp('(?<![a-z])${e.key}(?![a-z])').hasMatch(t)) out.add(e.value.toDouble());
  }
  return out;
}

bool _isMentioned(Set<double> m, double v) => m.any((x) => (x - v).abs() < 1e-6);

/// Para qué es: el verbo y su complemento dicen la tipología aunque el texto
/// nombre otra cosa («para subir al altillo» es una escalera, no un altillo).
const _purposes = <(String, StructureType)>[
  (r'(?:subir|bajar|acceder|llegar)\s+(?:a|al|a la|hasta|desde)(?![a-z])', StructureType.escalera),
  (r'(?:cruzar|atravesar|pasar)\s+(?:por\s+)?(?:encima|sobre|por arriba)|unir .{0,40}por arriba|de una nave a otra',
      StructureType.pasarela),
  (r'que no se caiga|no se caigan|evitar caidas|proteger (?:el|los) (?:borde|hueco)', StructureType.barandilla),
  (r'cerrar (?:la|el|mi|una|un) (?:finca|parcela|terreno|solar|patio|jardin|perimetro|huerta)|'
      r'(?:separar|delimitar) .{0,30}(?:finca|parcela|terreno|solar|jardin|huerta|vecino)|vallar', StructureType.valla),
  (r'(?:que|para que) se abra|(?:abrir|abra) .{0,25}para que (?:entre|entren|pasen|salgan)', StructureType.cancela),
  (r'(?:para|donde)\s+aparcar|dar sombra|'
      r'(?:proteger|cubrir|resguardar) (?:el|los|la|las|mi|mis) (?:coches?|vehiculos?|motos?|furgonetas?|caravanas?|autocaravanas?)',
      StructureType.marquesina),
  (r'(?:colgar|izar)\s|(?:elevar|levantar) (?:el |la |los |las )?(?:motor|motores|carga|cargas|pieza|piezas|peso)',
      StructureType.portico),
];

/// Tipología reconocida por palabras clave y por la finalidad, con el peso
/// de la palabra (0 si no hay).
(StructureType?, int) ruleType(String prompt) {
  final t = canonicalize(normalize(prompt));
  final (best, weight, at) = keywordType(t);
  for (final (re, ty) in _purposes) {
    final m = RegExp(re).firstMatch(t);
    // la finalidad manda si lo nombrado va detrás (es su complemento) o no hay nada
    if (m != null && (best == null || at > m.start)) return (ty, 10);
  }
  return (best, weight);
}

/// Frase con la que el intérprete entiende cada dato de la ficha.
String fieldPhrase(String field, Object value) {
  String m(Object v) => v is num ? _f(v.toDouble()) : '$v';
  return switch (field) {
    'length' => 'largo ${m(value)} m',
    'width' => 'ancho ${m(value)} m',
    'height' => 'altura ${m(value)} m',
    'roofing' => 'cubierta de $value',
    'cladding' => 'cerramiento de $value',
    'grade' => 'acero $value',
    'finish' => '$value',
    'city' => 'en $value',
    'use' => 'uso $value',
    'liveLoad' => 'sobrecarga ${m(value)} kg/m2',
    'levels' => '${m(value)} niveles',
    'variant' => 'variante $value',
    _ => '$value',
  };
}

/// ¿Aparece en el texto alguna palabra significativa (4+ letras) del valor?
bool _backedByText(String text, String value) {
  final words = normalize(value).split(RegExp(r'[^a-z0-9]+')).where((w) => w.length >= 4);
  return words.any((w) => RegExp('(?<![a-z])${RegExp.escape(w.length > 5 ? w.substring(0, w.length - 1) : w)}').hasMatch(text));
}

/// Junta el intérprete por reglas, la similitud semántica (embeddings), el
/// razonamiento de oficio y la ficha del LLM. Manda lo escrito en el texto;
/// lo que falta se deduce por oficio, luego se toma de la IA si el texto lo
/// respalda y, si no, queda el valor habitual de la tipología.
/// [overrides] son los cambios que hace el usuario en la ficha (campo -> valor).
Understanding understand(String prompt,
    {List<(StructureType, double)> ranking = const [],
    Map<String, dynamic>? llm,
    StructureType? forceType,
    Map<String, Object> overrides = const {}}) {
  final notes = <String>[];
  final text = spellNumbers(prompt);
  final fixes = spanishNote(normalize(prompt));
  if (fixes != null) notes.add(fixes);
  final (rType, rWeight) = ruleType(text);
  final eType = ranking.isEmpty ? null : ranking.first.$1;
  final eMargin = ranking.length > 1 ? ranking[0].$2 - ranking[1].$2 : 1.0;

  StructureType type;
  DataSource typeSource;
  if (forceType != null) {
    type = forceType;
    typeSource = DataSource.user;
  } else if (rType != null && (rWeight > 1 || eType == null || eType == rType || eMargin < 0.01)) {
    type = rType;
    typeSource = DataSource.text;
    if (eType != null && eType != rType) {
      notes.add('Por el significado también podría ser «${eType.label}»; se toma «${rType.label}» porque lo dice tu texto.');
    }
  } else if (eType != null && (rType != null || eMargin > 0.004)) {
    type = eType;
    typeSource = DataSource.ai;
    notes.add(rType == null
        ? 'Tipología reconocida por el significado de tu petición: «${type.label}».'
        : 'Tu texto usa una palabra genérica; por el significado se entiende «${type.label}».');
  } else {
    type = detectType(canonicalize(text), <String>[]);
    typeSource = DataSource.assumed;
    notes.add('No se reconoce la tipología en tu texto: se toma «${type.label}». Cámbiala arriba si no es.');
  }

  final orig = parsePrompt(text, type: type);
  final base = parsePrompt('', type: type);
  final said = mentionedLengths(text);
  final src = <String, DataSource>{};
  bool fromText(String field) => switch (field) {
        'length' => _isMentioned(said, orig.length),
        'width' => _isMentioned(said, orig.width),
        'height' => _isMentioned(said, orig.height),
        'roofing' => orig.roofing != base.roofing,
        'cladding' => orig.cladding != base.cladding,
        'grade' => orig.grade != base.grade,
        'finish' => orig.finish != base.finish,
        'city' => orig.snow != base.snow || orig.wind != base.wind,
        'use' => orig.use != base.use,
        'liveLoad' => orig.liveLoad != base.liveLoad,
        'levels' => orig.levels != base.levels && RegExp(r'\d+\s*(niveles|alturas|baldas|estantes|pisos|plantas|tramos)').hasMatch(text),
        'variant' => orig.variant != base.variant,
        _ => false,
      };
  const fields = ['length', 'width', 'height', 'roofing', 'cladding', 'grade', 'finish', 'city', 'use', 'liveLoad', 'levels', 'variant'];
  for (final f in fields) {
    if (fromText(f)) src[f] = DataSource.text;
  }

  final extra = <String>[];
  // 0) extracción en dos pasos: cifras con su sentido que el intérprete no ha leído
  final facts = readFacts(text);
  final fromFacts = <String>[];
  for (final f in facts) {
    final field = f.field;
    if (field == null || src[field] == DataSource.text || overrides.containsKey(field)) continue;
    if (field == 'height' && facts.any((o) => o.field == 'height' && o.value > f.value)) continue;
    extra.add(field == 'liveLoad' ? 'sobrecarga ${_f(f.value)} kg/m2' : fieldPhrase(field, f.value));
    src[field] = DataSource.text;
    fromFacts.add('${f.label} ${_f(f.value)} ${f.unit}');
  }
  if (fromFacts.isNotEmpty) notes.add('Leído de tu texto: ${fromFacts.join(', ')}.');
  // 1) cambios del usuario
  overrides.forEach((f, v) {
    extra.add(fieldPhrase(f, v));
    src[f] = DataSource.user;
  });
  // 2) razonamiento de oficio
  for (final d in tradeDeductions(text, type)) {
    if (src.containsKey(d.field)) continue;
    extra.add(d.phrase);
    src[d.field] = DataSource.deduced;
    notes.add(d.why);
  }
  // 3) ficha del LLM, solo con datos que respalda el texto
  if (llm != null) {
    double? n(String k) => _num(llm[k]);
    String? str(String k) {
      final v = llm[k];
      return v is String && v.trim().isNotEmpty && v.trim().toLowerCase() != 'null' ? v.trim() : null;
    }

    final cand = <String, Object?>{
      'length': n('largo_m'),
      'width': n('ancho_m'),
      'height': n('alto_m'),
      'roofing': str('cubierta'),
      'cladding': str('cerramiento'),
      'grade': str('acero'),
      'finish': str('acabado'),
      'city': str('ubicacion'),
      'use': str('uso'),
      'liveLoad': n('carga_kg_m2'),
      'levels': n('niveles'),
    };
    final ignored = <String>[];
    cand.forEach((f, v) {
      if (v == null || src.containsKey(f)) return;
      final ok = v is double ? v > 0 && _isMentioned(said, v) : _backedByText(text, v as String);
      if (!ok) {
        ignored.add(f);
        return;
      }
      extra.add(fieldPhrase(f, v));
      src[f] = DataSource.ai;
    });
    final read = src.entries.where((e) => e.value == DataSource.ai).map((e) => _fieldName[e.key]).toList();
    if (read.isNotEmpty) notes.add('La IA ha leído de tu texto: ${read.join(', ')}.');
    if (ignored.isNotEmpty) {
      notes.add('Se descartan datos que la IA proponía sin que estén en tu texto '
          '(${ignored.map((f) => _fieldName[f]).join(', ')}).');
    }
  }
  for (final f in fields) {
    src.putIfAbsent(f, () => DataSource.assumed);
  }
  final enriched = extra.isEmpty ? text : '$text, ${extra.join(', ')}';
  final spec = parsePrompt(enriched, type: type);
  final assumed = {for (final e in src.entries) if (e.value == DataSource.assumed) e.key};
  return Understanding(prompt, type, typeSource, ranking, llm, spec, src, notes, enriched,
      facts: facts, warnings: coherenceWarnings(spec, facts), questions: clarifyingQuestions(type, assumed));
}

const _fieldName = {
  'length': 'largo',
  'width': 'ancho',
  'height': 'alto',
  'roofing': 'cubierta',
  'cladding': 'cerramiento',
  'grade': 'acero',
  'finish': 'acabado',
  'city': 'ubicación',
  'use': 'uso',
  'liveLoad': 'sobrecarga',
  'levels': 'niveles',
  'variant': 'forma',
};
