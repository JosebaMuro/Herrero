import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/engine/designer.dart';
import 'package:herrero/engine/model.dart';
import 'package:herrero/engine/parser.dart';
import 'package:herrero/engine/profiles.dart';
import 'package:herrero/screens/home_screen.dart' show examples;

void main() {
  test('marquesina de Joseba: panel sándwich, galvanizada', () {
    const p = 'Marquesina para 2 coches de 5,5 x 5 m y 2,4 m de alto, panel Sandwich , galvanizada';
    final s = parsePrompt(p);
    expect(s.type, StructureType.marquesina);
    expect(s.roofing, startsWith('panel sándwich'));
    expect(s.finish.toLowerCase(), contains('galvaniz'));
    expect(s.grade.name, 'S275JR');
    expect(s.height, closeTo(2.4, 0.01));
    final d = designFromSpec(s, p);
    expect(d.hypotheses.join(' '), contains('sándwich'));
    expect(d.checks, isNotEmpty);
    // ignore: avoid_print
    print({for (final m in d.members) m.profile.name});
  });

  test('perfiles por partes', () {
    final t = normalize('Nave de 20 x 12 m, 6 m de alto, pilares HEB 220, correas de tubo 100x100, tirantes de redondo 16, vigas IPE');
    final parts = partProfiles(t);
    expect(parts['pilares'], 'HEB 220');
    expect(parts['correas'], 'SHS 100x*');
    expect(parts['arriostramiento'], 'R16');
    expect(parts['vigas'], 'ipe');
  });

  test('forma inversa y HEA', () {
    final notes = <String>[];
    final parts = partProfiles(normalize('Porche con HEA 160 en los pilares y tubo rectangular para las vigas'), notes);
    expect(parts['pilares'], 'HEB 160');
    expect(parts['vigas'], 'rhs');
    expect(notes.join(), contains('HEA 160'));
  });

  test('sin perfiles: la app elige', () {
    expect(partProfiles(normalize('Nave de 30 x 15 m con pilares cada 5 m de 6 m de alto')), isEmpty);
    expect(partProfiles(normalize('Escalera recta con barandilla de 1 m de alto')), isEmpty);
  });

  test('el diseño respeta el perfil impuesto', () {
    const p = 'Nave de 20 x 12 m, 6 m de alto, pilares HEB 260, correas de tubo';
    final d = designFromPrompt(p);
    final cols = d.members.where((m) => m.role == MemberRole.column).map((m) => m.profile.name).toSet();
    expect(cols, {'HEB 260'});
    final purl = d.members.where((m) => m.role == MemberRole.purlin).map((m) => m.profile.family).toSet();
    expect(purl.every((f) => f == ProfileFamily.shs || f == ProfileFamily.rhs), isTrue);
    expect(d.hypotheses.join(' '), contains('pilares: HEB 260'));
  });

  test('materiales: aluminio, inox y cubiertas', () {
    final a = parsePrompt('Pérgola de aluminio de 4 x 3 m con policarbonato celular de 16 mm');
    expect(a.grade.kind, MaterialKind.aluminium);
    expect(a.roofing, 'policarbonato celular 16 mm');
    final i = parsePrompt('Barandilla de acero inoxidable 316 de 6 m');
    expect(i.grade.kind, MaterialKind.stainless);
    final n = parsePrompt('Nave de 20 x 10 m, cubierta de panel sándwich de 60 mm, cerramiento de chapa');
    expect(n.roofing, 'panel sándwich 60 mm');
    expect(n.cladding, 'chapa');
    final m = designFromPrompt('Marquesina de 6 x 5 m en acero corten');
    expect(m.spec.grade.kind, MaterialKind.weathering);
    expect(m.welds.every((w) => w.process.contains('Ni')), isTrue);
  });

  test('ejemplos de la pantalla de inicio', () {
    for (final e in examples) {
      final d = designFromPrompt(e);
      expect(d.checks, isNotEmpty, reason: e);
      // ignore: avoid_print
      print('${d.spec.type.name.padRight(12)} ${d.spec.grade.name.padRight(8)} ${d.spec.finish.padRight(28)} ${d.spec.roofing.padRight(26)} ${d.spec.parts}  η=${d.maxUtilization.toStringAsFixed(2)}');
    }
  });
}
