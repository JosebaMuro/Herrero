import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:herrero/engine/designer.dart';
import 'package:herrero/engine/model.dart';
import 'package:herrero/engine/normativa.dart';
import 'package:herrero/engine/parser.dart';
import 'package:herrero/engine/spanish.dart';
import 'package:herrero/engine/vocabulary.dart';
import 'package:herrero/screens/catalog_screen.dart';

Fabrication fab(String s) => readFabrication(canonicalize(normalize(s)));

void main() {
  group('requisitos de soldadura en la descripción', () {
    test('proceso, calidad, clase de ejecución y ensayos', () {
      final f = fab('Pórtico soldado con TIG, calidad B, EXC3, uniones a tope con penetración completa y radiografiado');
      expect(f.process, startsWith('141'));
      expect(f.quality, 'B');
      expect(f.exc, 3);
      expect(f.ndt, contains('RT'));
      expect(f.fullPenetration, isTrue);
    });
    test('nombres de taller de los procesos', () {
      expect(fab('soldadura de hilo').process, startsWith('135'));
      expect(fab('todo soldado con electrodo').process, startsWith('111'));
      expect(fab('soldadura MIG').process, startsWith('131'));
      expect(fab('hilo tubular en obra').process, startsWith('136'));
      expect(fab('una escalera de 3 m').process, isEmpty);
    });
    test('por defecto EXC2 y calidad C', () {
      final f = fab('marquesina de 5 x 5 m');
      expect(f.isEmpty, isTrue);
      expect(f.execClass, 2);
      expect(f.qualityLevel, 'C');
      expect(fab('EXC1').qualityLevel, 'D');
      expect(fab('nivel de calidad B').execClass, 3);
    });
    test('ambiente corrosivo', () {
      expect(fab('pérgola junto al mar').corrosivity, 'C4');
      expect(fab('pasarela en el muelle').corrosivity, 'C5');
      expect(fab('estructura en ambiente C3').corrosivity, 'C3');
      expect(fab('cubierta para la piscina').corrosivity, 'C4');
    });
    test('calderería y equipos a presión', () {
      expect(fab('calderín de aire comprimido a 8 bar').pressure, isTrue);
      expect(fab('torre para un depósito de agua').vessel, isTrue);
      expect(fab('torre para un depósito de agua').pressure, isFalse);
    });
  });

  group('aplica la normativa al diseño', () {
    test('el proceso pedido llega a la tabla de soldaduras con su consumible', () {
      final d = designFromPrompt('Barandilla de inox 316 de 8 m soldada con TIG, junto al mar');
      expect(d.welds, isNotEmpty);
      expect(d.welds.every((w) => w.process.startsWith('141')), isTrue);
      expect(d.welds.first.process, contains('316'));
      expect(d.hypotheses.join(' '), contains('decapado y pasivado'));
      expect(d.norms.map((n) => n.code), containsAll(['CTE DB-SUA 1', 'UNE-EN 10088', 'UNE-EN ISO 4063']));
    });
    test('clase de ejecución y calidad en la memoria', () {
      final d = designFromPrompt('Nave de 20 x 12 m, ejecución EXC3, ultrasonidos en las uniones a tope con penetración completa');
      final h = d.hypotheses.join(' ');
      expect(h, contains('clase EXC3'));
      expect(h, contains('nivel B'));
      expect(h, contains('ultrasonidos'));
      expect(d.warnings.join(' '), contains('EN ISO 3834-2'));
    });
    test('el caso de la marquesina galvanizada pide venteos', () {
      final d = designFromPrompt('Marquesina para 2 coches de 5,5 x 5 m y 2,4 m de alto, panel sándwich, galvanizada');
      expect(d.hypotheses.join(' '), contains('venteo'));
      expect(d.hypotheses.join(' '), contains('clase EXC2'));
      expect(d.norms.map((n) => n.code), contains('UNE-EN ISO 1461'));
      expect(d.norms.map((n) => n.code), isNot(contains('UNE-EN 13445')));
    });
    test('avisos de oficio', () {
      expect(designFromPrompt('Torre de 4 m para un calderín a presión de 10 bar').warnings.join(' '), contains('UNE-EN 13445'));
      expect(designFromPrompt('Pérgola de 4 x 3 m con cordones discontinuos, junto al mar').warnings.join(' '),
          allOf(contains('Cordones discontinuos'), contains('galvanizado')));
      expect(designFromPrompt('Cancela corredera motorizada de 4 m').warnings.join(' ') +
              designFromPrompt('Cancela corredera motorizada de 4 m').hypotheses.join(' '),
          contains('12453'));
      expect(designFromPrompt('Pérgola de aluminio de 4 x 3 m soldada con electrodo').warnings.join(' '),
          contains('MIG (131) o TIG (141)'));
    });
  });

  group('biblioteca y vocabulario', () {
    test('normas con resumen y área conocida', () {
      expect(normLibrary.length, greaterThan(40));
      for (final n in normLibrary) {
        expect(normAreas, contains(n.area), reason: n.code);
        expect(n.summary.length, greaterThan(40), reason: n.code);
        if (n.when != null) RegExp(n.when!);
      }
    });
    test('todas las categorías del glosario tienen términos', () {
      for (final c in glossaryCategories) {
        expect(glossary.where((t) => t.category == c), isNotEmpty, reason: c);
      }
      expect(glossary.map((t) => t.category).toSet().difference(glossaryCategories.toSet()), isEmpty);
    });
    test('el diccionario entiende las palabras de soldadura y calderería', () {
      String fix(String s) => fixSpanish(normalize(s));
      expect(fix('soldado con electrdo'), contains('electrodo'));
      expect(fix('radiografiaddo'), contains('radiografiado'));
      expect(fix('depósito de dos birolas'), contains('virolas'));
      expect(fix('cordones continuos'), contains('continuos'));
      expect(fix('cuatro metros'), contains('cuatro'));
      expect(parsePrompt('escalera de 3 m soldada con hilo').type, StructureType.escalera);
    });
  });

  testWidgets('pestaña Normativa con buscador', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CatalogScreen()));
    await tester.tap(find.text('Normativa'));
    await tester.pumpAndSettle();
    expect(find.text('CTE DB-SE-A'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'radiograf');
    await tester.pumpAndSettle();
    expect(find.text('UNE-EN ISO 17636'), findsOneWidget);
    expect(find.text('CTE DB-SE-A'), findsNothing);
  });
}
