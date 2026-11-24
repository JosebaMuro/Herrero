import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/engine/budget.dart';
import 'package:herrero/engine/designer.dart';
import 'package:herrero/engine/invoice_parser.dart';
import 'package:herrero/engine/pricing.dart';
import 'package:herrero/engine/spec_json.dart';
import 'package:herrero/services/project_store.dart';

const _factura = '''
HIERROS DEL NORTE, S.L.
Pol. Ind. Júndiz, C/ Lermandabide 12
01015 Vitoria-Gasteiz
CIF: B-01234567   Tel. 945 123 456
info@hierrosnorte.es
FACTURA Nº: F-2026/0451
Fecha: 14/10/2026
CLIENTE: TALLERES HERRERO S.L.  B98765432
Código Descripción Cantidad Precio Dto Importe
00123 VIGA IPE-200 S275JR 12M 539,40 KG 1,08 582,55
00456 TUBO EST. 80X80X3 S275 6M 120,00 KG 1,32 5 150,48
00789 CHAPA LAM. 10MM 3000X1500 S275 353,25 KG 1,02 360,32
00999 TORNILLO DIN 931 M16X40 8.8 GALV 100 UD 0,38 38,00
PORTES 1 25,00 25,00
BASE IMPONIBLE 1.156,35
IVA 21% 242,83
TOTAL 1.399,18
''';

void main() {
  group('parseMaterial', () {
    test('perfiles y tubos', () {
      expect(parseMaterial('VIGA IPE-200 S275JR')!.key, 'IPE 200');
      expect(parseMaterial('HEB220')!.key, 'HEB 220');
      expect(parseMaterial('TUBO EST. 80X80X3')!.key, 'SHS 80x3');
      expect(parseMaterial('Tubo 80.40.2')!.key, 'RHS 80x40x2');
      expect(parseMaterial('SHS 80x3')!.key, 'SHS 80x3');
      expect(parseMaterial('CHS 48,3x3')!.key, 'CHS 48,3x3');
      expect(parseMaterial('Tubo redondo inox 316 42,4x2')!.key, 'INOX CHS 42,4x2');
      expect(parseMaterial('ANGULO 50X50X5')!.key, 'L 50x5');
      expect(parseMaterial('L 50x5')!.key, 'L 50x5');
      expect(parseMaterial('Pletina 50x8')!.key, 'PLETINA 50x8');
      expect(parseMaterial('R16')!.key, 'REDONDO 16');
    });
    test('chapa, tornillería y servicios', () {
      expect(parseMaterial('CHAPA LAM. 10MM 3000X1500')!.key, 'CHAPA 10');
      expect(parseMaterial('Chapa 3000x1500x8')!.key, 'CHAPA 8');
      expect(parseMaterial('TORNILLO DIN 931 M16X40 8.8')!.key, 'TORNILLO M16');
      expect(parseMaterial('Pernos de anclaje M20 x 600 mm B500S')!.key, 'ANCLAJE M20');
      expect(parseMaterial('Galvanizado en caliente')!.key, 'GALVANIZADO');
      expect(parseMaterial('Panel sándwich 30 mm')!.key, 'SANDWICH');
      expect(parseMaterial('PORTES'), isNotNull);
      expect(parseMaterial('Hola qué tal'), isNull);
    });
  });

  test('parseNumber en formato español', () {
    expect(parseNumber('1.234,56'), 1234.56);
    expect(parseNumber('12,5'), 12.5);
    expect(parseNumber('1234.56'), 1234.56);
    expect(parseNumber('1.000'), 1000);
    expect(parseNumber('abc'), isNull);
  });

  test('lee una factura de proveedor', () {
    final inv = parseInvoiceText(_factura);
    expect(inv.supplierName, 'HIERROS DEL NORTE, S.L.');
    expect(inv.cif, 'B01234567');
    expect(inv.number, 'F-2026/0451');
    expect(inv.date, DateTime(2026, 10, 14));
    expect(inv.address, contains('Lermandabide'));
    expect(inv.phone, contains('945'));
    expect(inv.isPriceList, isFalse);
    final byRef = {for (final l in inv.lines) l.ref?.key: l};
    expect(byRef['IPE 200']!.unitPrice, closeTo(1.08, 1e-9));
    expect(byRef['IPE 200']!.unit, PriceUnit.kg);
    expect(byRef['SHS 80x3']!.discountPct, 5);
    expect(byRef['SHS 80x3']!.unitPrice, closeTo(1.254, 1e-9));
    expect(byRef['CHAPA 10']!.qty, closeTo(353.25, 1e-9));
    expect(byRef['TORNILLO M16']!.unit, PriceUnit.ud);
    // las líneas de totales no son materiales
    expect(inv.lines.where((l) => l.description.toUpperCase().contains('TOTAL')), isEmpty);
  });

  test('lee una tarifa con €/kg y €/m', () {
    final inv = parseInvoiceText('''
ACEROS LEVANTE S.A.
TARIFA DE PRECIOS NETOS 2026
IPE 200 ........ 1,10 €/kg
Tubo 60x60x2 ... 4,20 €/m
Chapa 8 mm ..... 1,05 €/kg
''');
    expect(inv.isPriceList, isTrue);
    expect(inv.lines.length, 3);
    expect(inv.lines[1].ref!.key, 'SHS 60x2');
    expect(inv.lines[1].unit, PriceUnit.m);
  });

  group('PriceBook', () {
    final here = const GeoPoint(42.85, -2.67); // Vitoria
    PriceBook book() {
      final b = PriceBook();
      final near = b.upsertSupplier(Supplier(id: 'a', name: 'Hierros del Norte S.L.', cif: 'B01234567', location: const GeoPoint(42.86, -2.75)));
      final far = b.upsertSupplier(Supplier(id: 'b', name: 'Aceros Madrid', location: const GeoPoint(40.42, -3.70)));
      b.addPrices([
        PriceEntry(supplierId: near.id, ref: 'IPE 200', description: 'IPE 200', unit: PriceUnit.kg, price: 1.10, date: DateTime(2026, 10, 1), source: PriceSource.factura),
        PriceEntry(supplierId: far.id, ref: 'IPE 200', description: 'IPE 200', unit: PriceUnit.kg, price: 0.90, date: DateTime(2026, 10, 1), source: PriceSource.tarifa),
        PriceEntry(supplierId: near.id, ref: 'SHS 60x2', description: 'Tubo 60x60x2', unit: PriceUnit.m, price: 4.20, date: DateTime(2026, 9, 1), source: PriceSource.tarifa),
      ]);
      return b;
    }

    test('filtra por radio', () {
      final q = PriceQuery(here: here, radiusKm: 50, now: DateTime(2026, 11, 1));
      final p = book().lookup(const MaterialRef('IPE', '200'), PriceUnit.kg, q)!;
      expect(p.value, 1.10);
      expect(p.distanceKm, lessThan(10));
      final wide = PriceQuery(here: here, radiusKm: 400, policy: PricePolicy.masBarato, now: DateTime(2026, 11, 1));
      expect(book().lookup(const MaterialRef('IPE', '200'), PriceUnit.kg, wide)!.value, 0.90);
    });

    test('convierte €/m a €/kg y usa la familia', () {
      final q = PriceQuery(here: here, now: DateTime(2026, 11, 1));
      final p = book().lookup(const MaterialRef('SHS', '60x2'), PriceUnit.kg, q, kgPerUnit: 3.5)!;
      expect(p.value, closeTo(1.2, 1e-9));
      // otra medida de IPE: €/kg de la familia
      final f = book().lookup(const MaterialRef('IPE', '240'), PriceUnit.kg, q)!;
      expect(f.level, MatchLevel.familia);
      // HEB: categoría «laminado»
      final c = book().lookup(const MaterialRef('HEB', '220'), PriceUnit.kg, q)!;
      expect(c.level, MatchLevel.categoria);
      // inox no se presupuesta con precios de acero al carbono
      expect(book().lookup(const MaterialRef('IPE', '200', 'INOX'), PriceUnit.kg, q), isNull);
    });

    test('descarta precios antiguos y no duplica proveedores', () {
      final b = book();
      final q = PriceQuery(here: here, maxAgeMonths: 1, now: DateTime(2027, 6, 1));
      expect(b.lookup(const MaterialRef('IPE', '200'), PriceUnit.kg, q), isNull);
      final again = b.upsertSupplier(Supplier(id: 'x', name: 'HIERROS DEL NORTE, SL', cif: 'B-01234567'));
      expect(again.id, 'a');
      expect(PriceBook.fromJson(b.toJson()).entries.length, b.entries.length);
    });

    test('importa una factura completa', () {
      final b = PriceBook();
      final inv = parseInvoiceText(_factura);
      final s = b.upsertSupplier(Supplier(id: PriceBook.newSupplierId(), name: inv.supplierName, cif: inv.cif));
      b.addPrices(inv.toPrices(s.id));
      expect(b.entries.length, greaterThanOrEqualTo(4));
      expect(b.entries.every((e) => e.source == PriceSource.factura), isTrue);
    });
  });

  test('presupuesto: usa precios, marca lo que falta y no inventa', () {
    final d = designFromPrompt('Marquesina para 2 coches de 5,5 x 5 m y 2,4 m de alto, panel sándwich, galvanizada');
    final b = PriceBook();
    b.upsertSupplier(Supplier(id: 'a', name: 'Hierros', location: const GeoPoint(42.86, -2.75)));
    b.addPrices([
      for (final r in ['IPE', 'HEB', 'SHS', 'RHS', 'UPN', 'L', 'CHS', 'PLETINA', 'REDONDO'])
        PriceEntry(supplierId: 'a', ref: '$r 1', description: r, unit: PriceUnit.kg, price: 1.2, date: DateTime.now(), source: PriceSource.factura),
    ]);
    final rates = WorkshopRates(); // sin €/h
    final bud = buildBudget(d, b, const PriceQuery(here: GeoPoint(42.85, -2.67)), rates);
    final mats = bud.of(BudgetSection.materiales).where((l) => l.key.startsWith('perfil:')).toList();
    expect(mats, isNotEmpty);
    expect(mats.every((l) => l.unitPrice != null), isTrue, reason: mats.map((l) => '${l.concept} ${l.ref}').join('\n'));
    // sin €/h, la mano de obra queda sin precio y lo dice
    final mo = bud.lines.firstWhere((l) => l.key == 'mo:taller');
    expect(mo.missing, isTrue);
    expect(mo.origin, contains('hora'));
    expect(bud.complete, isFalse);
    // con €/h y un precio fijado a mano
    final bud2 = buildBudget(d, b, const PriceQuery(), WorkshopRates(hourly: 35, marginPct: 10),
        project: const ProjectBudgetSettings(manualPrices: {'acab:galvanizado': 0.6}, extras: 120));
    final g = bud2.lines.firstWhere((l) => l.key == 'acab:galvanizado');
    expect(g.manual, isTrue);
    expect(bud2.total, closeTo(bud2.base * 1.21, 1e-6));
    expect(bud2.base, closeTo(bud2.direct * 1.10, 1e-6));
    expect(quoteRequestText(d), contains('precio'));
  });

  test('almacén de proyectos: guardar, listar, duplicar y borrar', () {
    final dir = Directory.systemTemp.createTempSync('herrero_proj');
    addTearDown(() => dir.deleteSync(recursive: true));
    final d = designFromPrompt('Escalera recta de 3 m de altura y 1 m de ancho con barandilla, galvanizada');
    final store = ProjectStore(dir);
    final r = ProjectStore.fromDesign(d)
      ..client = 'Comunidad Calle Mayor 3'
      ..budget = const ProjectBudgetSettings(extras: 80).toJson();
    store.save(r, kg: d.steelKg);
    // spec ida y vuelta
    final back = specFromJson(specToJson(d.spec));
    expect(back.type, d.spec.type);
    expect(back.height, d.spec.height);
    expect(back.railing, d.spec.railing);
    // otro almacén sobre la misma carpeta lee el índice
    final store2 = ProjectStore(dir);
    expect(store2.list().single.client, 'Comunidad Calle Mayor 3');
    expect(store2.list().single.kg, closeTo(d.steelKg, 0.1));
    final loaded = store2.load(r.id)!;
    expect(loaded.prompt, d.prompt);
    expect(ProjectBudgetSettings.fromJson(loaded.budget).extras, 80);
    final copy = store2.duplicate(r.id)!;
    expect(store2.list().length, 2);
    expect(store2.search('copia').single.id, copy.id);
    expect(store2.search('calle mayor').length, 2);
    // índice roto → se reconstruye desde las carpetas
    File('${dir.path}/index.json').writeAsStringSync('{roto');
    expect(ProjectStore(dir).list().length, 2);
    store2.delete(copy.id);
    expect(ProjectStore(dir).list().length, 1);
  });
}
