import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:onnxruntime/onnxruntime.dart';

import 'bpe_tokenizer.dart';
import 'ort_util.dart';

/// Pregunta que se hace al modelo sobre un croquis o plano. El modelo es más
/// fiable en inglés; la respuesta se traduce a términos del oficio después.
const sketchQuestion =
    'Which steel structure is drawn: a carport, warehouse, staircase, railing, gate, mezzanine, '
    'footbridge, tower, truss, shelving, fence, pole or portal frame? Name it, say how many columns '
    'it has, what the roof is made of and which dimensions are written.';

class VlmRequest {
  final String modelDir;
  final String prefix; // smolvlm (256M) o smolvlm500 (500M)
  final Uint8List rgba;
  final int width, height;
  final String question;
  final int maxTokens;
  final int threads;
  final double repetitionPenalty;
  const VlmRequest({
    required this.modelDir,
    this.prefix = 'smolvlm',
    required this.rgba,
    required this.width,
    required this.height,
    this.question = sketchQuestion,
    this.maxTokens = 120,
    this.threads = 4,
    this.repetitionPenalty = 1.15,
  });
}

class VlmResult {
  final String text;
  final List<int> ids;
  final Duration time;
  const VlmResult(this.text, this.ids, this.time);
}

/// Trabajo de lectura de croquis en curso (cancelable).
class VlmJob {
  final Future<VlmResult> future;
  final void Function() cancel;
  VlmJob._(this.future, this.cancel);
}

/// Lanza el VLM en un isolate; [onPartial] recibe el texto según se genera.
VlmJob startVlm(VlmRequest req, void Function(String partial) onPartial) {
  final rp = ReceivePort();
  final completer = Completer<VlmResult>();
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
    } else if (msg is VlmResult) {
      completer.complete(msg);
      finish();
    } else if (msg is List) {
      final e = msg.isEmpty ? 'Error' : '${msg.first}';
      completer.completeError(Exception(_friendly(e)));
      finish();
    }
  });
  Isolate.spawn(_entry, [rp.sendPort, req], onError: rp.sendPort).then((i) {
    iso = i;
    if (cancelled) i.kill(priority: Isolate.immediate);
  }).catchError((Object e) {
    if (!completer.isCompleted) completer.completeError(e);
    rp.close();
  });
  return VlmJob._(completer.future, () {
    cancelled = true;
    if (!completer.isCompleted) completer.completeError(Exception('Cancelado'));
    finish();
  });
}

Future<void> _entry(List<dynamic> args) async {
  final SendPort sp = args[0];
  final VlmRequest req = args[1];
  try {
    sp.send(await runVlmSync(req, sp.send));
  } catch (e) {
    sp.send(['$e']);
  }
}

String _friendly(String s) {
  if (s.contains('bad_alloc') || s.toLowerCase().contains('out of memory')) {
    return 'Memoria insuficiente para el modelo de visión. Cierra otras apps y vuelve a probar.';
  }
  if (s.contains('NO_SUCHFILE') || s.contains('PathNotFoundException') || s.contains('No such file')) {
    return 'Faltan ficheros del modelo de visión. Vuelve a descargarlo desde el gestor de modelos.';
  }
  return s;
}

String _p(String dir, String f) => '$dir${Platform.pathSeparator}$f';

/// Imagen RGBA cualquiera -> tensor [1,1,3,512,512] normalizado a [-1, 1].
/// Se escala al cuadrado de 512 (como hace el procesador de Idefics3 sin
/// trocear) promediando por área; la transparencia se compone sobre blanco.
Float32List vlmPixels(Uint8List rgba, int w, int h, {int size = 512}) {
  final out = Float32List(3 * size * size);
  final plane = size * size;
  final sx = w / size, sy = h / size;
  for (var y = 0; y < size; y++) {
    final y0 = y * sy, y1 = (y + 1) * sy;
    final iy0 = y0.floor(), iy1 = math.min(h, y1.ceil());
    for (var x = 0; x < size; x++) {
      final x0 = x * sx, x1 = (x + 1) * sx;
      final ix0 = x0.floor(), ix1 = math.min(w, x1.ceil());
      var r = 0.0, g = 0.0, b = 0.0, wsum = 0.0;
      for (var yy = iy0; yy < iy1; yy++) {
        final wy = math.min(y1, yy + 1.0) - math.max(y0, yy.toDouble());
        if (wy <= 0) continue;
        for (var xx = ix0; xx < ix1; xx++) {
          final wx = math.min(x1, xx + 1.0) - math.max(x0, xx.toDouble());
          if (wx <= 0) continue;
          final k = (yy * w + xx) * 4;
          final a = rgba[k + 3] / 255.0;
          final wt = wx * wy;
          r += (rgba[k] * a + 255 * (1 - a)) * wt;
          g += (rgba[k + 1] * a + 255 * (1 - a)) * wt;
          b += (rgba[k + 2] * a + 255 * (1 - a)) * wt;
          wsum += wt;
        }
      }
      final o = y * size + x;
      final inv = wsum > 0 ? 1 / (wsum * 127.5) : 0.0;
      out[o] = r * inv - 1;
      out[plane + o] = g * inv - 1;
      out[2 * plane + o] = b * inv - 1;
    }
  }
  return out;
}

/// Texto del turno de usuario con la imagen expandida (sin trocear: 64 tokens).
String vlmPrompt(String question, {int imageTokens = 64}) =>
    '<|im_start|>User:<fake_token_around_image><global-img>${'<image>' * imageTokens}'
    '<fake_token_around_image>$question<end_of_utterance>\nAssistant:';

/// Ejecuta el VLM (síncrono; llamar dentro de un isolate). [onPartial] recibe
/// el texto acumulado cada pocos tokens.
Future<VlmResult> runVlmSync(VlmRequest req, [void Function(String)? onPartial]) async {
  final sw = Stopwatch()..start();
  OrtEnv.instance.init();
  final cfg = jsonDecode(await File(_p(req.modelDir, '${req.prefix}_config.json')).readAsString()) as Map<String, dynamic>;
  final t = cfg['text_config'] as Map<String, dynamic>;
  final hidden = (t['hidden_size'] as num).toInt();
  final layers = (t['num_hidden_layers'] as num).toInt();
  final kvHeads = (t['num_key_value_heads'] as num).toInt();
  final headDim = (t['head_dim'] as num?)?.toInt() ?? hidden ~/ (t['num_attention_heads'] as num).toInt();
  final vocabSize = (t['vocab_size'] as num).toInt();
  final imageTok = (cfg['image_token_id'] as num).toInt();
  final tok = await BpeTokenizer.fromFile(_p(req.modelDir, '${req.prefix}_tokenizer.json'));
  final eos = <int>{(t['eos_token_id'] as num).toInt(), if (tok.vocab['<end_of_utterance>'] != null) tok.vocab['<end_of_utterance>']!};

  final ro = OrtRunOptions();
  OrtSession? vis, emb, dec;
  try {
    // 1) imagen -> 64 vectores
    vis = ortOpen(_p(req.modelDir, '${req.prefix}_vision_int8.onnx'), req.threads);
    final pv = OrtValueTensor.createTensorWithDataList(vlmPixels(req.rgba, req.width, req.height), [1, 1, 3, 512, 512]);
    final vin = <String, OrtValue>{'pixel_values': pv};
    OrtValue? pm;
    if (vis.inputNames.contains('pixel_attention_mask')) {
      pm = OrtValueTensor.createTensorWithDataList(List<bool>.filled(512 * 512, true), [1, 1, 512, 512]);
      vin['pixel_attention_mask'] = pm;
    }
    final vo = vis.run(ro, vin);
    pv.release();
    pm?.release();
    final feats = ortFloats(vo[0]!, 64 * hidden);
    for (final o in vo) {
      o?.release();
    }
    vis.release();
    vis = null;

    // 2) prompt -> embeddings, con la imagen en el hueco de los tokens <image>
    final ids = tok.encode(vlmPrompt(req.question));
    emb = ortOpen(_p(req.modelDir, '${req.prefix}_embed_int8.onnx'), math.min(2, req.threads));
    Float32List embed(List<int> x) {
      final it = OrtValueTensor.createTensorWithDataList(Int64List.fromList(x), [1, x.length]);
      final eo = emb!.run(ro, {'input_ids': it});
      it.release();
      final r = ortFloats(eo[0]!, x.length * hidden);
      for (final o in eo) {
        o?.release();
      }
      return r;
    }

    var e = embed(ids);
    var k = 0;
    for (var i = 0; i < ids.length && k < 64; i++) {
      if (ids[i] == imageTok) {
        e.setRange(i * hidden, (i + 1) * hidden, feats, k * hidden);
        k++;
      }
    }

    // 3) decodificación voraz con caché KV (el pasado empieza vacío)
    dec = ortOpen(_p(req.modelDir, '${req.prefix}_decoder_int8.onnx'), req.threads);
    final outNames = dec.outputNames;
    final logitsIdx = outNames.indexOf('logits');
    var past = <String, OrtValue>{};
    for (var l = 0; l < layers; l++) {
      for (final kv in ['key', 'value']) {
        past['past_key_values.$l.$kv'] =
            OrtValueTensor.createTensorWithDataList(Float32List(0), [1, kvHeads, 0, headDim]);
      }
    }
    final mask = List<int>.filled(ids.length, 1, growable: true);
    var pos = [for (var i = 0; i < ids.length; i++) i];
    var seq = ids.length;
    final outIds = <int>[];
    for (var step = 0; step < req.maxTokens; step++) {
      final eT = OrtValueTensor.createTensorWithDataList(e, [1, seq, hidden]);
      final mT = OrtValueTensor.createTensorWithDataList(Int64List.fromList(mask), [1, mask.length]);
      final pT = OrtValueTensor.createTensorWithDataList(Int64List.fromList(pos), [1, seq]);
      final outs = dec.run(ro, {'inputs_embeds': eT, 'attention_mask': mT, 'position_ids': pT, ...past});
      eT.release();
      mT.release();
      pT.release();
      for (final v in past.values) {
        v.release();
      }
      past = {};
      final logits = ortFloats(outs[logitsIdx]!, vocabSize, (seq - 1) * vocabSize);
      for (var i = 0; i < outs.length; i++) {
        final n = outNames[i];
        if (n.startsWith('present')) {
          past[n.replaceFirst('present', 'past_key_values')] = outs[i]!;
        } else {
          outs[i]?.release();
        }
      }
      if (req.repetitionPenalty != 1) {
        for (final id in outIds.toSet()) {
          final v = logits[id];
          logits[id] = v > 0 ? v / req.repetitionPenalty : v * req.repetitionPenalty;
        }
      }
      var best = 0;
      for (var i = 1; i < logits.length; i++) {
        if (logits[i] > logits[best]) best = i;
      }
      outIds.add(best);
      if (eos.contains(best)) break;
      if (onPartial != null && outIds.length % 4 == 0) onPartial(tok.decode(outIds));
      e = embed([best]);
      mask.add(1);
      pos = [pos.last + 1];
      seq = 1;
    }
    for (final v in past.values) {
      v.release();
    }
    final text = tok.decode(outIds).trim();
    return VlmResult(text, outIds, sw.elapsed);
  } finally {
    vis?.release();
    emb?.release();
    dec?.release();
    ro.release();
  }
}
