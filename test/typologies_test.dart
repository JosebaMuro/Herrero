import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/engine/catalog.dart';
import 'package:herrero/engine/designer.dart';
import 'package:herrero/engine/model.dart';
import 'package:herrero/engine/parser.dart';

void _dump(Design d) {
  // ignore: avoid_print
  print('--- ${d.spec.type} L=${d.spec.length} W=${d.spec.width} H=${d.spec.height} '
      'P=${d.spec.pointLoad} lev=${d.spec.levels} var=${d.spec.variant} kg=${d.steelKg.toStringAsFixed(0)} '
      'members=${d.members.length} surf=${d.surfaces.length}');
  for (final pc in d.pieces) {
    // ignore: avoid_print
    print('  ${pc.mark} ${pc.description} ${pc.profile.name} ${pc.lengthMm} x${pc.qty}');
  }
  for (final c in d.checks) {
    // ignore: avoid_print
    print('  ✓ ${c.element}: ${c.description} η=${c.utilization.toStringAsFixed(2)}');
  }
  for (final n in [...d.spec.notes, ...d.warnings]) {
    // ignore: avoid_print
    print('  · $n');
  }
}

void main() {
  for (final t in typologies) {
    test('ejemplo ${t.type.name}', () {
      final s = parsePrompt(t.example);
      expect(s.type, t.type, reason: t.example);
      final d = designFromPrompt(t.example);
      _dump(d);
      expect(d.members, isNotEmpty);
      expect(d.pieces, isNotEmpty);
      expect(d.steelKg, greaterThan(0));
      expect(d.steelKg.isFinite, isTrue);
      for (final c in d.checks) {
        expect(c.utilization.isFinite, isTrue, reason: '${c.element} ${c.description}');
      }
      for (final m in d.members) {
        expect(m.a.x.isFinite && m.a.y.isFinite && m.a.z.isFinite, isTrue);
        expect(m.b.x.isFinite && m.b.y.isFinite && m.b.z.isFinite, isTrue);
      }
    });
  }

  const variants = {
    'escalera de caracol de 3 m': StructureType.escalera,
    'escalera exterior de 5 m de altura con meseta': StructureType.escalera,
    'puente peatonal de 15 m sobre un arroyo': StructureType.pasarela,
    'pasamanos para rampa de 6 m': StructureType.barandilla,
    'baranda de acero inoxidable con vidrio de 8 m': StructureType.barandilla,
    'cerchas a dos aguas para cubrir un patio de 8 x 12 sobre pilares de 3 m': StructureType.cercha,
    'cuchillos de cordones paralelos de 12 m de luz': StructureType.cercha,
    'bancada para máquinas de 3 x 2 a 1,5 m': StructureType.torre,
    'plataforma elevada de 2 x 2 a 6 m para depósito de 10.000 litros': StructureType.torre,
    'estantería de baldas de 3 m x 0,6 x 2,5 con 5 baldas': StructureType.estanteria,
    'rack para palés de 3 alturas': StructureType.estanteria,
    'portón abatible de dos hojas de 4 m': StructureType.cancela,
    'puerta peatonal de 1 m con chapa': StructureType.cancela,
    'cerramiento de malla electrosoldada de 50 m': StructureType.valla,
    'cerca de parcela de 40 m con chapa': StructureType.valla,
    'grúa pórtico para polipasto de 2 t y 5 m de luz': StructureType.portico,
    'mástil para bandera de 8 m': StructureType.poste,
    'báculo de farola de 6 m': StructureType.poste,
    'pérgola de 4 x 3 para terraza': StructureType.marquesina,
    'cobertizo de 6 x 4 para leña': StructureType.marquesina,
    'altillo de 6 x 5': StructureType.entreplanta,
    'nave de 20 x 12 en Burgos': StructureType.nave,
  };
  for (final e in variants.entries) {
    test('variante ${e.key}', () {
      final s = parsePrompt(e.key);
      expect(s.type, e.value, reason: e.key);
      final d = designFromPrompt(e.key);
      _dump(d);
      expect(d.members, isNotEmpty);
      expect(d.steelKg.isFinite && d.steelKg > 0, isTrue);
    });
  }

  group('vocabulario', () {
    test('números con letra', () {
      final s = parsePrompt('escalera de tres metros y medio de altura');
      expect(s.type, StructureType.escalera);
      expect(s.height, 3.5);
    });
    test('miles', () {
      expect(parsePrompt('soporte para deposito de cinco mil litros').pointLoad, closeTo(55, 1));
      expect(parsePrompt('torre para deposito de 10.000 litros').pointLoad, closeTo(110, 1));
    });
    test('antioxidante no es corten', () {
      expect(parsePrompt('barandilla de 6 m con pintura antioxidante').finish, isNot(contains('corten')));
    });
    test('hasta no es asta', () {
      expect(parsePrompt('valla de 20 m hasta 2 m de alto').type, StructureType.valla);
    });
    test('cumbrera', () {
      final s = parsePrompt('nave de 20x12 con altura a cumbrera de 7 m');
      expect(s.height, lessThan(7));
      expect(s.height, greaterThan(5));
    });
    test('regionalismos', () {
      expect(parsePrompt('galpón de 30 x 15').type, StructureType.nave);
      expect(parsePrompt('tranquera de 4 m').type, StructureType.cancela);
      expect(parsePrompt('cuchillos de 9 m de luz').type, StructureType.cercha);
      expect(parsePrompt('pretil de 12 metros').type, StructureType.barandilla);
      expect(parsePrompt('asta de bandera de 7 m').type, StructureType.poste);
      expect(parsePrompt('tecle de 2 tn').type, StructureType.portico);
    });
    test('acabados', () {
      expect(parsePrompt('portón de 5 m lacado en blanco').finish, 'lacado en blanco');
      expect(parsePrompt('valla galva de 20 ml').finish, contains('galvanizado'));
      expect(parsePrompt('valla galva de 20 ml').length, 20);
    });
    test('faltas', () {
      expect(parsePrompt('nave de 20x10 con panel sanwich').roofing, contains('sándwich'));
    });
  });
}
