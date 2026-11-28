// FreeLLMAPI integrado: el paquete de Herrero trae Node.js y FreeLLMAPI
// (scripts/bundle_freellmapi.sh) y aquí se arranca como proceso hijo, en modo
// escritorio (FREEAPI_DESKTOP=1: sin cuenta ni contraseña desde este equipo).
// Dart puro (dart:io): lo usan la app y las pruebas.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

/// Dónde está el FreeLLMAPI del paquete.
class FreeLlmApiBundle {
  const FreeLlmApiBundle({required this.node, required this.appDir, this.env = const {}, this.version = ''});

  /// Ejecutable de Node.js.
  final String node;

  /// Carpeta `app` (con `server/dist/index.js`).
  final String appDir;

  /// Variables extra para Node (Android: bibliotecas y certificados).
  final Map<String, String> env;
  final String version;

  String get serverDir => '$appDir${Platform.pathSeparator}server';
  String get entry => '$serverDir${Platform.pathSeparator}dist${Platform.pathSeparator}index.js';

  bool get exists => File(node).existsSync() && File(entry).existsSync();

  /// Paquete de escritorio en [root] (`<root>/node`, `<root>/app`).
  static FreeLlmApiBundle desktop(String root) {
    final sep = Platform.pathSeparator;
    final node = Platform.isWindows ? '$root${sep}node${sep}node.exe' : '$root${sep}node${sep}bin${sep}node';
    var version = '';
    try {
      version = (jsonDecode(File('$root${sep}pack.json').readAsStringSync()) as Map)['freellmapi'] as String? ?? '';
    } catch (_) {}
    return FreeLlmApiBundle(node: node, appDir: '$root${sep}app', version: version);
  }

  /// Junto al ejecutable de Herrero (Windows: carpeta del .exe; Linux: el bundle,
  /// /opt/herrero o el AppImage). `HERRERO_FREELLMAPI` lo cambia (pruebas).
  static FreeLlmApiBundle? find() {
    final sep = Platform.pathSeparator;
    final roots = <String>[
      if (Platform.environment['HERRERO_FREELLMAPI'] case final String d when d.isNotEmpty) d,
      '${File(Platform.resolvedExecutable).parent.path}${sep}freellmapi',
    ];
    for (final r in roots) {
      final b = desktop(r);
      if (b.exists) return b;
    }
    return null;
  }
}

/// Estado del FreeLLMAPI integrado.
enum FreeLlmApiState { absent, stopped, starting, running, error }

/// FreeLLMAPI arrancado por Herrero en 127.0.0.1.
class EmbeddedFreeLlmApi {
  EmbeddedFreeLlmApi({this.basePort = 31480, FreeLlmApiBundle? Function()? locate})
    : _locate = locate ?? FreeLlmApiBundle.find;

  /// Instancia de la app (la carpeta de datos la pone `main`).
  static final instance = EmbeddedFreeLlmApi();

  final int basePort;
  final FreeLlmApiBundle? Function() _locate;
  Future<String> Function()? _dataDir;

  /// Carpeta donde FreeLLMAPI guarda su base de datos, clave de cifrado y registro.
  set dataDir(Future<String> Function() f) => _dataDir = f;

  /// Localizador del paquete (Android lo prepara al vuelo).
  Future<FreeLlmApiBundle?> Function()? prepare;

  Process? _proc;
  int? _port;
  String? _apiKey;
  String? lastError;
  Future<(String, String)>? _starting;
  FreeLlmApiState _state = FreeLlmApiState.stopped;
  final _changes = StreamController<FreeLlmApiState>.broadcast();

  Stream<FreeLlmApiState> get changes => _changes.stream;
  FreeLlmApiState get state => _state;
  int? get port => _port;
  String? get dashboardUrl => _port == null ? null : 'http://127.0.0.1:$_port/';

  void _set(FreeLlmApiState s) {
    _state = s;
    if (!_changes.isClosed) _changes.add(s);
  }

  Future<FreeLlmApiBundle?> bundle() async => prepare != null ? await prepare!() : _locate();

  /// Hay FreeLLMAPI en este paquete.
  Future<bool> available() async => (await bundle())?.exists ?? false;

  /// URL base `/v1` y clave unificada, arrancándolo si hace falta.
  Future<(String, String)> endpoint() {
    final k = _apiKey, p = _port;
    if (k != null && p != null && _state == FreeLlmApiState.running) return Future.value(('http://127.0.0.1:$p/v1', k));
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<String> _data() async {
    final f = _dataDir;
    final d = Directory(
      f == null ? '${Directory.systemTemp.path}${Platform.pathSeparator}herrero-freellmapi' : await f(),
    );
    await d.create(recursive: true);
    return d.path;
  }

  /// Clave de cifrado de las claves de proveedor (una por equipo, no se cambia).
  Future<String> _encryptionKey(String data) async {
    final f = File('$data${Platform.pathSeparator}encryption.key');
    if (await f.exists()) {
      final k = (await f.readAsString()).trim();
      if (k.length >= 32) return k;
    }
    final r = Random.secure();
    final k = [for (var i = 0; i < 32; i++) r.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
    await f.writeAsString(k);
    return k;
  }

  /// Sesión del panel (modo escritorio: solo desde este equipo), o null si en
  /// [port] no hay un FreeLLMAPI arrancado por Herrero.
  Future<String?> _session(int port) async {
    try {
      final r = await http
          .post(Uri.parse('http://127.0.0.1:$port/api/auth/desktop-session'))
          .timeout(const Duration(seconds: 3));
      if (r.statusCode != 200) return null;
      return (jsonDecode(r.body) as Map)['token'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<String> _unifiedKey(int port, String token) async {
    final r = await http
        .get(Uri.parse('http://127.0.0.1:$port/api/settings/api-key'), headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 5));
    if (r.statusCode != 200) throw Exception('FreeLLMAPI no da la clave (HTTP ${r.statusCode})');
    return (jsonDecode(r.body) as Map)['apiKey'] as String;
  }

  Future<bool> _portFree(int port) async {
    try {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      await s.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<(String, String)> _start() async {
    final b = await bundle();
    if (b == null || !b.exists) {
      _set(FreeLlmApiState.absent);
      throw Exception('Este paquete de Herrero no trae FreeLLMAPI. Usa un endpoint externo.');
    }
    _set(FreeLlmApiState.starting);
    lastError = null;
    try {
      // ¿ya hay uno (de una sesión anterior que no se cerró bien)?
      for (var p = basePort; p < basePort + 10; p++) {
        final t = await _session(p);
        if (t != null) {
          _port = p;
          _apiKey = await _unifiedKey(p, t);
          _set(FreeLlmApiState.running);
          return ('http://127.0.0.1:$p/v1', _apiKey!);
        }
        if (await _portFree(p)) {
          _port = p;
          break;
        }
      }
      final port = _port ?? (throw Exception('No hay puerto libre entre $basePort y ${basePort + 9}'));
      final data = await _data();
      final sep = Platform.pathSeparator;
      final log = File('$data${sep}freellmapi.log').openWrite();
      final env = <String, String>{
        ...b.env,
        'NODE_ENV': 'production',
        'HOST': '127.0.0.1',
        'PORT': '$port',
        'FREEAPI_DESKTOP': '1',
        'ENCRYPTION_KEY': await _encryptionKey(data),
        'FREEAPI_DB_PATH': '$data${sep}freeapi.db',
        'FREEAPI_ENV_PATH': '$data$sep.env',
        'NO_UPDATE_NOTIFIER': '1',
      };
      final proc = await Process.start(b.node, [b.entry], workingDirectory: b.serverDir, environment: env);
      _proc = proc;
      final tail = <String>[];
      void keep(String l) {
        log.writeln(l);
        tail.add(l);
        if (tail.length > 12) tail.removeAt(0);
      }

      proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(keep, onError: (_) {});
      proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(keep, onError: (_) {});
      int? exitCode;
      proc.exitCode.then((c) {
        exitCode = c;
        log.close();
        if (identical(_proc, proc)) {
          _proc = null;
          _apiKey = null;
          if (_state != FreeLlmApiState.stopped) {
            lastError = 'FreeLLMAPI se ha cerrado (código $c). ${tail.join(' ')}'.trim();
            _set(FreeLlmApiState.error);
          }
        }
      });
      final until = DateTime.now().add(const Duration(seconds: 60));
      while (DateTime.now().isBefore(until)) {
        if (exitCode != null) {
          throw Exception('FreeLLMAPI no arranca (código $exitCode): ${tail.join(' ')}');
        }
        final t = await _session(port);
        if (t != null) {
          _apiKey = await _unifiedKey(port, t);
          _set(FreeLlmApiState.running);
          return ('http://127.0.0.1:$port/v1', _apiKey!);
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      throw Exception('FreeLLMAPI no ha arrancado en 60 s: ${tail.join(' ')}');
    } catch (e) {
      lastError = '$e'.replaceFirst('Exception: ', '');
      await stop(keepState: true);
      _set(FreeLlmApiState.error);
      rethrow;
    }
  }

  /// Para el FreeLLMAPI que arrancó Herrero (no toca otros).
  Future<void> stop({bool keepState = false}) async {
    final p = _proc;
    _proc = null;
    _apiKey = null;
    if (!keepState) _set(FreeLlmApiState.stopped);
    if (p == null) return;
    p.kill();
    try {
      await p.exitCode.timeout(const Duration(seconds: 3));
    } catch (_) {
      p.kill(ProcessSignal.sigkill);
    }
  }
}
