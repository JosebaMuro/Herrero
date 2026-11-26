import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/ai/photo_prompt.dart';
import 'package:herrero/engine/comprehension_aids.dart';
import 'package:herrero/engine/designer.dart';
import 'package:herrero/engine/material_catalog.dart';
import 'package:herrero/engine/model.dart';
import 'package:herrero/engine/parser.dart';
import 'package:herrero/engine/profiles.dart';
import 'package:herrero/engine/understanding.dart';
import 'package:herrero/views/render_view.dart' show Finish;

const balcon = 'Barandilla de balcon formada por 5 listones frontales de 20×50 mm horizontales, con llanta de 30×5 mm '
    'vertical en extremos y centro y 170 mm de llanta hacia el interior en parte superior e inferior. Tiene una altura '
    'exterior de 390 mm e interior de 685 mm para union por el interior de la fachada del balcon. Lleva a media altura '
    'entre las llantas, apolladas y soldadas longitudinal para poner tiestos.';

void main() {
  test('el catálogo no repite ids ni deja materiales sin nombre o sin foto', () {
    final ids = materialCatalog.map((m) => m.id).toSet();
    expect(ids.length, materialCatalog.length);
    for (final m in materialCatalog) {
      expect(m.aka, isNotEmpty, reason: m.id);
      expect(m.photo, isNotEmpty, reason: m.id);
      for (final a in m.aka) {
        expect(a, normalize(a), reason: 'sinónimo sin normalizar en ${m.id}: $a');
      }
    }
  });

  test('reconoce materiales por sus nombres y regionalismos', () {
    expect(materialsIn('cubierta de calaminón').map((m) => m.id), ['chapa-grecada']);
    expect(materialsIn('techo de calamina').map((m) => m.id), ['chapa-ondulada']);
    expect(materialsIn('policarbonato compacto de 6 mm').map((m) => m.id), ['policarbonato-compacto']);
    expect(materialsIn('IPN 200 y UPN 120').map((m) => m.id), ['ipn', 'upn']);
    expect(materialsIn('llanta de 30x5').map((m) => m.id), ['llanta']);
    expect(materialsIn('suelo de chapa estriada').map((m) => m.id), ['chapa-lagrimada']);
    expect(materialsIn('barandilla de cristal').map((m) => m.id), ['vidrio-laminado']);
    expect(materialFor('panel sándwich 40 mm')!.id, 'panel-sandwich');
    expect(materialFor('panel sándwich', groups: {MatGroup.cerramiento})!.id, 'panel-fachada');
    expect(materialFor('sin cubierta (pérgola abierta)'), isNull);
  });

  test('la cubierta del catálogo llega a la ficha, al peso y a la foto', () {
    final s = parsePrompt('cobertizo de 5 x 3 m con techo de calamina');
    expect(s.roofing, 'chapa ondulada');
    final d = designFromSpec(s, 'cobertizo de 5 x 3 m con techo de calamina');
    expect(d.hypotheses.join(' ') + d.checks.map((c) => c.detail).join(' '), isNot(contains('NaN')));
    final p = photoPrompt(d, Finish.galvanizado, PhotoScene.sunny);
    expect(p, contains('galvanized corrugated wavy metal roof sheets'));
    expect(parsePrompt('caseta de 3 x 2 con cubierta de onduline').roofing, contains('placa asfáltica'));
    final n = parsePrompt('tejavana de 6 x 4 con calaminón');
    expect(n.roofing, 'chapa grecada');
    expect(n.notes.join(' '), contains('Calaminón'));
  });

  test('la IA recibe los materiales citados y las secciones no se leen como medidas', () {
    final u = llmUser(balcon);
    expect(u, contains('Materiales citados'));
    expect(u, contains('Llanta / pletina'));
    expect(u, isNot(contains('50 m («')));
    expect(u, contains('0,685 m'));
    expect(u, isNot(contains('Cordón superior')));
    final f = readFacts(balcon);
    expect(f.where((x) => x.label.startsWith('sección')).length, 2);
    expect(f.firstWhere((x) => x.field == 'height').value, closeTo(0.685, 1e-9));
    expect(maskSections('tubo 80x80 de 3 m').contains('80'), isFalse);
    expect(maskSections('marquesina de 5 x 3 m'), 'marquesina de 5 x 3 m');
  });

  test('barandilla sobre peto del texto de prueba', () {
    final u = understand(balcon);
    final s = u.spec;
    expect(u.type, StructureType.barandilla);
    expect(s.variant, 'sobre peto · tiestos');
    expect(s.height, closeTo(0.685, 1e-9));
    expect(s.length, 3.0); // no dice la longitud: la de un balcón
    final d = designFromSpec(s, balcon);
    final posts = d.members.where((m) => m.role == MemberRole.post).toList();
    expect(posts.length, 6); // 3 montantes (extremos y centro), cara exterior e interior
    expect(posts.every((m) => m.profile.name == 'Pletina 30x5'), isTrue);
    final slats = d.members.where((m) => m.profile.name == 'RHS 50x20x2').toList();
    expect(slats.length, 5);
    final returns = d.members.where((m) => m.role == MemberRole.bracket).toList();
    expect(returns.length, 9); // superior, inferior y de tiestos en cada montante
    expect(returns.first.length, closeTo(0.17, 1e-9));
    expect(d.members.where((m) => m.profile.family == ProfileFamily.round).length, 2); // redondos de tiestos
    expect(d.warnings.join(' '), contains('escalables'));
    expect(d.surfaces.where((x) => x.kind == SurfaceKind.wall), isNotEmpty); // se dibuja el peto
    final p = photoPrompt(d, Finish.negro, PhotoScene.sunny);
    expect(p, contains('parapet'));
  });
}
