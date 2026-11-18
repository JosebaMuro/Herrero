import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:herrero/engine/formacion.dart';
import 'package:herrero/screens/catalog_screen.dart';

void main() {
  group('biblioteca de formación', () {
    test('todas las fichas tienen área conocida, texto y enlaces https', () {
      expect(trainingLibrary.length, greaterThan(30));
      for (final t in trainingLibrary) {
        expect(trainingAreas, contains(t.area), reason: t.code);
        expect(t.summary.length, greaterThan(40), reason: t.code);
        for (final l in t.links) {
          expect(Uri.parse(l.url).scheme, 'https', reason: '${t.code}: ${l.url}');
          expect(l.label, isNotEmpty);
        }
      }
      for (final a in trainingAreas) {
        expect(trainingLibrary.any((t) => t.area == a), isTrue, reason: a);
      }
    });
    test('códigos únicos y títulos clave presentes', () {
      final codes = trainingLibrary.map((t) => t.code).toList();
      expect(codes.toSet().length, codes.length);
      for (final c in [
        'Técnico en Soldadura y Calderería',
        'Técnico Superior en Construcciones Metálicas',
        'FMEC0119_2',
        'FMEC0219_2',
        'FMEC0319_2',
        'FMEC0208',
        'FME035_2',
        'UNE-EN ISO 9606-1',
        'IIW / EWF',
      ]) {
        expect(codes, contains(c));
      }
    });
    test('las fichas de FP y certificados enlazan una fuente oficial', () {
      const official = ['todofp.es', 'boe.es', 'incual.educacion.gob.es', 'sepe.es', 'sepe.gob.es', 'lanbide.eus'];
      for (final t in trainingLibrary.where((t) =>
          t.area == 'FP del sistema educativo' ||
          t.area == 'Certificados profesionales (empleo)' ||
          t.area == 'Cualificaciones del INCUAL')) {
        expect(t.links.any((l) => official.any((d) => Uri.parse(l.url).host.endsWith(d))), isTrue, reason: t.code);
      }
    });
  });

  testWidgets('pestaña Formación con buscador', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CatalogScreen()));
    await tester.ensureVisible(find.text('Formación'));
    await tester.tap(find.text('Formación'));
    await tester.pumpAndSettle();
    expect(find.text('TodoFP'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'TIG');
    await tester.pumpAndSettle();
    expect(find.text('FMEC0219_2'), findsOneWidget);
    expect(find.text('TodoFP'), findsNothing);
    await tester.tap(find.text('FMEC0219_2'));
    await tester.pumpAndSettle();
    expect(find.byType(ActionChip), findsWidgets);
  });
}
