import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/cad/sheets.dart';
import 'package:herrero/engine/designer.dart';
import 'package:herrero/engine/model.dart';

void main() {
  const prompts = {
    'escalera recta de 3 m de altura y 1 m de ancho': 'recta',
    'escalera en L de 3 m de altura y 1 m de ancho': 'en l',
    'escalera en U de 3,2 m de altura y 1,1 m de ancho': 'en u',
    'escalera de zanca central de 2,8 m de altura y 1 m de ancho': 'zanca central',
    'escalera de caracol de 3 m de altura': 'caracol',
    'escala de gato de 5 m para subir a la cubierta': 'escala de gato',
    'barandilla de vidrio de 8 m': 'vidrio',
    'barandilla de cables de 6 m': 'cables',
    'barandilla de chapa perforada de 5 m': 'chapa perforada',
    'barandilla con lamas de 5 m': 'lamas',
    'barandilla industrial con rodapie de 12 m para una plataforma': 'barrotes · rodapié',
    'pasamanos a pared de 4 m para la escalera': 'pasamanos a pared',
    'reja de ventana de 1,2 x 1,0 m': 'reja · barrotes',
  };
  for (final e in prompts.entries) {
    test(e.key, () {
      final d = designFromPrompt(e.key);
      expect(d.spec.variant, startsWith(e.value));
      expect(d.members, isNotEmpty);
      expect(d.pieces, isNotEmpty);
      expect(d.steelKg.isFinite && d.steelKg > 0, isTrue);
      for (final c in d.checks) {
        expect(c.utilization.isFinite, isTrue, reason: '${c.element} ${c.description}');
      }
      for (final m in d.members) {
        expect([m.a.x, m.a.y, m.a.z, m.b.x, m.b.y, m.b.z].every((v) => v.isFinite), isTrue);
      }
      final sheets = buildSheets(d);
      expect(sheets.length, greaterThanOrEqualTo(6));
      for (final s in sheets) {
        final (x0, y0, x1, y1) = s.bounds;
        expect(x0 >= -1 && y0 >= -1 && x1 <= s.width + 1 && y1 <= s.height + 1, isTrue, reason: '${s.number} se sale');
      }
    });
  }

  test('escalera en L y en U giran', () {
    final l = designFromPrompt('escalera en L de 3 m de altura y 1 m de ancho');
    final stringers = l.members.where((m) => m.role == MemberRole.stringer).toList();
    expect(stringers.any((m) => (m.b.x - m.a.x).abs() > 0.5), isTrue);
    expect(stringers.any((m) => (m.b.y - m.a.y).abs() > 0.5), isTrue);
    final u = designFromPrompt('escalera en U de 3 m de altura y 1 m de ancho');
    final dx = u.members.where((m) => m.role == MemberRole.stringer).map((m) => (m.b.x - m.a.x).sign).toSet();
    expect(dx, containsAll([1.0, -1.0]));
  });

  test('caracol: mástil, peldaños en abanico y aviso del CTE', () {
    final d = designFromPrompt('escalera de caracol de 3 m');
    expect(d.members.where((m) => m.role == MemberRole.column).single.profile.name, startsWith('CHS'));
    expect(d.checks.where((c) => c.element == 'Huella').every((c) => c.utilization <= 1), isTrue);
    expect(d.warnings.join(' '), contains('uso restringido'));
    // un Ø pequeño no cumple el ancho mínimo y se dice
    final small = designFromPrompt('escalera de caracol de 1,4 m de diametro y 3 m de altura');
    expect(small.checks.firstWhere((c) => c.element == 'Anchura útil').utilization, greaterThan(1));
  });

  test('escala de gato: jaula solo por encima de 3 m', () {
    final tall = designFromPrompt('escala de gato de 5 m');
    final low = designFromPrompt('escala de gato de 2,5 m');
    expect(tall.members.any((m) => m.role == MemberRole.frame), isTrue);
    expect(low.members.any((m) => m.role == MemberRole.frame), isFalse);
  });

  test('el vidrio no cuenta como acero', () {
    final glass = designFromPrompt('barandilla de vidrio de 8 m');
    final bars = designFromPrompt('barandilla de 8 m');
    expect(glass.steelKg, lessThan(bars.steelKg * 1.5));
    expect(glass.surfaces.where((s) => s.kind == SurfaceKind.glass), isNotEmpty);
  });

  test('cables: montantes de extremo reforzados y aviso de escalable', () {
    final d = designFromPrompt('barandilla de cables de 6 m');
    expect(d.checks.any((c) => c.element.startsWith('Montante de extremo')), isTrue);
    expect(d.warnings.join(' '), contains('escalable'));
  });

  test('reja: hueco ≤ 10 cm', () {
    final d = designFromPrompt('reja de forja para ventana de 1 m de ancho y 1,2 m de alto');
    expect(d.checks.firstWhere((c) => c.element == 'Barrotes').utilization, lessThanOrEqualTo(1));
    expect(d.members.where((m) => m.role == MemberRole.baluster).first.profile.name, 'R16');
  });
}
