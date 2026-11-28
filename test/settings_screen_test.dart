// Ajustes: endpoint de IA (FreeLLMAPI / Infinito) y su uso en la ficha.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/ai/remote_settings.dart';
import 'package:herrero/screens/settings_screen.dart';
import 'package:herrero/screens/understand_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> big(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
  }

  Future<void> settle(WidgetTester tester, [int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('Ajustes: activar el endpoint y elegir FreeLLMAPI', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await big(tester);
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await settle(tester);
    expect(find.text('Endpoint de IA (FreeLLMAPI)'), findsOneWidget);
    await tester.tap(find.text('FreeLLMAPI escritorio (:31415)'));
    await settle(tester);
    await tester.tap(find.text('Usar el endpoint para el razonamiento'));
    await settle(tester);
    final p = await SharedPreferences.getInstance();
    final s = RemoteLlmSettings.fromJson(jsonDecode(p.getString('ai.remote')!) as Map<String, dynamic>);
    expect(s.enabled, isTrue);
    expect(s.baseUrl, freeLlmApiDesktop);
    expect(s.model, 'auto');
  });

  testWidgets('la ficha usa el endpoint aunque no haya modelos locales', (tester) async {
    await big(tester);
    late HttpServer srv;
    var calls = 0;
    HttpOverrides.global = null; // la prueba de widgets falsea HttpClient (400)
    await tester.runAsync(() async {
      srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      srv.listen((req) async {
        await utf8.decodeStream(req);
        calls++;
        req.response.headers.contentType = ContentType.json;
        req.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '{"tipo": "marquesina", "largo_m": 7.5, "ubicacion": "Burgos"}'},
              },
            ],
          }),
        );
        await req.response.close();
      });
    });
    addTearDown(() => srv.close(force: true));
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(
      () => RemoteLlmStore.instance.save(
        RemoteLlmSettings(
          enabled: true,
          embedded: false,
          baseUrl: 'http://127.0.0.1:${srv.port}',
          fallbackLocal: false,
        ),
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: UnderstandScreen(prompt: 'tejadillo para tres coches en Burgos')));
    await settle(tester, 40);
    expect(find.text('Comprensión con IA no instalada'), findsNothing);
    expect(find.textContaining('Razonamiento:'), findsNothing);
    expect(calls, 1);
    await RemoteLlmStore.instance.save(const RemoteLlmSettings());
  });
}
