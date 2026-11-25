// Comprensión local de la petición (Dart puro: la usan la app y la TUI).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../engine/comprehension_aids.dart';
import '../engine/intents.dart';
import '../engine/model.dart';
import '../engine/understanding.dart';
import 'local_text.dart';
import 'ort_core.dart';

/// Textos de referencia de cada tipología para los embeddings ([prefix]:
/// lo que pide el modelo delante, «passage: » en e5).
List<(StructureType, String)> intentPassages([String prefix = 'passage: ']) => [
      for (final e in typeIntents.entries) ...[
        (e.key, '$prefix${e.key.label}'),
        for (final x in e.value) (e.key, '$prefix$x'),
      ]
    ];

/// Ordena las tipologías por parecido con la petición: media de las dos
/// frases de ejemplo más parecidas de cada una.
List<(StructureType, double)> rankTypes(Float32List q, List<(StructureType, Float32List)> index) {
  final sims = <StructureType, List<double>>{};
  for (final (t, v) in index) {
    sims.putIfAbsent(t, () => []).add(dot(q, v));
  }
  final out = <(StructureType, double)>[];
  sims.forEach((t, l) {
    l.sort((a, b) => b.compareTo(a));
    final k = l.length < 2 ? l.length : 2;
    out.add((t, l.take(k).reduce((a, b) => a + b) / k));
  });
  out.sort((a, b) => b.$2.compareTo(a.$2));
  return out;
}

int _fnv(String s) {
  var h = 0x811c9dc5;
  for (final b in utf8.encode(s)) {
    h = ((h ^ b) * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// LLM que razona antes de rellenar la ficha (Qwen3-4B-Thinking).
bool llmThinks(String prefix) => prefix == 'qwen3think';

/// Fichero ONNX del LLM de prefijo [prefix].
String llmModelFile(String prefix) => llmThinks(prefix) ? '${prefix}_model_q4.onnx' : '${prefix}_model_int8.onnx';

/// Comprensión con los modelos de [dir] (e5-small o jina-es) y de
/// [reasonDir] (Qwen3 0.6B o Qwen3-4B-Thinking), sin depender de Flutter.
class ComprehensionEngine {
  ComprehensionEngine(this.dir, {String? reasonDir, this.embed = e5Spec}) : reasonDir = reasonDir ?? dir;
  final String dir;
  final String reasonDir;
  final EmbedSpec embed;

  List<(StructureType, Float32List)>? _index;
  String? _indexKey;

  bool get embedReady => ['_model_int8.onnx', '_tokenizer.json', '_config.json']
      .every((f) => File('$dir${Platform.pathSeparator}${embed.prefix}$f').existsSync());

  bool reasonReady([String prefix = 'qwen3']) => [llmModelFile(prefix), '${prefix}_tokenizer.json', '${prefix}_config.json']
      .every((f) => File('$reasonDir${Platform.pathSeparator}$f').existsSync());

  /// Embeddings de las frases de ejemplo, calculados una vez y guardados
  /// (un índice por modelo: e5 y jina-es no se mezclan).
  Future<List<(StructureType, Float32List)>> _loadIndex(int threads, AiEngine engine) async {
    final passages = intentPassages(embed.passage);
    final model = File('$dir${Platform.pathSeparator}${embed.prefix}_model_int8.onnx');
    final key = '${embed.prefix}-${_fnv(passages.map((p) => p.$2).join('\n'))}-${model.lengthSync()}';
    if (_index != null && _indexKey == key) return _index!;
    final name = embed.prefix == 'e5s' ? 'intents_index.json' : 'intents_index_${embed.prefix}.json';
    final f = File('$dir${Platform.pathSeparator}$name');
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      if (j['key'] == key) {
        final v = (j['vectors'] as List)
            .map((e) => Float32List.fromList([for (final x in e as List) (x as num).toDouble()]))
            .toList();
        _index = [for (var i = 0; i < passages.length; i++) (passages[i].$1, v[i])];
        _indexKey = key;
        return _index!;
      }
    } catch (_) {}
    final v = await embedTexts(
        EmbedRequest(dir, [for (final p in passages) p.$2], prefix: embed.prefix, threads: threads, engine: engine));
    _index = [for (var i = 0; i < passages.length; i++) (passages[i].$1, v[i])];
    _indexKey = key;
    try {
      await f.writeAsString(jsonEncode({
        'key': key,
        'vectors': [for (final x in v) x.map((e) => double.parse(e.toStringAsFixed(5))).toList()],
      }));
    } catch (_) {}
    return _index!;
  }

  /// Tipologías ordenadas por parecido de significado.
  Future<List<(StructureType, double)>> rank(String prompt, {int threads = 4, AiEngine engine = AiEngine.cpu}) async {
    final index = await _loadIndex(threads, engine);
    final q = (await embedTexts(EmbedRequest(dir, ['${embed.query}${prompt.trim()}'],
            prefix: embed.prefix, threads: threads, engine: engine)))
        .first;
    return rankTypes(q, index);
  }

  /// Lanza el LLM para leer la petición con la tipología ya decidida.
  LlmJob read(String prompt, StructureType type, void Function(String) onPartial,
          {String prefix = 'qwen3',
          int threads = 4,
          AiEngine engine = AiEngine.cpu,
          List<(String, String)>? examples}) =>
      startLlm(
          llmRequestFor(reasonDir, prefix, prompt, type, threads: threads, engine: engine, examples: examples),
          onPartial);

  final Map<String, Float32List> _exampleVecs = {};

  /// Ejemplos para el LLM elegidos por parecido de significado con la petición (simétrico: ambos como consulta)
  /// (los vectores de los ejemplos se guardan para no recalcularlos).
  Future<List<(String, String)>> examplesFor(String prompt, StructureType type, List<(String, String)> pool,
      {int k = 3, int threads = 4, AiEngine engine = AiEngine.cpu}) async {
    if (pool.length <= k) return pool;
    final missing = [
      for (final (q, _) in pool)
        if (!_exampleVecs.containsKey(q)) q
    ];
    final texts = ['${embed.query}${prompt.trim()}', for (final q in missing) '${embed.query}$q'];
    final v = await embedTexts(EmbedRequest(dir, texts, prefix: embed.prefix, threads: threads, engine: engine));
    for (var i = 0; i < missing.length; i++) {
      _exampleVecs[missing[i]] = v[i + 1];
    }
    final q = v.first;
    return pickExamples(prompt, type, pool: pool, k: k, similarity: (e) => dot(q, _exampleVecs[e]!));
  }
}

/// Petición al LLM según el modelo: con razonamiento (Qwen3-4B-Thinking) piensa antes y
/// la ficha empieza al cerrar `</think>`; sin él, la ficha empieza ya.
LlmRequest llmRequestFor(String dir, String prefix, String prompt, StructureType type,
    {int threads = 4, AiEngine engine = AiEngine.cpu, List<(String, String)>? examples}) {
  if (!llmThinks(prefix)) {
    return LlmRequest(
        modelDir: dir, prefix: prefix, prompt: llmChat(prompt, type, examples), threads: threads, engine: engine);
  }
  return LlmRequest(
    modelDir: dir,
    prefix: prefix,
    modelFile: llmModelFile(prefix),
    prompt: llmThinkChat(prompt, type, examples),
    afterThink: llmSeed(type),
    thinkStart: llmThinkStart,
    thinkBudget: 384,
    threads: threads,
    engine: engine,
  );
}
