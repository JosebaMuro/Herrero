import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/ai/accel.dart';
import 'package:onnxruntime/onnxruntime.dart';

/// Pruebas de la aceleración. La parte con ONNX Runtime real solo corre con
/// HERRERO_ORT_TEST=1 (CI de Windows con la DLL de DirectML de la app, o en local con
/// LD_LIBRARY_PATH apuntando a la biblioteca del paquete).
void main() {
  test('los índices guardados en ajustes no cambian', () {
    expect(AiEngine.auto.index, 0);
    expect(AiEngine.cpu.index, 1);
    expect(AiEngine.nnapi.index, 2);
    expect(enginesForPlatform(), containsAll([AiEngine.auto, AiEngine.cpu]));
  });

  test('Solo CPU no prueba ningún acelerador', () {
    expect(accelChain(AiEngine.cpu, quantized: false, available: const ['DmlExecutionProvider']), isEmpty);
  });

  test('en Windows, Automático elige el runtime cargado (CUDA > OpenVINO > DirectML)', () {
    final dml = accelChain(AiEngine.auto,
        quantized: true, available: const ['DmlExecutionProvider', 'CPUExecutionProvider']);
    final cuda = accelChain(AiEngine.auto,
        quantized: true, available: const ['CUDAExecutionProvider', 'CPUExecutionProvider']);
    final none = accelChain(AiEngine.cuda, quantized: true, available: const ['CPUExecutionProvider']);
    expect(none, isEmpty);
    if (Platform.isWindows) {
      expect(dml, [OrtEp.directml]);
      expect(cuda, [OrtEp.cuda]);
    }
  });

  final run = Platform.environment['HERRERO_ORT_TEST'] == '1';
  test('abre y ejecuta un modelo con el motor elegido y con vuelta a CPU', () async {
    OrtEnv.instance.init();
    final providers = ortProviders();
    // ignore: avoid_print
    print('Proveedores de ONNX Runtime: $providers');
    if (Platform.isWindows) {
      expect(providers, contains('DmlExecutionProvider'), reason: 'la app debe llevar ONNX Runtime con DirectML');
    }
    final engine = AiEngine.values.firstWhere((e) => e.name == (Platform.environment['HERRERO_ORT_ENGINE'] ?? 'auto'));
    for (final e in {engine, AiEngine.cpu}) {
      final o = ortOpenAccel('test${Platform.pathSeparator}data${Platform.pathSeparator}tiny_accel.onnx', 2, e,
          quantized: false);
      // ignore: avoid_print
      print('Motor ${e.name} -> ${o.ep.label}');
      final x = OrtValueTensor.createTensorWithDataList(Float32List.fromList([1, 1, 2, 0]), [2, 2]);
      final ro = OrtRunOptions();
      final out = o.session.run(ro, {'x': x});
      final y = (out[0]!.value as List).expand((r) => (r as List).cast<double>()).toList();
      expect(y, [5.5, 0, 10, 2.5, 0, 7]);
      for (final v in out) {
        v?.release();
      }
      x.release();
      ro.release();
      o.session.release();
    }
  }, skip: !run);
}
