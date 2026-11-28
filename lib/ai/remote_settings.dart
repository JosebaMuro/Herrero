// Ajustes del endpoint de IA (FreeLLMAPI, la pasarela de Infinito / 9000
// tokens, u otro compatible con OpenAI), guardados en shared_preferences.
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'remote_llm.dart';

export 'remote_llm.dart';

/// Pasarela integrada de Infinito (9000 tokens): OpenAI en :8686/v1, modelo auto.
const infinitoGateway = 'http://127.0.0.1:8686/v1';

class RemoteLlmStore {
  RemoteLlmStore._();
  static final instance = RemoteLlmStore._();
  static const _key = 'ai.remote';

  RemoteLlmSettings? _cache;

  Future<RemoteLlmSettings> load() async {
    if (_cache != null) return _cache!;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      _cache = raw == null
          ? const RemoteLlmSettings()
          : RemoteLlmSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      _cache = const RemoteLlmSettings();
    }
    return _cache!;
  }

  Future<void> save(RemoteLlmSettings s) async {
    _cache = s;
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(s.toJson()));
  }
}

/// Un endpoint encontrado en la configuración de Infinito (9000 tokens).
class DetectedEndpoint {
  const DetectedEndpoint(this.name, this.baseUrl, this.apiKey);
  final String name;
  final String baseUrl;
  final String apiKey;
}

/// Carpeta de configuración de Infinito (como `os.UserConfigDir()` de Go).
String? infinitoConfigPath([Map<String, String>? env]) {
  final e = env ?? Platform.environment;
  final sep = Platform.pathSeparator;
  final home = e['INFINITO_HOME'];
  if (home != null && home.isNotEmpty) return '$home${sep}config.json';
  String? base;
  if (Platform.isWindows) {
    base = e['APPDATA'];
  } else if (Platform.isMacOS) {
    final h = e['HOME'];
    base = h == null ? null : '$h/Library/Application Support';
  } else {
    base = e['XDG_CONFIG_HOME'] ?? (e['HOME'] == null ? null : '${e['HOME']}/.config');
  }
  return base == null ? null : '$base${sep}infinito${sep}config.json';
}

/// Lee la configuración de Infinito: su pasarela integrada y FreeLLMAPI
/// (con las claves que tenga guardadas). Vacío si no está instalado.
List<DetectedEndpoint> parseInfinitoConfig(Map<String, dynamic> j) {
  final out = <DetectedEndpoint>[];
  final host = (j['gateway_host'] as String?)?.trim();
  final port = (j['gateway_port'] as num?)?.toInt() ?? 8686;
  final h = host == null || host.isEmpty || host == '0.0.0.0' ? '127.0.0.1' : host;
  out.add(DetectedEndpoint('Pasarela de Infinito', 'http://$h:$port/v1', (j['gateway_key'] as String?) ?? ''));
  final f = j['freellmapi'];
  if (f is Map && (f['url'] as String? ?? '').isNotEmpty) {
    out.add(DetectedEndpoint('FreeLLMAPI (de Infinito)', normalizeBaseUrl(f['url'] as String), (f['api_key'] as String?) ?? ''));
  }
  return out;
}

Future<List<DetectedEndpoint>> detectInfinito() async {
  final path = infinitoConfigPath();
  if (path == null) return const [];
  try {
    final f = File(path);
    if (!await f.exists()) return const [];
    return parseInfinitoConfig(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
  } catch (_) {
    return const [];
  }
}
