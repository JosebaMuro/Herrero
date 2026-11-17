// Ficha de interpretación: sale al instante con las reglas, se puede corregir
// y lleva al cálculo. Sin modelos instalados funciona igual.
import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/engine/model.dart';
import 'package:herrero/screens/project_screen.dart';
import 'package:herrero/screens/understand_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, String prompt) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: UnderstandScreen(prompt: prompt)));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('ficha deducida y corrección del usuario', (tester) async {
    await pump(tester, 'un techado para aparcar tres coches');
    expect(find.text('Lo que he entendido'), findsOneWidget);
    expect(find.text(StructureType.marquesina.label), findsOneWidget);
    expect(find.text('7,50 m'), findsOneWidget);
    expect(find.textContaining('3 plazas'), findsOneWidget);
    expect(find.text('deducido'), findsWidgets);

    await tester.tap(find.text('Altura libre'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '3,2');
    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();
    expect(find.text('3,20 m'), findsOneWidget);
    expect(find.text('cambiado por ti'), findsOneWidget);
  });

  testWidgets('cambiar la tipología y calcular', (tester) async {
    await pump(tester, 'marquesina para 2 coches de 5,5 x 5 m');
    await tester.tap(find.text(StructureType.marquesina.label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(StructureType.nave.label).last);
    await tester.pumpAndSettle();
    expect(find.text('Luz (ancho)'), findsOneWidget);
    expect(find.text('cambiado por ti'), findsWidgets);

    await tester.scrollUntilVisible(find.text('Calcular estructura'), 200);
    await tester.tap(find.text('Calcular estructura'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ProjectScreen), findsOneWidget);
  });

  testWidgets('elegir la forma de la escalera', (tester) async {
    await pump(tester, 'escalera de 3 m de altura');
    expect(find.text('Forma'), findsOneWidget);
    expect(find.text('Recta'), findsOneWidget);
    await tester.tap(find.text('Forma'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('De caracol'));
    await tester.pumpAndSettle();
    expect(find.text('De caracol'), findsOneWidget);
    expect(find.text('Diámetro'), findsOneWidget);
    expect(find.text('cambiado por ti'), findsWidgets);
  });
}
