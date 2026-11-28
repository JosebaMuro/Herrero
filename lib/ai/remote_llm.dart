// LLM por un endpoint compatible con OpenAI (FreeLLMAPI u otro): alternativa
// opcional al Qwen3 local para rellenar la ficha. Dart puro (app y TUI).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../engine/comprehension_aids.dart';
import '../engine/model.dart';
import '../engine/understanding.dart';
import 'local_text.dart';

/// Proyecto FreeLLMAPI (proxy que reúne los planes gratuitos de muchos
/// proveedores tras un único endpoint `/v1` compatible con OpenAI).
const freeLlmApiRepo = 'https://github.com/tashfeenahmed/freellmapi';

/// Direcciones habituales de FreeLLMAPI: servidor/Docker y app de escritorio.
const freeLlmApiDocker = 'http://localhost:3001/v1';
const freeLlmApiDesktop = 'http://127.0.0.1:31415/v1';

/// Ajustes del endpoint remoto (se guardan en `ai.remote.*`).
class RemoteLlmSettings {
  const RemoteLlmSettings({
    this.enabled = false,
    this.baseUrl = freeLlmApiDocker,
    this.apiKey = '',
    this.model = 'auto',
    this.fallbackLocal = true,
    this.timeoutS = 90,
    this.embedded = true,
  });

  /// Usar el FreeLLMAPI que trae Herrero (lo arranca él, URL y clave solas).
  final bool embedded;

  /// Usar el endpoint para el razonamiento de la ficha.
  final bool enabled;

  /// URL base hasta `/v1` (se admite sin `/v1` y con barra final).
  final String baseUrl;

  /// Clave unificada (`freellmapi-…`) o la del proveedor; vacía si no pide.
  final String apiKey;

  /// Modelo: `auto` deja elegir a FreeLLMAPI (`auto:fast`, `auto:smart`, un id…).
  final String model;

  /// Si el endpoint falla, usar el modelo local instalado.
  final bool fallbackLocal;
  final int timeoutS;

  bool get usable => enabled && (embedded || baseUrl.trim().isNotEmpty);

  RemoteLlmSettings copyWith(
          {bool? enabled,
          String? baseUrl,
          String? apiKey,
          String? model,
          bool? fallbackLocal,
          int? timeoutS,
          bool? embedded}) =>
      RemoteLlmSettings(
        enabled: enabled ?? this.enabled,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        fallbackLocal: fallbackLocal ?? this.fallbackLocal,
        timeoutS: timeoutS ?? this.timeoutS,
        embedded: embedded ?? this.embedded,
      );

  Map<String, Object> toJson() => {
        'enabled': enabled,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'fallbackLocal': fallbackLocal,
        'timeoutS': timeoutS,
        'embedded': embedded,
      };

  factory RemoteLlmSettings.fromJson(Map<String, dynamic> j) => RemoteLlmSettings(
        enabled: j['enabled'] == true,
        baseUrl: (j['baseUrl'] as String?) ?? freeLlmApiDocker,
        apiKey: (j['apiKey'] as String?) ?? '',
        model: ((j['model'] as String?) ?? '').trim().isEmpty ? 'auto' : (j['model'] as String).trim(),
        fallbackLocal: j['fallbackLocal'] != false,
        timeoutS: (j['timeoutS'] as num?)?.toInt() ?? 90,
        embedded: j['embedded'] != false,
      );
}

/// `http://host:3001`, `http://host:3001/`, `…/v1/` -> `http://host:3001/v1`.
String normalizeBaseUrl(String url) {
  var u = url.trim();
  while (u.endsWith('/')) {
    u = u.substring(0, u.length - 1);
  }
  if (u.isEmpty) return u;
  if (!u.contains('://')) u = 'http://$u';
  for (final tail in ['/chat/completions', '/models']) {
    if (u.endsWith(tail)) u = u.substring(0, u.length - tail.length);
  }
  if (!RegExp(r'/v\d+[a-z]*$').hasMatch(u)) u = '$u/v1';
  return u;
}

Map<String, String> _headers(RemoteLlmSettings s) => {
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream, application/json',
      if (s.apiKey.trim().isNotEmpty) 'Authorization': 'Bearer ${s.apiKey.trim()}',
    };

/// Instrucción extra para un LLM de chat: no se le puede forzar el comienzo
/// de la respuesta como al local, así que se le pide solo el JSON.
String remoteSystem(StructureType type) => '${llmSystem()}\n'
    'Responde SOLO con la ficha en JSON, en una línea, sin explicaciones ni bloques de código. '
    'La tipología ya está decidida: empieza exactamente por {"tipo": "${type.name}", '
    'y no inventes medidas que no estén en la petición.';

/// Mensajes de chat (OpenAI) para leer [prompt] con la tipología ya decidida.
List<Map<String, String>> remoteMessages(String prompt, StructureType type, [List<(String, String)>? examples]) => [
      {'role': 'system', 'content': remoteSystem(type)},
      for (final (q, a) in examples ?? pickExamples(prompt, type)) ...[
        {'role': 'user', 'content': llmUser(q)},
        {'role': 'assistant', 'content': a},
      ],
      {'role': 'user', 'content': llmUser(prompt)},
    ];

/// Quita el razonamiento en línea (`<think>…</think>`) y las vallas ``` de
/// la respuesta; devuelve (ficha, razonamiento).
(String, String) splitRemoteAnswer(String text) {
  var t = text;
  var thought = '';
  final m = RegExp(r'<think>([\s\S]*?)(</think>|$)').firstMatch(t);
  if (m != null) {
    thought = m.group(1)!.trim();
    t = t.replaceRange(m.start, m.end, '');
  }
  t = t.replaceAll(RegExp(r'```(json)?', caseSensitive: false), '').trim();
  final i = t.indexOf('{');
  if (i > 0) t = t.substring(i);
  return (t, thought);
}

/// Error legible del endpoint.
String remoteError(Object e, RemoteLlmSettings s) {
  final base = normalizeBaseUrl(s.baseUrl);
  if (e is SocketException || e is http.ClientException) {
    return 'No se puede conectar con $base. ¿Está FreeLLMAPI en marcha? '
        'Desde el móvil usa la IP del PC (y en Docker, HOST_BIND=0.0.0.0).';
  }
  if (e is TimeoutException) return 'El endpoint no ha respondido a tiempo ($base).';
  return '$e'.replaceFirst('Exception: ', '');
}

String _httpError(int code, String body) {
  var msg = body.trim();
  try {
    final j = jsonDecode(body);
    if (j is Map) {
      final err = j['error'];
      msg = err is Map ? '${err['message'] ?? err}' : '${err ?? j['message'] ?? body}';
    }
  } catch (_) {}
  if (msg.length > 200) msg = '${msg.substring(0, 200)}…';
  return switch (code) {
    401 || 403 => 'Clave no válida o ausente (HTTP $code). Copia la clave unificada de la página Keys de FreeLLMAPI.',
    404 => 'Ruta no encontrada (HTTP 404): revisa que la URL base acabe en /v1. $msg',
    429 => 'Sin cuota en los proveedores ahora mismo (HTTP 429). $msg',
    _ => 'HTTP $code: $msg',
  };
}

/// Modelos que ofrece el endpoint (`GET /models`), con `auto` delante.
Future<List<String>> listRemoteModels(RemoteLlmSettings s, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final r = await c
        .get(Uri.parse('${normalizeBaseUrl(s.baseUrl)}/models'), headers: _headers(s))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception(_httpError(r.statusCode, r.body));
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    final data = j is Map ? j['data'] : j;
    final ids = <String>[
      for (final m in (data as List? ?? const []))
        if (m is Map && m['id'] is String) m['id'] as String,
    ]..sort();
    return ['auto', for (final id in ids) if (id != 'auto') id];
  } finally {
    if (client == null) c.close();
  }
}

/// Lanza la lectura de la ficha en el endpoint, con streaming SSE (y
/// respuesta JSON normal si el servidor no lo hace). Mismo [LlmJob] que el local.
LlmJob startRemoteLlm(RemoteLlmSettings s, String prompt, StructureType type, void Function(String) onPartial,
    {List<(String, String)>? examples, http.Client? client}) {
  final c = client ?? http.Client();
  final completer = Completer<LlmResult>();
  final sw = Stopwatch()..start();
  StreamSubscription<String>? sub;
  void done() {
    sub?.cancel();
    if (client == null) c.close();
  }

  Future<void> run() async {
    final req = http.Request('POST', Uri.parse('${normalizeBaseUrl(s.baseUrl)}/chat/completions'))
      ..headers.addAll(_headers(s))
      ..body = jsonEncode({
        'model': s.model.trim().isEmpty ? 'auto' : s.model.trim(),
        'messages': remoteMessages(prompt, type, examples),
        'temperature': 0.1,
        'max_tokens': 600,
        'stream': true,
      });
    final resp = await c.send(req).timeout(Duration(seconds: s.timeoutS));
    if (resp.statusCode != 200) {
      throw Exception(_httpError(resp.statusCode, await resp.stream.bytesToString()));
    }
    final via = resp.headers['x-routed-via'];
    final label = via == null || via.isEmpty ? 'Endpoint' : 'Endpoint · $via';
    final text = StringBuffer(), thought = StringBuffer();
    final isSse = (resp.headers['content-type'] ?? '').contains('event-stream');
    if (!isSse) {
      final j = jsonDecode(await resp.stream.bytesToString()) as Map<String, dynamic>;
      final msg = ((j['choices'] as List).first as Map)['message'] as Map;
      text.write(msg['content'] ?? '');
      thought.write(msg['reasoning_content'] ?? msg['reasoning'] ?? '');
    } else {
      final finished = Completer<void>();
      sub = resp.stream.transform(utf8.decoder).transform(const LineSplitter()).timeout(Duration(seconds: s.timeoutS)).listen(
        (line) {
          if (!line.startsWith('data:')) return;
          final data = line.substring(5).trim();
          if (data == '[DONE]') return;
          try {
            final j = jsonDecode(data) as Map<String, dynamic>;
            if (j['error'] != null) throw Exception('${(j['error'] as Map?)?['message'] ?? j['error']}');
            final ch = j['choices'] as List?;
            if (ch == null || ch.isEmpty) return;
            final d = ((ch.first as Map)['delta'] ?? const {}) as Map;
            final r = d['reasoning_content'] ?? d['reasoning'];
            if (r is String && r.isNotEmpty) {
              thought.write(r);
              onPartial('$thinkingLabel${_tail(thought.toString())}');
            }
            final ct = d['content'];
            if (ct is String && ct.isNotEmpty) {
              text.write(ct);
              onPartial(text.toString());
            }
          } on FormatException {
            // trozo incompleto: se ignora
          } catch (e) {
            if (!finished.isCompleted) finished.completeError(e);
          }
        },
        onError: (Object e) {
          if (!finished.isCompleted) finished.completeError(e);
        },
        onDone: () {
          if (!finished.isCompleted) finished.complete();
        },
        cancelOnError: true,
      );
      await finished.future;
    }
    final (ficha, inline) = splitRemoteAnswer(text.toString());
    if (!ficha.contains('{')) throw Exception('El endpoint no ha devuelto una ficha JSON: «${_tail(text.toString())}»');
    final th = [thought.toString().trim(), inline].where((x) => x.isNotEmpty).join('\n');
    if (!completer.isCompleted) completer.complete(LlmResult(ficha, const [], 0, sw.elapsed, label, th));
  }

  run().catchError((Object e) {
    if (!completer.isCompleted) completer.completeError(Exception(remoteError(e, s)));
  }).whenComplete(done);
  return LlmJob(completer.future, () {
    if (!completer.isCompleted) completer.completeError(Exception('Cancelado'));
    done();
  });
}

String _tail(String s) {
  final t = s.replaceAll('\n', ' ').trim();
  return t.length <= 160 ? t : '…${t.substring(t.length - 160)}';
}
