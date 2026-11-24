// Comprensión local de la petición (Dart puro: la usan la app y la TUI).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../engine/intents.dart';
import '../engine/model.dart';
import '../engine/understanding.dart';
import 'local_text.dart';
import 'ort_core.dart';

/// Textos de referencia de cada tipología para los embeddings.
List<(StructureType, String)> intentPassages() => [
      for (final e in typeIntents.entries) ...[
        (e.key, 'passage: ${e.key.label}'),
        for (final x in e.value) (e.key, 'passage: $x'),
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

/// Comprensión con los modelos de [dir] (e5-small y Qwen3), sin depender de Flutter.
class ComprehensionEngine {
  ComprehensionEngine(this.dir);
  final String dir;

  List<(StructureType, Float32List)>? _index;
  String? _indexKey;

  bool get embedReady => ['e5s_model_int8.onnx', 'e5s_tokenizer.json', 'e5s_config.json']
      .every((f) => File('$dir${Platform.pathSeparator}$f').existsSync());

  bool reasonReady([String prefix = 'qwen3']) => ['_model_int8.onnx', '_tokenizer.json', '_config.json']
      .every((f) => File('$dir${Platform.pathSeparator}$prefix$f').existsSync());

  /// Embeddings de las frases de ejemplo, calculados una vez y guardados.
  Future<List<(StructureType, Float32List)>> _loadIndex(int threads, AiEngine engine) async {
    final passages = intentPassages();
    final key = '${_fnv(passages.map((p) => p.$2).join('\n'))}-${File('$dir/e5s_model_int8.onnx').lengthSync()}';
    if (_index != null && _indexKey == key) return _index!;
    final f = File('$dir${Platform.pathSeparator}intents_index.json');
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
    final v = await embedTexts(EmbedRequest(dir, [for (final p in passages) p.$2], threads: threads, engine: engine));
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
    final q = (await embedTexts(EmbedRequest(dir, ['query: ${prompt.trim()}'], threads: threads, engine: engine))).first;
    return rankTypes(q, index);
  }

  /// Lanza el LLM para leer la petición con la tipología ya decidida.
  LlmJob read(String prompt, StructureType type, void Function(String) onPartial,
          {String prefix = 'qwen3', int threads = 4, AiEngine engine = AiEngine.cpu}) =>
      startLlm(
        LlmRequest(modelDir: dir, prefix: prefix, prompt: llmChat(prompt, type), threads: threads, engine: engine),
        onPartial,
      );
}
