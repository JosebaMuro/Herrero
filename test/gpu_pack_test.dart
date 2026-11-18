import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/ai/accel.dart';
import 'package:herrero/ai/model_manager.dart';

/// Descarga e instala de verdad un paquete de aceleración (solo Windows, CI manual):
/// HERRERO_PACK_TEST=cuda|openvino.
void main() {
  final id = Platform.environment['HERRERO_PACK_TEST'];
  test('instala el paquete $id', () async {
    final packs = GpuPacks.instance;
    final p = gpuPacks.firstWhere((p) => p.id == id);
    // ignore: avoid_print
    print('Ficheros: ${packs.filesFor(p).map((f) => f.name).toList()} (${packs.sizeOf(p)} bytes)');
    var last = -1;
    packs.addListener(() {
      final st = packs.status[p.id];
      final pc = ((st?.progress ?? 0) * 10).floor();
      if (pc != last) {
        last = pc;
        // ignore: avoid_print
        print('${st?.state} ${(100 * (st?.progress ?? 0)).toStringAsFixed(0)} %');
      }
    });
    await packs.install(p);
    final st = packs.status[p.id]!;
    // ignore: avoid_print
    print('Resultado: ${st.state} ${st.error ?? ''}');
    final dir = Directory(GpuPacks.dirFor(p.id)!);
    if (dir.existsSync()) {
      for (final f in dir.listSync()) {
        // ignore: avoid_print
        print('  ${f.path} ${f is File ? f.lengthSync() : ''}');
      }
    }
    expect(st.state, DlState.installed, reason: st.error);
  }, skip: id == null || !Platform.isWindows, timeout: const Timeout(Duration(minutes: 40)));
}
