// Cargador de ONNX Runtime de Herrero para Windows.
//
// scripts/ort_runtime.py lo copia en el paquete `onnxruntime` como
// lib/src/bindings/herrero_loader.dart y hace que bindings.dart lo use en vez de
// DynamicLibrary.open('onnxruntime.dll').
//
// Reglas:
// * Siempre por ruta completa: Windows trae un onnxruntime.dll antiguo en System32
//   y abrirlo por nombre puede devolver ese (v3.4.1).
// * Por defecto, el de la app (junto a herrero.exe): ONNX Runtime 1.20 con DirectML.
// * Si el usuario ha instalado un paquete de aceleración (CUDA u OpenVINO) y lo ha
//   elegido, se abre el de %LOCALAPPDATA%\Herrero\gpu\<paquete>\.
// * La elección se fija una vez por proceso en la variable HERRERO_ORT_DIR: todos los
//   isolates cargan la misma DLL (dos ONNX Runtime distintos en un proceso chocan).
//   También sirve para forzar una carpeta en las pruebas de CI.
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _GetEnvC = Uint32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32);
typedef _GetEnvD = int Function(Pointer<Utf16>, Pointer<Utf16>, int);
typedef _SetEnvC = Int32 Function(Pointer<Utf16>, Pointer<Utf16>);
typedef _SetEnvD = int Function(Pointer<Utf16>, Pointer<Utf16>);
typedef _SetDirC = Int32 Function(Pointer<Utf16>);
typedef _SetDirD = int Function(Pointer<Utf16>);

String? _getEnv(DynamicLibrary k32, String name) {
  final f = k32.lookupFunction<_GetEnvC, _GetEnvD>('GetEnvironmentVariableW');
  final n = name.toNativeUtf16();
  final buf = calloc<Uint16>(32768).cast<Utf16>();
  try {
    final len = f(n, buf, 32768);
    return len == 0 ? null : buf.toDartString(length: len);
  } finally {
    calloc.free(n);
    calloc.free(buf);
  }
}

void _setEnv(DynamicLibrary k32, String name, String value) {
  final f = k32.lookupFunction<_SetEnvC, _SetEnvD>('SetEnvironmentVariableW');
  final n = name.toNativeUtf16();
  final v = value.toNativeUtf16();
  f(n, v);
  calloc.free(n);
  calloc.free(v);
}

void _setDllDirectory(DynamicLibrary k32, String? dir) {
  final f = k32.lookupFunction<_SetDirC, _SetDirD>('SetDllDirectoryW');
  if (dir == null) {
    f(nullptr);
    return;
  }
  final d = dir.toNativeUtf16();
  f(d);
  calloc.free(d);
}

/// Carpeta del paquete de aceleración elegido (o null si no hay o no está completo).
String? _selectedPack(String? localAppData) {
  if (localAppData == null || localAppData.isEmpty) return null;
  final base = '$localAppData\\Herrero\\gpu';
  final sel = File('$base\\runtime.txt');
  if (!sel.existsSync()) return null;
  final id = sel.readAsStringSync().trim();
  if (id.isEmpty || !RegExp(r'^[a-z0-9_-]+$').hasMatch(id)) return null;
  final dir = '$base\\$id';
  return File('$dir\\installed.json').existsSync() ? dir : null;
}

DynamicLibrary herreroOpenOrt() {
  final k32 = DynamicLibrary.open('kernel32.dll');
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final candidates = <String>[];
  final fixed = _getEnv(k32, 'HERRERO_ORT_DIR');
  if (fixed != null && fixed.isNotEmpty) {
    candidates.add(fixed);
  } else {
    try {
      final pack = _selectedPack(_getEnv(k32, 'LOCALAPPDATA'));
      if (pack != null) candidates.add(pack);
    } catch (_) {}
  }
  if (!candidates.contains(exeDir)) candidates.add(exeDir);
  for (final dir in candidates) {
    final dll = '$dir\\onnxruntime.dll';
    if (!File(dll).existsSync()) continue;
    final extra = dir != exeDir;
    try {
      if (extra) {
        // las DLL del paquete (cuDNN, cuBLAS, OpenVINO…) se buscan en su carpeta
        _setDllDirectory(k32, dir);
        _setEnv(k32, 'PATH', '$dir;${_getEnv(k32, 'PATH') ?? ''}');
      }
      final lib = DynamicLibrary.open(dll);
      _setEnv(k32, 'HERRERO_ORT_DIR', dir);
      return lib;
    } catch (_) {
      if (extra) _setDllDirectory(k32, null);
    }
  }
  // sin alternativa: el de la app, por ruta completa (el error dirá qué falta)
  return DynamicLibrary.open('$exeDir\\onnxruntime.dll');
}
