import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/ai/model_gate.dart';
import 'package:herrero/ai/model_manager.dart';
import 'package:herrero/engine/budget.dart';
import 'package:herrero/engine/designer.dart';
import 'package:herrero/engine/pricing.dart';
import 'package:herrero/plans/pdf_text.dart';
import 'package:herrero/services/export.dart';
import 'package:herrero/services/geo.dart';

String _text(Uint8List pdf) => PdfTextReader.read(pdf, maxPages: 40).tokens.map((t) => t.text).join(' ');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final out = Platform.environment['HERRERO_OUT'];
  setUpAll(() async {
    final loader = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    await loader.load();
  });

  const prompt = 'Marquesina para 2 coches de 5,5 x 5 m y 2,4 m de alto, panel sándwich, galvanizada';

  testWidgets('cada apartado sale aislado, con destinatario y numeración propia', (tester) async {
    await tester.runAsync(() async {
      final d = designFromPrompt(prompt);
      const info = ProjectInfo(name: 'Marquesina Garaje Pérez', client: 'Ana Pérez', site: 'Vitoria');
      for (final s in [ProjectSection.materiales, ProjectSection.soldadura, ProjectSection.montaje]) {
        final pdf = await buildSectionsPdf(d, [s], info: info);
        final t = _text(pdf);
        expect(t, contains(s.label.toUpperCase()), reason: s.name);
        expect(t, contains('Para: ${s.recipient}'), reason: s.name);
        expect(t, contains('${s.label} · pág. 1 de'), reason: s.name);
        expect(t, contains('Ana Pérez'));
        if (out != null) File('$out/seccion_${s.fileSuffix}.pdf').writeAsBytesSync(pdf);
      }
      // el apartado de materiales no lleva precios ni el de soldadura el despiece de compras
      final mat = _text(await buildSectionsPdf(d, [ProjectSection.materiales]));
      expect(mat, isNot(contains('€')));
      expect(mat, contains('Pedido de barras comerciales'));
      final sold = _text(await buildSectionsPdf(d, [ProjectSection.soldadura]));
      expect(sold, contains('Uniones soldadas'));
      expect(sold, isNot(contains('Pedido de barras')));

      // dos apartados en un PDF: la numeración vuelve a empezar en cada uno
      final both = _text(await buildSectionsPdf(d, [ProjectSection.materiales, ProjectSection.soldadura]));
      expect(both, contains('Materiales y pedido · pág. 1 de'));
      expect(both, contains('Soldadura · pág. 1 de'));

      // presupuesto
      final b = PriceBook()..upsertSupplier(Supplier(id: 'a', name: 'Hierros'));
      b.addPrices([
        for (final r in ['IPE', 'HEB', 'SHS', 'RHS', 'UPN', 'L', 'CHS'])
          PriceEntry(supplierId: 'a', ref: '$r 1', description: r, unit: PriceUnit.kg, price: 1.2, date: DateTime.now(), source: PriceSource.factura),
      ]);
      final bud = buildBudget(d, b, const PriceQuery(), WorkshopRates(hourly: 38));
      final pres = await buildSectionsPdf(d, [ProjectSection.presupuesto], budget: bud, info: info);
      final pt = _text(pres);
      expect(pt, contains('TOTAL'));
      expect(pt, contains('SIN PRECIO')); // galvanizado y tornillería sin precio en la base
      if (out != null) File('$out/seccion_presupuesto.pdf').writeAsBytesSync(pres);
    });
  });

  group('turnos de modelos', () {
    test('decide por RAM y modo', () {
      expect(needsMemorySaving(MemoryMode.automatico, 4), isTrue);
      expect(needsMemorySaving(MemoryMode.automatico, 16), isFalse);
      expect(needsMemorySaving(MemoryMode.automatico, 0), isFalse); // RAM desconocida
      expect(needsMemorySaving(MemoryMode.siempre, 32), isTrue);
      expect(needsMemorySaving(MemoryMode.nunca, 2), isFalse);
    });

    test('con poca RAM, cambiar de paso cancela los modelos que no tocan', () async {
      final g = ModelGate.instance
        ..mode = MemoryMode.automatico
        ..ramOverride = 4;
      var llmCancelled = false, photoCancelled = false, dropped = 0;
      g.onDropCaches(() => dropped++);
      g.enter(WorkflowStep.comprension);
      final release = g.hold(ModelTask.reason, () => llmCancelled = true);
      expect(g.activeTasks, [ModelTask.reason]);
      g.enter(WorkflowStep.comprension); // mismo paso: sigue
      expect(llmCancelled, isFalse);
      g.enter(WorkflowStep.foto); // la foto no usa el LLM
      expect(llmCancelled, isTrue);
      expect(dropped, greaterThan(0));
      release();
      // un modelo cada vez: abrir la foto cancela otro trabajo largo
      g.hold(ModelTask.sketch, () => photoCancelled = true);
      g.hold(ModelTask.photo, () {});
      expect(photoCancelled, isTrue);
      expect(g.activeTasks, [ModelTask.photo]);
      // trabajos cortos en fila
      final order = <int>[];
      final a = g.run(ModelTask.plans, () async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        order.add(1);
      });
      final b2 = g.run(ModelTask.plans, () async => order.add(2));
      await Future.wait([a, b2]);
      expect(order, [1, 2]);
      g.ramOverride = 32;
      var kept = true;
      g.hold(ModelTask.reason, () => kept = false);
      g.enter(WorkflowStep.foto);
      expect(kept, isTrue, reason: 'con RAM de sobra no se cancela nada');
      g.ramOverride = null;
    });
  });

  group('mapa y webs', () {
    test('consulta y lectura de distribuidores de OpenStreetMap', () {
      final q = distributorsQuery(const GeoPoint(42.85, -2.67), 40);
      expect(q, contains('around:40000,42.85000,-2.67000'));
      final list = parseDistributors('''
{"elements":[
 {"type":"node","id":1,"lat":42.86,"lon":-2.70,"tags":{"name":"Hierros Júndiz","shop":"trade","phone":"+34 945 000 000","addr:street":"Lermandabide","addr:city":"Vitoria"}},
 {"type":"way","id":2,"center":{"lat":42.9,"lon":-2.6},"tags":{"name":"Galvanizados Norte","industrial":"factory","website":"galvanorte.es"}},
 {"type":"node","id":3,"lat":42.9,"lon":-2.6,"tags":{"shop":"trade"}}
]}''');
      expect(list.length, 2);
      expect(list.first.phone, contains('945'));
      expect(list.first.address, contains('Vitoria'));
      expect(list.last.location!.lat, 42.9);
      expect(list.every((s) => s.source == SupplierSource.mapa), isTrue);
    });

    test('texto de una página de tarifas', () {
      final t = htmlToText('<table><tr><td>IPE 200</td><td>1,10 &euro;/kg</td></tr><tr><td>Tubo 40x40x2</td><td>2,35 €/m</td></tr></table>');
      expect(t.split('\n').length, 2);
      expect(t, contains('1,10 €/kg'));
    });
  });
}
