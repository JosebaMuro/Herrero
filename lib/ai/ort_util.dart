import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:onnxruntime/onnxruntime.dart';
// ignore: implementation_imports
import 'package:onnxruntime/src/bindings/onnxruntime_bindings_generated.dart' as bg;

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

/// Abre una sesión de CPU con [threads] hilos y todas las optimizaciones.
OrtSession ortOpen(String path, int threads) {
  final o = OrtSessionOptions()
    ..setIntraOpNumThreads(threads)
    ..setInterOpNumThreads(1)
    ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
  try {
    o.appendCPUProvider(CPUFlags.useArena);
    return OrtSession.fromFile(File(path), o);
  } finally {
    o.release();
  }
}
