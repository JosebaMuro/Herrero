import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:onnxruntime/onnxruntime.dart';

import 'accel.dart';
import 'clip_tokenizer.dart';

export 'accel.dart' show AiEngine, AiEngineLabel, enginesForPlatform;

/// Petición de generación (se envía al isolate de trabajo).
class SdRequest {
  final String modelDir;
  final String textEncoderFile;
  final String unetFile;
  final String vaeEncoderFile;
  final String vaeDecoderFile;
  final double vaeScale;
  final String prompt;
  final int size;
  final int steps;
  final double strength;
  final Uint8List? initRgba; // size x size RGBA
  final int seed;
  final int threads;
  final AiEngine engine;

  const SdRequest({
    required this.modelDir,
    this.textEncoderFile = 'sdturbo_text_encoder_int8.onnx',
    required this.unetFile,
    this.vaeEncoderFile = 'sdturbo_vae_encoder.onnx',
    this.vaeDecoderFile = 'sdturbo_vae_decoder.onnx',
    this.vaeScale = 0.18215,
    required this.prompt,
    this.size = 512,
    this.steps = 2,
    this.strength = 0.5,
    this.initRgba,
    this.seed = 0,
    this.threads = 4,
    this.engine = AiEngine.auto,
  });
}

class SdProgress {
  final double fraction;
  final String message;
  const SdProgress(this.fraction, this.message);
}

class SdResult {
  final Uint8List rgba;
  final int size;
  final Duration elapsed;
  final String engineUsed;
  SdResult(this.rgba, this.size, this.elapsed, this.engineUsed);
}

class SdCancelled implements Exception {
  @override
  String toString() => 'Generación cancelada';
}

/// Trabajo de generación en curso (cancelable).
class SdJob {
  final Future<SdResult> future;
  final void Function() cancel;
  SdJob._(this.future, this.cancel);
}

/// Lanza la generación en un isolate para no bloquear la interfaz.
SdJob startGeneration(SdRequest req, void Function(SdProgress) onProgress) {
  final rp = ReceivePort();
  final completer = Completer<SdResult>();
  Isolate? iso;
  var cancelled = false;

  void finish() {
    rp.close();
    iso?.kill(priority: Isolate.immediate);
  }

  rp.listen((msg) {
    if (completer.isCompleted) return;
    if (msg is SdProgress) {
      onProgress(msg);
    } else if (msg is SdResult) {
      completer.complete(msg);
      finish();
    } else if (msg is String) {
      completer.completeError(Exception(msg));
      finish();
    } else if (msg is List) {
      // error no capturado dentro del isolate: [mensaje, pila]
      completer.completeError(Exception(_friendly(msg.isEmpty ? 'Error' : msg.first as Object)));
      finish();
    }
  });
  Isolate.spawn(_entry, [rp.sendPort, req], onError: rp.sendPort)
      .then((i) {
        iso = i;
        if (cancelled) i.kill(priority: Isolate.immediate);
      })
      .catchError((Object e) {
        if (!completer.isCompleted) completer.completeError(e);
        rp.close();
      });
  return SdJob._(completer.future, () {
    cancelled = true;
    if (!completer.isCompleted) completer.completeError(SdCancelled());
    finish();
  });
}

Future<SdResult> generateImage(SdRequest req, void Function(SdProgress) onProgress) =>
    startGeneration(req, onProgress).future;

Future<void> _entry(List<dynamic> args) async {
  final SendPort sp = args[0];
  final SdRequest req = args[1];
  try {
    final res = await _run(req, (f, m) => sp.send(SdProgress(f, m)));
    sp.send(res);
  } catch (e) {
    sp.send(_friendly(e));
  }
}

String _friendly(Object e) {
  final s = '$e';
  if (s.contains('bad_alloc') || s.toLowerCase().contains('out of memory') || s.contains('Failed to allocate')) {
    return 'Memoria insuficiente para generar la imagen. Prueba la resolución 384 o el modelo "Ligero".';
  }
  if (s.contains('NO_SUCHFILE') || s.contains('PathNotFoundException') || s.contains('No such file')) {
    return 'Faltan ficheros del modelo. Vuelve a descargarlo desde el gestor de modelos.';
  }
  return s;
}

// ---------------------------------------------------------------------------
// Planificador Euler discreto (timestep_spacing = trailing), igual que diffusers
// ---------------------------------------------------------------------------

List<double> sigmasTable() {
  final b0 = math.sqrt(0.00085), b1 = math.sqrt(0.012);
  var acp = 1.0;
  final out = <double>[];
  for (var i = 0; i < 1000; i++) {
    final b = math.pow(b0 + (b1 - b0) * i / 999, 2).toDouble();
    acp *= (1 - b);
    out.add(math.sqrt((1 - acp) / acp));
  }
  return out;
}

List<int> timestepsFor(int n) => [for (var i = 0; i < n; i++) (1000 - i * 1000 / n).round() - 1];

class _Gauss {
  final math.Random r;
  double? _spare;
  _Gauss(int seed) : r = math.Random(seed);
  double next() {
    if (_spare != null) {
      final s = _spare!;
      _spare = null;
      return s;
    }
    double u, v, s;
    do {
      u = r.nextDouble() * 2 - 1;
      v = r.nextDouble() * 2 - 1;
      s = u * u + v * v;
    } while (s >= 1 || s == 0);
    final m = math.sqrt(-2 * math.log(s) / s);
    _spare = v * m;
    return u * m;
  }
}

Float32List _flat(dynamic v) {
  final out = <double>[];
  void walk(dynamic x) {
    if (x is List) {
      for (final e in x) {
        walk(e);
      }
    } else {
      out.add((x as num).toDouble());
    }
  }

  walk(v);
  return Float32List.fromList(out);
}

String _p(String dir, String f) => '$dir${Platform.pathSeparator}$f';

/// Modelo ONNX con selección de motor y vuelta a CPU si la aceleración falla.
class _Model {
  final String path;
  final SdRequest req;
  final bool quantized;
  AiEngine engine;
  OrtEp ep = OrtEp.cpu;
  OrtSession? _s;
  _Model(this.path, this.req, {required this.quantized}) : engine = req.engine;

  OrtSession get session {
    if (_s != null) return _s!;
    final o = ortOpenAccel(path, req.threads, engine, quantized: quantized);
    ep = o.ep;
    return _s = o.session;
  }

  Float32List run(OrtRunOptions ro, Map<String, OrtValue> inputs) {
    List<OrtValue?> outs;
    try {
      outs = session.run(ro, inputs);
    } catch (e) {
      if (ep == OrtEp.cpu) rethrow;
      // la aceleración ha fallado en ejecución: reintento en CPU
      release();
      engine = AiEngine.cpu;
      outs = session.run(ro, inputs);
    }
    final r = _flat(outs[0]!.value);
    for (final o in outs) {
      o?.release();
    }
    return r;
  }

  void release() {
    _s?.release();
    _s = null;
  }
}

Future<SdResult> _run(SdRequest req, void Function(double, String) progress) async {
  final sw = Stopwatch()..start();
  OrtEnv.instance.init();
  // Política de motor (accelChain): los modelos int8 dinámicos (texto, UNet) no los
  // admite NNAPI, así que en Android "Automático" solo acelera el VAE (fp32). En PC la
  // GPU (DirectML, CUDA u OpenVINO) se usa para todos.
  final used = <String>{};
  final ro = OrtRunOptions();

  // 1) Texto -> embeddings
  progress(0.03, 'Interpretando la descripción…');
  final tok = await ClipTokenizer.fromDir(req.modelDir);
  final ids = tok.encode(req.prompt);
  final te = _Model(_p(req.modelDir, req.textEncoderFile), req, quantized: true);
  final idsT = OrtValueTensor.createTensorWithDataList(Int64List.fromList(ids), [1, 77]);
  final emb = te.run(ro, {'input_ids': idsT});
  idsT.release();
  used.add(te.ep.label);
  te.release();

  final size = req.size;
  final h = size ~/ 8, w = size ~/ 8;
  final n = 4 * h * w;
  final sig = sigmasTable();
  var ts = timestepsFor(req.steps);
  final g = _Gauss(req.seed);
  var lat = Float32List(n);

  // 2) Latentes iniciales
  if (req.initRgba != null) {
    final k = math.max(1, math.min((req.steps * req.strength).floor(), req.steps));
    ts = ts.sublist(req.steps - k);
    progress(0.12, 'Codificando el render 3D…');
    final img = Float32List(3 * size * size);
    final px = req.initRgba!;
    final plane = size * size;
    for (var o = 0; o < plane; o++) {
      final i = o * 4;
      img[o] = px[i] / 127.5 - 1;
      img[plane + o] = px[i + 1] / 127.5 - 1;
      img[2 * plane + o] = px[i + 2] / 127.5 - 1;
    }
    final enc = _Model(_p(req.modelDir, req.vaeEncoderFile), req, quantized: false);
    final t = OrtValueTensor.createTensorWithDataList(img, [1, 3, size, size]);
    final e = enc.run(ro, {'sample': t});
    t.release();
    used.add(enc.ep.label);
    enc.release();
    final s0 = sig[ts.first];
    for (var i = 0; i < n; i++) {
      lat[i] = e[i] * req.vaeScale + g.next() * s0;
    }
  } else {
    final s0 = math.sqrt(sig[ts.first] * sig[ts.first] + 1);
    for (var i = 0; i < n; i++) {
      lat[i] = g.next() * s0;
    }
  }

  // 3) Difusión (UNet)
  progress(0.22, 'Cargando el modelo de imagen…');
  final unet = _Model(_p(req.modelDir, req.unetFile), req, quantized: true);
  unet.session; // carga explícita (lo más lento la primera vez)
  final embT = OrtValueTensor.createTensorWithDataList(emb, [1, 77, emb.length ~/ 77]);
  for (var i = 0; i < ts.length; i++) {
    progress(0.35 + 0.4 * i / ts.length, 'Generando (paso ${i + 1} de ${ts.length})…');
    final t = ts[i];
    final sc = sig[t];
    final nx = i + 1 < ts.length ? sig[ts[i + 1]] : 0.0;
    final inp = Float32List(n);
    final k = 1 / math.sqrt(sc * sc + 1);
    for (var j = 0; j < n; j++) {
      inp[j] = lat[j] * k;
    }
    final xT = OrtValueTensor.createTensorWithDataList(inp, [1, 4, h, w]);
    final tT = OrtValueTensor.createTensorWithDataList(Float32List.fromList([t.toDouble()]), [1]);
    final eps = unet.run(ro, {'sample': xT, 'timestep': tT, 'encoder_hidden_states': embT});
    xT.release();
    tT.release();
    final dt = nx - sc;
    final nl = Float32List(n);
    for (var j = 0; j < n; j++) {
      nl[j] = lat[j] + eps[j] * dt;
    }
    lat = nl;
  }
  embT.release();
  used.add(unet.ep.label);
  unet.release();

  // 4) Decodificar
  progress(0.8, 'Revelando la imagen…');
  final dec = _Model(_p(req.modelDir, req.vaeDecoderFile), req, quantized: false);
  final z = Float32List(n);
  for (var j = 0; j < n; j++) {
    z[j] = lat[j] / req.vaeScale;
  }
  final zT = OrtValueTensor.createTensorWithDataList(z, [1, 4, h, w]);
  final out = dec.run(ro, {'latent_sample': zT});
  zT.release();
  used.add(dec.ep.label);
  dec.release();
  ro.release();
  OrtEnv.instance.release();

  final rgba = Uint8List(size * size * 4);
  final plane = size * size;
  int c(double v) => ((v + 1) * 127.5).round().clamp(0, 255);
  for (var o = 0; o < plane; o++) {
    rgba[o * 4] = c(out[o]);
    rgba[o * 4 + 1] = c(out[plane + o]);
    rgba[o * 4 + 2] = c(out[2 * plane + o]);
    rgba[o * 4 + 3] = 255;
  }
  progress(1, 'Listo');
  final accel = used.where((u) => u != 'CPU').toList();
  final engine = accel.isEmpty ? 'CPU (${req.threads} hilos)' : '${accel.join(' + ')} + CPU (${req.threads} hilos)';
  return SdResult(rgba, size, sw.elapsed, engine);
}
