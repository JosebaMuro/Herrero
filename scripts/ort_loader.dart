// Cargador de ONNX Runtime de Herrero para Windows y Linux.
//
// scripts/ort_runtime.py lo copia en el paquete `onnxruntime` como
// lib/src/bindings/herrero_loader.dart y hace que bindings.dart lo use en vez de
// DynamicLibrary.open('onnxruntime.dll') / ('libonnxruntime.so.1.15.1').
//
// Reglas en Windows:
// * Siempre por ruta completa: Windows trae un onnxruntime.dll antiguo en System32
//   y abrirlo por nombre puede devolver ese (v3.4.1).
// * Por defecto, el de la app (junto a herrero.exe): ONNX Runtime 1.20 con DirectML.
// * Si el usuario ha instalado un paquete de aceleración (CUDA u OpenVINO) y lo ha
//   elegido, se abre el de %LOCALAPPDATA%\Herrero\gpu\<paquete>\.
// * La elección se fija una vez por proceso en la variable HERRERO_ORT_DIR: todos los
//   isolates cargan la misma DLL (dos ONNX Runtime distintos en un proceso chocan).
//   También sirve para forzar una carpeta en las pruebas de CI.
//
// En Linux, lo mismo con ~/.local/share/herrero/gpu/<paquete>/ (o $XDG_DATA_HOME):
// * Por defecto, el de la app (bundle/lib/libonnxruntime.so.1.15.1, ONNX Runtime 1.20 CPU).
// * Con el paquete CUDA, su libonnxruntime.so. LD_LIBRARY_PATH no se puede cambiar con
//   el proceso ya arrancado, así que antes se precargan por ruta completa las bibliotecas
//   de NVIDIA del paquete (cudart, cuBLAS, cuFFT, cuRAND, NVRTC, cuDNN): cuando ONNX Runtime abre su
//   proveedor CUDA, el enlazador las encuentra ya cargadas por su soname.
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

DynamicLibrary herreroOpenOrt() => Platform.isLinux ? _openLinux() : _openWindows();

DynamicLibrary _openWindows() {
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

// ---------------------------------------------------------------------------
// Linux
// ---------------------------------------------------------------------------

typedef _GetEnvLC = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _SetEnvLC = Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32);
typedef _SetEnvLD = int Function(Pointer<Utf8>, Pointer<Utf8>, int);

/// getenv/setenv de libc: Platform.environment es una copia y los demás isolates no
/// verían el cambio.
String? _getEnvL(String name) {
  final f = DynamicLibrary.process().lookupFunction<_GetEnvLC, _GetEnvLC>('getenv');
  final n = name.toNativeUtf8();
  try {
    final r = f(n);
    return r == nullptr ? null : r.toDartString();
  } finally {
    calloc.free(n);
  }
}

void _setEnvL(String name, String value) {
  final f = DynamicLibrary.process().lookupFunction<_SetEnvLC, _SetEnvLD>('setenv');
  final n = name.toNativeUtf8();
  final v = value.toNativeUtf8();
  f(n, v, 1);
  calloc.free(n);
  calloc.free(v);
}

String? _linuxPackBase() {
  final xdg = _getEnvL('XDG_DATA_HOME');
  if (xdg != null && xdg.startsWith('/')) return '$xdg/herrero/gpu';
  final home = _getEnvL('HOME');
  return home == null || home.isEmpty ? null : '$home/.local/share/herrero/gpu';
}

String? _selectedPackLinux() {
  final base = _linuxPackBase();
  if (base == null) return null;
  final sel = File('$base/runtime.txt');
  if (!sel.existsSync()) return null;
  final id = sel.readAsStringSync().trim();
  if (id.isEmpty || !RegExp(r'^[a-z0-9_-]+$').hasMatch(id)) return null;
  final dir = '$base/$id';
  return File('$dir/installed.json').existsSync() ? dir : null;
}

/// Bibliotecas de NVIDIA del paquete, en cualquier orden: se reintenta hasta que no
/// se pueda cargar ninguna más (cada una necesita las anteriores ya cargadas).
void _preloadVendorLibs(String dir) {
  final re = RegExp(r'^lib(cudart|cublasLt|cublas|cufft|curand|cudnn[a-z_]*|nvrtc[a-z-]*|nvJitLink)\.so(\.\d+)*$');
  var pending = [
    for (final e in Directory(dir).listSync())
      if (e is File && re.hasMatch(e.uri.pathSegments.last)) e.path
  ]..sort();
  while (pending.isNotEmpty) {
    final failed = <String>[];
    for (final p in pending) {
      try {
        DynamicLibrary.open(p);
      } catch (_) {
        failed.add(p);
      }
    }
    if (failed.length == pending.length) break; // el resto no se puede cargar (falta algo del sistema)
    pending = failed;
  }
}

DynamicLibrary _openLinux() {
  final libDir = '${File(Platform.resolvedExecutable).parent.path}/lib';
  final candidates = <String>[];
  final fixed = _getEnvL('HERRERO_ORT_DIR');
  if (fixed != null && fixed.isNotEmpty) {
    candidates.add(fixed);
  } else {
    try {
      final pack = _selectedPackLinux();
      if (pack != null) candidates.add(pack);
    } catch (_) {}
  }
  if (!candidates.contains(libDir)) candidates.add(libDir);
  for (final dir in candidates) {
    final so = dir == libDir ? '$dir/libonnxruntime.so.1.15.1' : '$dir/libonnxruntime.so';
    if (!File(so).existsSync()) continue;
    try {
      if (dir != libDir) _preloadVendorLibs(dir);
      final lib = DynamicLibrary.open(so);
      _setEnvL('HERRERO_ORT_DIR', dir);
      return lib;
    } catch (_) {}
  }
  // sin alternativa: por nombre, como el paquete original (RPATH $ORIGIN/lib)
  return DynamicLibrary.open('libonnxruntime.so.1.15.1');
}
