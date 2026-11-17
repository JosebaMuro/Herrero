import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:onnxruntime/onnxruntime.dart';

import 'accel.dart';
import 'bpe_tokenizer.dart';
import 'ort_util.dart';

String _p(String dir, String f) => '$dir${Platform.pathSeparator}$f';

// ---------------------------------------------------------------------------
// Tokenizador SentencePiece Unigram (XLM-R, el de multilingual-e5)
// ---------------------------------------------------------------------------

class UnigramTokenizer {
  final Map<String, int> _ids;
  final List<double> _scores;
  final int unkId, bosId, eosId, maxPiece;
  final double _unkScore;
  UnigramTokenizer._(this._ids, this._scores, this.unkId, this.bosId, this.eosId, this.maxPiece, this._unkScore);

  static Future<UnigramTokenizer> fromFile(String path) async =>
      fromJson(jsonDecode(await File(path).readAsString()) as Map<String, dynamic>);

  static UnigramTokenizer fromJson(Map<String, dynamic> j) {
    final m = j['model'] as Map<String, dynamic>;
    final vocab = m['vocab'] as List;
    final ids = <String, int>{};
    final scores = <double>[];
    var maxLen = 1;
    var minScore = 0.0;
    for (var i = 0; i < vocab.length; i++) {
      final e = vocab[i] as List;
      final piece = e[0] as String;
      final sc = (e[1] as num).toDouble();
      ids[piece] = i;
      scores.add(sc);
      final n = piece.runes.length;
      if (n > maxLen) maxLen = n;
      if (sc < minScore) minScore = sc;
    }
    return UnigramTokenizer._(ids, scores, (m['unk_id'] as num?)?.toInt() ?? 3, ids['<s>'] ?? 0, ids['</s>'] ?? 2,
        math.min(maxLen, 24), minScore - 10);
  }

  /// Equivalencias NFKC de los caracteres de compatibilidad que aparecen en
  /// peticiones (fracciones, superíndices de m², ligaduras, ordinales).
  static const _nfkc = {
    '½': '1⁄2', '¼': '1⁄4', '¾': '3⁄4', '²': '2', '³': '3', '¹': '1', 'ﬁ': 'fi', 'ﬂ': 'fl', 'º': 'o', 'ª': 'a',
    '…': '...', '\u00a0': ' ', '\u2009': ' ', '\u202f': ' ',
  };

  /// Ids con <s> ... </s>, como el post-procesador de Hugging Face.
  List<int> encode(String text) {
    var t = text.replaceAll(RegExp(r'[\n\r\t]'), ' ');
    t = t.split('').map((c) => _nfkc[c] ?? c).join().replaceAll(RegExp(' {2,}'), ' ');
    t = BpeTokenizer.composeNfc(t);
    final out = <int>[bosId];
    // Metaspace: espacios -> ▁ y una palabra por cada ▁
    final s = '▁${t.replaceAll(' ', '▁')}';
    final words = RegExp('▁[^▁]*').allMatches(s).map((m) => m[0]!);
    for (final w in words) {
      out.addAll(_viterbi(w));
    }
    out.add(eosId);
    return out;
  }

  List<int> _viterbi(String word) {
    final ch = word.runes.map(String.fromCharCode).toList();
    final n = ch.length;
    final best = List<double>.filled(n + 1, -double.infinity);
    final from = List<int>.filled(n + 1, -1);
    final tok = List<int>.filled(n + 1, -1);
    best[0] = 0;
    for (var i = 0; i < n; i++) {
      if (best[i] == -double.infinity) continue;
      var piece = '';
      var matched = false;
      for (var len = 1; len <= maxPiece && i + len <= n; len++) {
        piece += ch[i + len - 1];
        final id = _ids[piece];
        if (id == null) continue;
        if (len == 1) matched = true;
        final sc = best[i] + _scores[id];
        if (sc > best[i + len]) {
          best[i + len] = sc;
          from[i + len] = i;
          tok[i + len] = id;
        }
      }
      if (!matched) {
        final sc = best[i] + _unkScore;
        if (sc > best[i + 1]) {
          best[i + 1] = sc;
          from[i + 1] = i;
          tok[i + 1] = unkId;
        }
      }
    }
    final ids = <int>[];
    for (var k = n; k > 0; k = from[k]) {
      ids.add(tok[k]);
    }
    final r = ids.reversed.toList();
    // une desconocidos seguidos, como fuse_unk
    final fused = <int>[];
    for (final id in r) {
      if (id == unkId && fused.isNotEmpty && fused.last == unkId) continue;
      fused.add(id);
    }
    return fused;
  }
}

// ---------------------------------------------------------------------------
// Embeddings de frases (multilingual-e5-small): media de la última capa
// ---------------------------------------------------------------------------

class EmbedRequest {
  final String modelDir;
  final String prefix;
  final List<String> texts; // con su prefijo e5: 'query: ' o 'passage: '
  final int threads;
  final AiEngine engine;
  const EmbedRequest(this.modelDir, this.texts, {this.prefix = 'e5s', this.threads = 2, this.engine = AiEngine.cpu});
}

/// Calcula los embeddings normalizados (síncrono; llamar en un isolate).
Future<List<Float32List>> runEmbedSync(EmbedRequest req) async {
  OrtEnv.instance.init();
  final tok = await UnigramTokenizer.fromFile(_p(req.modelDir, '${req.prefix}_tokenizer.json'));
  final cfg = jsonDecode(await File(_p(req.modelDir, '${req.prefix}_config.json')).readAsString()) as Map;
  final hidden = (cfg['hidden_size'] as num).toInt();
  final s = ortOpen(_p(req.modelDir, '${req.prefix}_model_int8.onnx'), req.threads, req.engine);
  final ro = OrtRunOptions();
  final out = <Float32List>[];
  try {
    for (final t in req.texts) {
      var ids = tok.encode(t);
      if (ids.length > 512) ids = [...ids.take(511), tok.eosId];
      final n = ids.length;
      final inputs = <String, OrtValue>{
        'input_ids': OrtValueTensor.createTensorWithDataList(Int64List.fromList(ids), [1, n]),
        'attention_mask': OrtValueTensor.createTensorWithDataList(Int64List.fromList(List.filled(n, 1)), [1, n]),
        if (s.inputNames.contains('token_type_ids'))
          'token_type_ids': OrtValueTensor.createTensorWithDataList(Int64List(n), [1, n]),
      };
      final r = s.run(ro, inputs);
      for (final v in inputs.values) {
        v.release();
      }
      final h = ortFloats(r[0]!, n * hidden);
      for (final o in r) {
        o?.release();
      }
      final v = Float32List(hidden);
      for (var i = 0; i < n; i++) {
        for (var k = 0; k < hidden; k++) {
          v[k] += h[i * hidden + k];
        }
      }
      var norm = 0.0;
      for (var k = 0; k < hidden; k++) {
        norm += v[k] * v[k];
      }
      norm = math.sqrt(norm);
      for (var k = 0; k < hidden; k++) {
        v[k] /= norm;
      }
      out.add(v);
    }
  } finally {
    s.release();
    ro.release();
  }
  return out;
}

/// Embeddings en un isolate aparte.
Future<List<Float32List>> embedTexts(EmbedRequest req) =>
    Isolate.run(() => ortWithCpuFallback(req.engine, () => runEmbedSync(req)));

double dot(Float32List a, Float32List b) {
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += a[i] * b[i];
  }
  return s;
}

// ---------------------------------------------------------------------------
// LLM pequeño (Qwen3) con caché KV y decodificación voraz
// ---------------------------------------------------------------------------

class LlmRequest {
  final String modelDir;
  final String prefix; // qwen3 (0.6B) o qwen3big (1.7B)
  final String prompt; // conversación completa ya formateada
  final int maxTokens;
  final int threads;
  final AiEngine engine;
  final bool stopAtJsonEnd; // corta al cerrar el objeto JSON abierto por el prompt
  const LlmRequest({
    required this.modelDir,
    this.prefix = 'qwen3',
    required this.prompt,
    this.maxTokens = 120,
    this.threads = 4,
    this.engine = AiEngine.cpu,
    this.stopAtJsonEnd = true,
  });
}

/// Tiempo del último prompt (diagnóstico).
int prefillMs = 0;

class LlmResult {
  final String text;
  final List<int> ids;
  final int promptTokens;
  final Duration time;
  const LlmResult(this.text, this.ids, this.promptTokens, this.time);
}

class LlmJob {
  final Future<LlmResult> future;
  final void Function() cancel;
  LlmJob._(this.future, this.cancel);
}

/// Lanza el LLM en un isolate; [onPartial] recibe el texto según se genera.
LlmJob startLlm(LlmRequest req, void Function(String partial) onPartial) {
  final rp = ReceivePort();
  final completer = Completer<LlmResult>();
  Isolate? iso;
  var cancelled = false;
  void finish() {
    rp.close();
    iso?.kill(priority: Isolate.immediate);
  }

  rp.listen((msg) {
    if (completer.isCompleted) return;
    if (msg is String) {
      onPartial(msg);
    } else if (msg is LlmResult) {
      completer.complete(msg);
      finish();
    } else if (msg is List) {
      final e = msg.isEmpty ? 'Error' : '${msg.first}';
      completer.completeError(Exception(_friendly(e)));
      finish();
    }
  });
  Isolate.spawn(_llmEntry, [rp.sendPort, req], onError: rp.sendPort).then((i) {
    iso = i;
    if (cancelled) i.kill(priority: Isolate.immediate);
  }).catchError((Object e) {
    if (!completer.isCompleted) completer.completeError(e);
    rp.close();
  });
  return LlmJob._(completer.future, () {
    cancelled = true;
    if (!completer.isCompleted) completer.completeError(Exception('Cancelado'));
    finish();
  });
}

Future<void> _llmEntry(List<dynamic> args) async {
  final SendPort sp = args[0];
  final LlmRequest req = args[1];
  try {
    sp.send(await ortWithCpuFallback(req.engine, () => runLlmSync(req, sp.send)));
  } catch (e) {
    sp.send(['$e']);
  }
}

String _friendly(String s) {
  if (s.contains('bad_alloc') || s.toLowerCase().contains('out of memory')) {
    return 'Memoria insuficiente para el modelo de razonamiento. Cierra otras apps y vuelve a probar.';
  }
  if (s.contains('NO_SUCHFILE') || s.contains('PathNotFoundException') || s.contains('No such file')) {
    return 'Faltan ficheros del modelo de razonamiento. Vuelve a descargarlo desde el gestor de modelos.';
  }
  return s;
}

/// ¿Está cerrado el objeto JSON que abre el prompt ({ ya escrito)?
bool _jsonClosed(String generated) {
  var depth = 1;
  var inStr = true; // el prompt deja abierta una clave: {"tipo": "x", "
  for (var i = 0; i < generated.length; i++) {
    final c = generated[i];
    if (c == '"' && (i == 0 || generated[i - 1] != '\\')) inStr = !inStr;
    if (inStr) continue;
    if (c == '{') depth++;
    if (c == '}') depth--;
    if (depth == 0) return true;
  }
  return false;
}

/// Ejecuta el LLM (síncrono; llamar dentro de un isolate).
Future<LlmResult> runLlmSync(LlmRequest req, [void Function(String)? onPartial]) async {
  final sw = Stopwatch()..start();
  OrtEnv.instance.init();
  final cfg = jsonDecode(await File(_p(req.modelDir, '${req.prefix}_config.json')).readAsString()) as Map<String, dynamic>;
  final layers = (cfg['num_hidden_layers'] as num).toInt();
  final kvHeads = (cfg['num_key_value_heads'] as num).toInt();
  final headDim = (cfg['head_dim'] as num?)?.toInt() ??
      (cfg['hidden_size'] as num).toInt() ~/ (cfg['num_attention_heads'] as num).toInt();
  final vocabSize = (cfg['vocab_size'] as num).toInt();
  final tok = await BpeTokenizer.fromFile(_p(req.modelDir, '${req.prefix}_tokenizer.json'));
  final eos = <int>{
    for (final k in ['<|im_end|>', '<|endoftext|>']) ?tok.vocab[k],
    if (cfg['eos_token_id'] is num) (cfg['eos_token_id'] as num).toInt(),
  };
  final ids = tok.encode(req.prompt);
  final ro = OrtRunOptions();
  final s = ortOpen(_p(req.modelDir, '${req.prefix}_model_int8.onnx'), req.threads, req.engine);
  final outNames = s.outputNames;
  final logitsIdx = outNames.indexOf('logits');
  var past = <String, OrtValue>{};
  for (var l = 0; l < layers; l++) {
    for (final kv in ['key', 'value']) {
      past['past_key_values.$l.$kv'] = OrtValueTensor.createTensorWithDataList(Float32List(0), [1, kvHeads, 0, headDim]);
    }
  }
  var done = 0; // tokens ya en la caché

  Float32List step(List<int> chunk) {
    final n = chunk.length;
    final inputs = <String, OrtValue>{
      'input_ids': OrtValueTensor.createTensorWithDataList(Int64List.fromList(chunk), [1, n]),
      'attention_mask': OrtValueTensor.createTensorWithDataList(Int64List.fromList(List.filled(done + n, 1)), [1, done + n]),
      if (s.inputNames.contains('position_ids'))
        'position_ids': OrtValueTensor.createTensorWithDataList(
            Int64List.fromList([for (var i = 0; i < n; i++) done + i]), [1, n]),
    };
    final outs = s.run(ro, {...inputs, ...past});
    for (final v in inputs.values) {
      v.release();
    }
    for (final v in past.values) {
      v.release();
    }
    past = {};
    final logits = ortFloats(outs[logitsIdx]!, vocabSize, (n - 1) * vocabSize);
    for (var i = 0; i < outs.length; i++) {
      final name = outNames[i];
      if (name.startsWith('present')) {
        past[name.replaceFirst('present', 'past_key_values')] = outs[i]!;
      } else {
        outs[i]?.release();
      }
    }
    done += n;
    return logits;
  }

  try {
    // prompt por trozos: los logits de todo el prompt de golpe ocuparían cientos de MB
    Float32List logits = Float32List(0);
    for (var i = 0; i < ids.length; i += 64) {
      logits = step(ids.sublist(i, math.min(ids.length, i + 64)));
    }
    prefillMs = sw.elapsedMilliseconds;
    final outIds = <int>[];
    var text = '';
    for (var k = 0; k < req.maxTokens; k++) {
      var best = 0;
      for (var i = 1; i < logits.length; i++) {
        if (logits[i] > logits[best]) best = i;
      }
      if (eos.contains(best)) break;
      outIds.add(best);
      text = tok.decode(outIds);
      if (onPartial != null && outIds.length % 3 == 0) onPartial(text);
      if (req.stopAtJsonEnd && _jsonClosed(text)) break;
      logits = step([best]);
    }
    return LlmResult(text, outIds, ids.length, sw.elapsed);
  } finally {
    for (final v in past.values) {
      v.release();
    }
    s.release();
    ro.release();
  }
}
