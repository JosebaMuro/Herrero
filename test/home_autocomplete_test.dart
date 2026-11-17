// Autocompletar en el campo de la petición.
import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/screens/home_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('sugiere y completa al escribir', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'escalera de car');
    await tester.pump();
    expect(find.byKey(const ValueKey('autocompletar')), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, 'escalera de caracol'));
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'escalera de caracol ');
    // tras la palabra completa propone lo que suele seguir
    expect(find.widgetWithText(ActionChip, 'con barandilla'), findsOneWidget);
  });
}
