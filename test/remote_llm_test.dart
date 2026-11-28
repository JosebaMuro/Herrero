// Endpoint de IA (FreeLLMAPI / pasarela de Infinito): cliente OpenAI con
// streaming, errores legibles y lectura de la configuración de Infinito.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/ai/remote_settings.dart';
import 'package:herrero/engine/model.dart';
import 'package:herrero/engine/understanding.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Servidor falso compatible con OpenAI. [mode]: sse, json, 401, think.
Future<(HttpServer, List<Map<String, dynamic>>)> fakeServer(String mode) async {
  final bodies = <Map<String, dynamic>>[];
  final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  srv.listen((req) async {
    final res = req.response;
    if (mode == '401' || req.headers.value('authorization') != 'Bearer freellmapi-abc') {
      res.statusCode = 401;
      res.write(jsonEncode({'error': {'message': 'Invalid API key'}}));
      await res.close();
      return;
    }
    if (req.uri.path == '/v1/models') {
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({'data': [{'id': 'gemini-2.5-flash'}, {'id': 'auto'}, {'id': 'llama-3.3-70b'}]}));
      await res.close();
      return;
    }
    bodies.add(jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>);
    const ficha = '{"tipo": "marquesina", "largo_m": 5.5, "ancho_m": 5, "alto_m": 2.4, "cubierta": "panel sándwich", '
        '"acabado": "galvanizado"}';
    res.headers.set('x-routed-via', 'groq/llama-3.3-70b');
    if (mode == 'json') {
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({'choices': [{'message': {'role': 'assistant', 'content': '```json\n$ficha\n```'}}]}));
    } else {
      res.headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8');
      final parts = <Map<String, dynamic>>[
        if (mode == 'think') {'reasoning_content': 'El 5,5 es el largo.'},
        for (var i = 0; i < ficha.length; i += 20) {'content': ficha.substring(i, (i + 20).clamp(0, ficha.length))},
      ];
      for (final d in parts) {
        res.write('data: ${jsonEncode({'choices': [{'delta': d}]})}\n\n');
        await res.flush();
      }
      res.write('data: [DONE]\n\n');
    }
    await res.close();
  });
  return (srv, bodies);
}

const prompt = 'Marquesina para 2 coches de 5,5 x 5 m y 2,4 m de alto, panel sándwich, galvanizada';

void main() {
  test('normaliza la URL base', () {
    expect(normalizeBaseUrl('http://localhost:3001'), 'http://localhost:3001/v1');
    expect(normalizeBaseUrl('http://localhost:3001/v1/'), 'http://localhost:3001/v1');
    expect(normalizeBaseUrl('192.168.1.20:3001'), 'http://192.168.1.20:3001/v1');
    expect(normalizeBaseUrl('http://x/v1/chat/completions'), 'http://x/v1');
    expect(normalizeBaseUrl('https://generativelanguage.googleapis.com/v1beta/openai'),
        'https://generativelanguage.googleapis.com/v1beta/openai/v1');
    expect(normalizeBaseUrl('https://api.groq.com/openai/v1'), 'https://api.groq.com/openai/v1');
  });

  test('separa razonamiento y vallas de código', () {
    final (f, th) = splitRemoteAnswer('<think>pienso</think>\n```json\n{"tipo": "reja"}\n```');
    expect(f, '{"tipo": "reja"}');
    expect(th, 'pienso');
  });

  test('mensajes de chat: sistema, ejemplos y petición con la tipología decidida', () {
    final m = remoteMessages(prompt, StructureType.marquesina);
    expect(m.first['role'], 'system');
    expect(m.first['content'], contains('{"tipo": "marquesina"'));
    expect(m.last['role'], 'user');
    expect(m.last['content'], contains('5,5 x 5'));
    expect(m.where((x) => x['role'] == 'assistant'), isNotEmpty);
  });

  for (final mode in ['sse', 'json', 'think']) {
    test('lee la ficha por el endpoint ($mode)', () async {
      final (srv, bodies) = await fakeServer(mode);
      addTearDown(srv.close);
      final s = RemoteLlmSettings(enabled: true, baseUrl: 'http://127.0.0.1:${srv.port}', apiKey: 'freellmapi-abc');
      final partials = <String>[];
      final r = await startRemoteLlm(s, prompt, StructureType.marquesina, partials.add).future;
      expect(bodies.single['model'], 'auto');
      expect(bodies.single['stream'], true);
      expect(r.engineLabel, 'Endpoint · groq/llama-3.3-70b');
      if (mode != 'json') expect(partials, isNotEmpty);
      if (mode == 'think') expect(r.thought, contains('largo'));
      final j = parseLlmJson(r.text);
      expect(j?['largo_m'], 5.5);
      final u = understand(prompt, llm: j);
      expect(u.type, StructureType.marquesina);
      expect(u.spec.height, closeTo(2.4, 1e-9));
    });
  }

  test('clave mala: error legible', () async {
    final (srv, _) = await fakeServer('401');
    addTearDown(srv.close);
    final s = RemoteLlmSettings(enabled: true, baseUrl: 'http://127.0.0.1:${srv.port}/v1');
    await expectLater(startRemoteLlm(s, prompt, StructureType.marquesina, (_) {}).future,
        throwsA(predicate((e) => '$e'.contains('Clave no válida'))));
  });

  test('sin servidor: dice que arranque FreeLLMAPI', () async {
    final s = RemoteLlmSettings(enabled: true, baseUrl: 'http://127.0.0.1:9', timeoutS: 5);
    await expectLater(startRemoteLlm(s, prompt, StructureType.marquesina, (_) {}).future,
        throwsA(predicate((e) => '$e'.contains('FreeLLMAPI'))));
  });

  test('lista de modelos con auto delante', () async {
    final (srv, _) = await fakeServer('sse');
    addTearDown(srv.close);
    final s = RemoteLlmSettings(baseUrl: 'http://127.0.0.1:${srv.port}', apiKey: 'freellmapi-abc');
    expect(await listRemoteModels(s), ['auto', 'gemini-2.5-flash', 'llama-3.3-70b']);
  });

  test('cancelar no deja la petición colgada', () async {
    final s = const RemoteLlmSettings(enabled: true, baseUrl: 'http://10.255.255.1:3001', timeoutS: 30);
    final job = startRemoteLlm(s, prompt, StructureType.marquesina, (_) {});
    job.cancel();
    await expectLater(job.future, throwsA(predicate((e) => '$e'.contains('Cancelado'))));
  });

  test('configuración de Infinito (9000 tokens): pasarela y FreeLLMAPI con sus claves', () {
    final d = parseInfinitoConfig({
      'gateway_host': '0.0.0.0',
      'gateway_port': 8686,
      'gateway_key': 'inf-123',
      'freellmapi': {'url': 'http://localhost:3001', 'api_key': 'freellmapi-xyz'},
    });
    expect(d.map((e) => e.baseUrl), ['http://127.0.0.1:8686/v1', 'http://localhost:3001/v1']);
    expect(d.map((e) => e.apiKey), ['inf-123', 'freellmapi-xyz']);
    expect(infinitoConfigPath({'INFINITO_HOME': '/x'}), '/x${Platform.pathSeparator}config.json');
  });

  test('los ajustes se guardan', () async {
    SharedPreferences.setMockInitialValues({});
    const s = RemoteLlmSettings(enabled: true, baseUrl: infinitoGateway, apiKey: 'inf-1', model: 'auto:fast');
    await RemoteLlmStore.instance.save(s);
    final p = await SharedPreferences.getInstance();
    final back = RemoteLlmSettings.fromJson(jsonDecode(p.getString('ai.remote')!) as Map<String, dynamic>);
    expect(back.toJson(), s.toJson());
  });
}
