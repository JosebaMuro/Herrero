// FreeLLMAPI integrado de verdad: arranca el Node y el FreeLLMAPI del paquete
// (HERRERO_FREELLMAPI=<carpeta freellmapi de scripts/bundle_freellmapi.sh>),
// saca la clave sola por el modo escritorio y responde en /v1.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/ai/remote_settings.dart';
import 'package:herrero/engine/model.dart';
import 'package:http/http.dart' as http;

void main() {
  final dir = Platform.environment['HERRERO_FREELLMAPI'];
  final skip = dir == null || dir.isEmpty ? 'sin HERRERO_FREELLMAPI' : null;

  test('sin paquete: lo dice claro', () async {
    final fl = EmbeddedFreeLlmApi(locate: () => null);
    expect(await fl.available(), isFalse);
    await expectLater(fl.endpoint(), throwsA(predicate((e) => '$e'.contains('no trae FreeLLMAPI'))));
    expect(fl.state, FreeLlmApiState.absent);
  });

  test('arranca, da la clave sola, responde en /v1 y se para', () async {
    final data = await Directory.systemTemp.createTemp('fl-');
    final fl = EmbeddedFreeLlmApi(basePort: 31580)..dataDir = () async => data.path;
    addTearDown(() async {
      await fl.stop();
      await data.delete(recursive: true);
    });
    expect(await fl.available(), isTrue);
    final (url, key) = await fl.endpoint();
    expect(url, 'http://127.0.0.1:31580/v1');
    expect(key, startsWith('freellmapi-'));
    expect(fl.state, FreeLlmApiState.running);
    expect(File('${data.path}/encryption.key').existsSync(), isTrue);

    final models = await listRemoteModels(RemoteLlmSettings(baseUrl: url, apiKey: key));
    expect(models.first, 'auto');

    // sin clave, FreeLLMAPI rechaza
    final r = await http.get(Uri.parse('$url/models'));
    expect(r.statusCode, 401);

    // el panel se abre sin contraseña desde este equipo
    final page = await http.get(Uri.parse(fl.dashboardUrl!));
    expect(page.statusCode, 200);

    // una ficha: sin internet no hay proveedores, pero el error se entiende
    final s = RemoteLlmSettings(enabled: true, baseUrl: url, apiKey: key, timeoutS: 60);
    try {
      final res = await startRemoteLlm(s, 'Marquesina de 5 x 3 m', StructureType.marquesina, (_) {}).future;
      expect(res.text, contains('{'));
    } catch (e) {
      expect('$e', isNot(contains('Clave no válida')));
    }

    // un segundo Herrero (o tras un cierre brusco) reutiliza el que hay
    final again = EmbeddedFreeLlmApi(basePort: 31580)..dataDir = () async => data.path;
    final (url2, key2) = await again.endpoint();
    expect((url2, key2), (url, key));

    await fl.stop();
    expect(fl.state, FreeLlmApiState.stopped);
    await Future<void>.delayed(const Duration(seconds: 1));
    await expectLater(http.get(Uri.parse('$url/models')), throwsA(anything));
    // la clave de cifrado se conserva entre arranques (las claves de proveedor siguen valiendo)
    final k1 = File('${data.path}/encryption.key').readAsStringSync();
    final (_, key3) = await fl.endpoint();
    expect(File('${data.path}/encryption.key').readAsStringSync(), k1);
    expect(key3, key, reason: 'misma base de datos, misma clave unificada');
  }, skip: skip);
}
