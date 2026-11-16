import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/engine/designer.dart';
import 'package:herrero/engine/model.dart';
import 'package:herrero/engine/parser.dart';

void main() {
  test('parser nave', () {
    final s = parsePrompt('Nave a dos aguas de 30 x 15 metros, 6 m de altura al alero, pórticos cada 6 m, panel sándwich, en Vitoria');
    expect(s.type, StructureType.nave);
    expect(s.length, 30);
    expect(s.width, 15);
    expect(s.height, 6);
    expect(s.bay, 6);
    expect(s.snow, 0.7);
  });
  test('parser marquesina', () {
    final s = parsePrompt('Marquesina para 2 coches de 5,5x5 m y 2,4 de alto galvanizada');
    expect(s.type, StructureType.marquesina);
    expect(s.length, 5.5);
    expect(s.width, 5);
    expect(s.height, 2.4);
  });
  test('parser entreplanta', () {
    final s = parsePrompt('Altillo de 8 x 4 a 3 m de altura para almacén');
    expect(s.type, StructureType.entreplanta);
    expect(s.liveLoad, 5);
  });
  for (final p in [
    'Nave a dos aguas de 30 x 15 metros, 6 m de altura al alero, pórticos cada 6 m, panel sándwich, en Vitoria',
    'Nave de 40x20 altura 7 m en León',
    'Marquesina para 2 coches de 5,5x5 m y 2,4 de alto galvanizada',
    'Pérgola de 4x3 sin cubierta',
    'Altillo de 8 x 4 a 3 m de altura para almacén',
    'Entreplanta de oficinas 12x9 altura 3,2 tramex',
  ]) {
    test('design $p', () {
      final d = designFromPrompt(p);
      print('--- $p');
      print('${d.spec.type} L=${d.spec.length} W=${d.spec.width} H=${d.spec.height} bay=${d.spec.bay}');
      for (final pc in d.pieces) {
        print('${pc.mark} ${pc.description} ${pc.profile.name} ${pc.lengthMm} x${pc.qty} ${pc.totalKg.toStringAsFixed(0)}kg');
      }
      for (final c in d.checks) {
        print('  ${c.element}: ${c.description} η=${c.utilization.toStringAsFixed(2)}');
      }
      for (final s in d.stock) {
        print('  stock ${s.profile.name}: ${s.bars} x ${s.barLength} waste ${s.wastePct.toStringAsFixed(1)}%');
      }
      print('kg=${d.steelKg.toStringAsFixed(0)} soldadura=${d.weldMeters.toStringAsFixed(1)} m');
      expect(d.members, isNotEmpty);
      expect(d.steelKg, greaterThan(0));
    });
  }
}
