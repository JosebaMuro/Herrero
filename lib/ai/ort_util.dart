import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:onnxruntime/onnxruntime.dart';
// ignore: implementation_imports
import 'package:onnxruntime/src/bindings/onnxruntime_bindings_generated.dart' as bg;

import 'accel.dart';

/// Lee [count] floats de un tensor (desde [offset]) sin pasar por listas anidadas.
Float32List ortFloats(OrtValue v, int count, [int offset = 0]) {
  final api = OrtEnv.instance.ortApiPtr.ref;
  final out = calloc<ffi.Pointer<ffi.Void>>();
  try {
    final st = api.GetTensorMutableData.asFunction<
        bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtValue>, ffi.Pointer<ffi.Pointer<ffi.Void>>)>()(v.ptr.cast(), out);
    OrtStatus.checkOrtStatus(st);
    final p = out.value.cast<ffi.Float>();
    return Float32List.fromList((p + offset).asTypedList(count));
  } finally {
    calloc.free(out);
  }
}

/// Abre una sesión con [threads] hilos, todas las optimizaciones y la aceleración de
/// [engine] (GPU / NPU si la hay; si no, o si falla, CPU).
OrtSession ortOpen(String path, int threads, [AiEngine engine = AiEngine.cpu]) =>
    ortOpenAccel(path, threads, engine).session;
