import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:onnxruntime/onnxruntime.dart';

import '../ai/accel.dart';
import 'plan_token.dart';

/// Petición de OCR: imagen RGBA en memoria y carpeta de modelos.
class OcrRequest {
  final String modelDir;
  final Uint8List rgba;
  final int width, height;
  final int maxSide; // lado máximo para el detector
  final int threads;
  final AiEngine engine;
  const OcrRequest({
    required this.modelDir,
    required this.rgba,
    required this.width,
    required this.height,
    this.maxSide = 1920,
    this.threads = 4,
    this.engine = AiEngine.cpu,
  });
}

/// Lector OCR local (PP-OCRv4: detector DB + reconocedor CTC) sobre ONNX Runtime.
/// Se ejecuta en un isolate para no bloquear la interfaz.
Future<List<PlanToken>> runOcr(OcrRequest r) =>
    Isolate.run(() => ortWithCpuFallback(r.engine, () async => ocrSync(r)));

List<PlanToken> ocrSync(OcrRequest r) {
  OrtEnv.instance.init();
  final sep = Platform.pathSeparator;
  // tamaños de entrada variables: en Android "Automático" (quantized) se queda en CPU,
  // NNAPI los lleva mal; en PC va a la GPU.
  final det = ortOpenAccel('${r.modelDir}${sep}ppocrv4_det.onnx', r.threads, r.engine).session;
  final rec = ortOpenAccel('${r.modelDir}${sep}ppocrv4_rec.onnx', r.threads, r.engine).session;
  final keys = File('${r.modelDir}${sep}ppocr_keys.txt').readAsStringSync().split('\n')..add(' ');
  final ro = OrtRunOptions();
  try {
    final boxes = _detect(det, ro, r);
    final out = <PlanToken>[];
    for (final b in boxes.take(400)) {
      final bw = b.x1 - b.x0, bh = b.y1 - b.y0;
      if (bh > 1.5 * bw) {
        // Texto vertical (cotas giradas): se prueban los dos sentidos de lectura
        final up = _recognize(rec, ro, r, b, _Orient.up, keys);
        final down = _recognize(rec, ro, r, b, _Orient.down, keys);
        final best = up.$2 >= down.$2 ? up : down;
        if (best.$2 > 0.5 && best.$1.trim().isNotEmpty) {
          out.add(PlanToken(best.$1.trim(), b.x0, b.y0, b.x1, b.y1, vertical: true, confidence: best.$2));
        }
      } else {
        final t = _recognize(rec, ro, r, b, _Orient.horizontal, keys);
        if (t.$2 > 0.5 && t.$1.trim().isNotEmpty) {
          out.add(PlanToken(t.$1.trim(), b.x0, b.y0, b.x1, b.y1, confidence: t.$2));
        }
      }
    }
    return out;
  } finally {
    ro.release();
    det.release();
    rec.release();
  }
}

class _Box {
  final double x0, y0, x1, y1, score;
  _Box(this.x0, this.y0, this.x1, this.y1, this.score);
}

enum _Orient { horizontal, up, down }

/// Lee el píxel (bilineal) del RGBA original y lo devuelve normalizado en BGR.
void _sample(OcrRequest r, double x, double y, Float32List dst, int plane, int idx) {
  final w = r.width, h = r.height;
  final fx = x.clamp(0.0, w - 1.0), fy = y.clamp(0.0, h - 1.0);
  final x0 = fx.floor(), y0 = fy.floor();
  final x1 = math.min(x0 + 1, w - 1), y1 = math.min(y0 + 1, h - 1);
  final ax = fx - x0, ay = fy - y0;
  for (var c = 0; c < 3; c++) {
    final src = r.rgba;
    final p00 = src[(y0 * w + x0) * 4 + c], p10 = src[(y0 * w + x1) * 4 + c];
    final p01 = src[(y1 * w + x0) * 4 + c], p11 = src[(y1 * w + x1) * 4 + c];
    final v = (p00 * (1 - ax) + p10 * ax) * (1 - ay) + (p01 * (1 - ax) + p11 * ax) * ay;
    // canal BGR: c=0 (R) va al plano 2
    dst[(2 - c) * plane + idx] = (v / 255.0 - 0.5) / 0.5;
  }
}

List<_Box> _detect(OrtSession det, OrtRunOptions ro, OcrRequest r) {
  final s = math.min(1.0, r.maxSide / math.max(r.width, r.height));
  final nw = math.max(32, ((r.width * s) / 32).round() * 32);
  final nh = math.max(32, ((r.height * s) / 32).round() * 32);
  final plane = nw * nh;
  final input = Float32List(3 * plane);
  final sx = r.width / nw, sy = r.height / nh;
  for (var y = 0; y < nh; y++) {
    for (var x = 0; x < nw; x++) {
      _sample(r, (x + 0.5) * sx - 0.5, (y + 0.5) * sy - 0.5, input, plane, y * nw + x);
    }
  }
  final t = OrtValueTensor.createTensorWithDataList(input, [1, 3, nh, nw]);
  final outs = det.run(ro, {'x': t});
  t.release();
  final prob = _flat(outs[0]!.value, plane);
  for (final o in outs) {
    o?.release();
  }
  // Binarizado + dilatación 2x2
  final bin = Uint8List(plane);
  for (var i = 0; i < plane; i++) {
    if (prob[i] > 0.3) bin[i] = 1;
  }
  final dil = Uint8List.fromList(bin);
  for (var y = 0; y < nh; y++) {
    for (var x = 0; x < nw; x++) {
      if (bin[y * nw + x] == 0) continue;
      if (x + 1 < nw) dil[y * nw + x + 1] = 1;
      if (y + 1 < nh) dil[(y + 1) * nw + x] = 1;
      if (x + 1 < nw && y + 1 < nh) dil[(y + 1) * nw + x + 1] = 1;
    }
  }
  // Componentes conexas
  final seen = Uint8List(plane);
  final stack = Int32List(plane);
  final boxes = <_Box>[];
  for (var i = 0; i < plane; i++) {
    if (dil[i] == 0 || seen[i] == 1) continue;
    var sp = 0;
    stack[sp++] = i;
    seen[i] = 1;
    var minX = nw, minY = nh, maxX = 0, maxY = 0, n = 0;
    var sum = 0.0;
    while (sp > 0) {
      final k = stack[--sp];
      final y = k ~/ nw, x = k - y * nw;
      n++;
      sum += prob[k];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      if (x > 0 && dil[k - 1] == 1 && seen[k - 1] == 0) {
        seen[k - 1] = 1;
        stack[sp++] = k - 1;
      }
      if (x + 1 < nw && dil[k + 1] == 1 && seen[k + 1] == 0) {
        seen[k + 1] = 1;
        stack[sp++] = k + 1;
      }
      if (y > 0 && dil[k - nw] == 1 && seen[k - nw] == 0) {
        seen[k - nw] = 1;
        stack[sp++] = k - nw;
      }
      if (y + 1 < nh && dil[k + nw] == 1 && seen[k + nw] == 0) {
        seen[k + nw] = 1;
        stack[sp++] = k + nw;
      }
    }
    if (n < 6) continue;
    final score = sum / n;
    if (score < 0.5) continue;
    final bw = (maxX - minX + 1).toDouble(), bh = (maxY - minY + 1).toDouble();
    if (math.min(bw, bh) < 3) continue;
    final d = bw * bh * 1.6 / (2 * (bw + bh)); // "unclip" del algoritmo DB
    boxes.add(_Box(
      math.max(0, (minX - d) * sx),
      math.max(0, (minY - d) * sy),
      math.min(r.width.toDouble(), (maxX + 1 + d) * sx),
      math.min(r.height.toDouble(), (maxY + 1 + d) * sy),
      score,
    ));
  }
  boxes.sort((a, b) => (b.score * (b.x1 - b.x0)).compareTo(a.score * (a.x1 - a.x0)));
  return boxes;
}

(String, double) _recognize(
    OrtSession rec, OrtRunOptions ro, OcrRequest r, _Box b, _Orient o, List<String> keys) {
  const hh = 48;
  final along = o == _Orient.horizontal ? b.x1 - b.x0 : b.y1 - b.y0;
  final across = o == _Orient.horizontal ? b.y1 - b.y0 : b.x1 - b.x0;
  final nw = math.min(1600, math.max(16, (hh * along / across).ceil()));
  final tw = math.max(160, ((nw + 31) ~/ 32) * 32);
  final plane = hh * tw;
  final input = Float32List(3 * plane); // relleno a 0 (gris medio)
  for (var v = 0; v < hh; v++) {
    for (var u = 0; u < nw; u++) {
      final fu = (u + 0.5) / nw, fv = (v + 0.5) / hh;
      final double x, y;
      switch (o) {
        case _Orient.horizontal:
          x = b.x0 + fu * (b.x1 - b.x0);
          y = b.y0 + fv * (b.y1 - b.y0);
          break;
        case _Orient.up: // se lee de abajo arriba
          x = b.x0 + fv * (b.x1 - b.x0);
          y = b.y1 - fu * (b.y1 - b.y0);
          break;
        case _Orient.down: // se lee de arriba abajo
          x = b.x1 - fv * (b.x1 - b.x0);
          y = b.y0 + fu * (b.y1 - b.y0);
          break;
      }
      _sample(r, x - 0.5, y - 0.5, input, plane, v * tw + u);
    }
  }
  final t = OrtValueTensor.createTensorWithDataList(input, [1, 3, hh, tw]);
  final outs = rec.run(ro, {'x': t});
  t.release();
  final v = outs[0]!.value as List;
  for (final e in outs) {
    e?.release();
  }
  final steps = v[0] as List;
  final sb = StringBuffer();
  var last = -1;
  var sum = 0.0;
  var n = 0;
  for (final row in steps) {
    final p = row as List;
    var best = 0;
    var bp = -1.0;
    for (var k = 0; k < p.length; k++) {
      final q = (p[k] as num).toDouble();
      if (q > bp) {
        bp = q;
        best = k;
      }
    }
    if (best != 0 && best != last && best - 1 < keys.length) {
      sb.write(keys[best - 1]);
      sum += bp;
      n++;
    }
    last = best;
  }
  return (sb.toString(), n == 0 ? 0.0 : sum / n);
}

Float32List _flat(dynamic v, int expected) {
  final out = Float32List(expected);
  var i = 0;
  void walk(dynamic x) {
    if (x is List) {
      for (final e in x) {
        walk(e);
      }
    } else if (i < expected) {
      out[i++] = (x as num).toDouble();
    }
  }

  walk(v);
  return out;
}
