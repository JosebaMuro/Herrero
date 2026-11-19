import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/engine/cutting.dart';
import 'package:herrero/engine/designer.dart';
import 'package:herrero/engine/model.dart';
import 'package:herrero/engine/profiles.dart';
import 'package:herrero/screens/project_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

SteelProfile _prof(ProfileFamily f) => tableFor(f)[3];

Piece _p(String mark, SteelProfile prof, double len, int qty) =>
    Piece(mark: mark, description: mark, profile: prof, lengthMm: len, qty: qty, cut: '90°');

/// Comprueba que cada barra respeta su longitud y que salen todas las piezas.
void _valid(StockPlan st, Map<String, int> wantMm) {
  final got = <String, int>{};
  for (final b in st.barList) {
    final need = b.cuts.fold<int>(0, (s, c) => s + c.length) + (b.cuts.length - 1) * b.kerf;
    expect(need, lessThanOrEqualTo(b.length - 2 * b.trim), reason: 'barra sobrecargada: ${b.cuts}');
    for (final c in b.cuts) {
      got[c.mark] = (got[c.mark] ?? 0) + c.length;
    }
  }
  expect(got, wantMm);
}

void main() {
  final shs = _prof(ProfileFamily.shs);
  final ipe = _prof(ProfileFamily.ipe);
  const s = CutSettings(kerf: 3, mode: BarMode.only6, mixLengths: false);

  test('dos piezas de 2990 por barra de 6 m con sierra de 3 mm', () {
    final st = optimizeCuts([_p('C1', shs, 2990, 4)], s).single;
    expect(st.bars, 2);
    expect(st.orderText, '2 × 6 m');
    expect(st.patterns.single.repeat, 2);
    _valid(st, {'C1': 4 * 2990});
  });

  test('la merma de sierra cuenta: 2 × 3000 no caben con kerf si hay que cortar', () {
    final st = optimizeCuts([_p('C1', shs, 3000, 2), _p('C2', shs, 500, 1)], s).single;
    // 3000 + 3000 = 6000 justo (la última pieza llega al final): una barra; la de 500 va aparte
    expect(st.bars, 2);
    _valid(st, {'C1': 6000, 'C2': 500});
  });

  test('aprovecha mejor que FFD y alcanza la cota inferior', () {
    final pieces = [
      _p('A', shs, 2600, 4),
      _p('B', shs, 1800, 6),
      _p('C', shs, 1500, 4),
      _p('D', shs, 1100, 6),
    ];
    final st = optimizeCuts(pieces, s).single;
    _valid(st, {'A': 10400, 'B': 10800, 'C': 6000, 'D': 6600});
    expect(st.isOptimal, isTrue, reason: '${st.bars} barras, cota ${st.lowerBound}');
  });

  test('mezcla 12 m y 6 m cuando sobra media barra', () {
    final st = optimizeCuts([_p('P1', ipe, 5000, 3), _p('V1', ipe, 1000, 1)],
            const CutSettings(kerf: 3, mode: BarMode.auto, mixLengths: true))
        .single;
    expect(st.orderText, '1 × 12 m + 1 × 6 m');
    expect(st.purchasedMm, 18000);
    _valid(st, {'P1': 15000, 'V1': 1000});
  });

  test('pieza más larga que la barra: tramos empalmados', () {
    final st = optimizeCuts([_p('P1', shs, 7500, 1)], s).single;
    expect(st.spliced, ['P1']);
    _valid(st, {'P1': 7500});
    expect(st.barList.expand((b) => b.cuts).where((c) => c.note.startsWith('tramo')).length, 2);
  });

  test('despunte y retales aprovechables', () {
    final st = optimizeCuts([_p('C1', shs, 4000, 1)],
            const CutSettings(kerf: 3, trim: 10, minRemnant: 500, mode: BarMode.only6, mixLengths: false))
        .single;
    expect(st.barList.single.remnantMm, 6000 - 20 - 4000 - 3);
    expect(st.remnants, [1977]);
    expect(st.scrapPct, lessThan(st.wastePct));
  });

  test('ajustes: ida y vuelta a JSON', () {
    const a = CutSettings(kerf: 4, trim: 5, minRemnant: 300, mode: BarMode.only12, mixLengths: false);
    final b = CutSettings.fromJson(a.toJson());
    expect(b.toJson(), a.toJson());
  });

  test('casos aleatorios: siempre válido y nunca peor que la cota + 1', () {
    final rnd = math.Random(7);
    for (var t = 0; t < 40; t++) {
      final pieces = [
        for (var i = 0; i < 1 + rnd.nextInt(6); i++)
          _p('M$i', shs, 200.0 + rnd.nextInt(5500), 1 + rnd.nextInt(8)),
      ];
      final st = optimizeCuts(pieces, s).single;
      final want = <String, int>{};
      for (final p in pieces) {
        want[p.mark] = (want[p.mark] ?? 0) + p.lengthMm.round() * p.qty;
      }
      _valid(st, want);
      expect(st.bars, lessThanOrEqualTo(st.lowerBound + 1));
    }
  });

  test('la marquesina de prueba sale con plan de corte completo', () {
    final d = designFromPrompt('Marquesina para 2 coches de 5,5 x 5 m y 2,4 m de alto, panel sándwich, galvanizada');
    expect(d.stock, isNotEmpty);
    for (final st in d.stock) {
      final want = <String, int>{};
      for (final p in d.pieces.where((p) => p.profile.name == st.profile.name)) {
        want[p.mark] = (want[p.mark] ?? 0) + p.lengthMm.round() * p.qty;
      }
      _valid(st, want);
      expect(cutPlanLines(st), isNotEmpty);
    }
  });

  testWidgets('pestaña Despiece: pedido, plan de corte y ajustes', (tester) async {
    SharedPreferences.setMockInitialValues({});
    CutSettings.current = const CutSettings();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final d = designFromPrompt('Marquesina para 2 coches de 5,5 x 5 m y 2,4 m de alto, panel sándwich, galvanizada');
    await tester.pumpWidget(MaterialApp(home: ProjectScreen(design: d)));
    await tester.pump();
    await tester.tap(find.text('Despiece'));
    await tester.pumpAndSettle();
    final title = find.text('Pedido de barras y plan de corte');
    await tester.scrollUntilVisible(title, 300, scrollable: find.byType(Scrollable).last);
    expect(title, findsOneWidget);
    expect(find.text('Barras a pedir'), findsOneWidget);

    await tester.ensureVisible(find.text('Ajustes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajustes'));
    await tester.pumpAndSettle();
    expect(find.text('Ajustes del optimizador de corte'), findsOneWidget);
    await tester.tap(find.text('Solo 6 m'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recalcular'));
    await tester.pumpAndSettle();
    expect(CutSettings.current.mode, BarMode.only6);
    expect(d.stock.every((st) => st.barList.every((b) => b.length == 6000)), isTrue);
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('cut_settings_v1'), contains('only6'));
    CutSettings.current = const CutSettings();
  });
}

