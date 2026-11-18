// Descargas verificadas (reanudación, reintentos y SHA-256) y estado de descarga.
//
// Dart puro (sin Flutter): lo usan la app y la TUI de terminal (bin/herrero_tui.dart).
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

enum DlState { notInstalled, downloading, verifying, installed, error }

class ModelStatus {
  DlState state;
  double progress; // 0..1
  int bytesDone;
  int bytesTotal;
  String? error;
  ModelStatus(this.state, {this.progress = 0, this.bytesDone = 0, this.bytesTotal = 0, this.error});
}

class DownloadCancelled implements Exception {
  @override
  String toString() => 'Cancelado';
}

const _maxAttempts = 4;

/// Descarga [url] en [target] con reintentos, reanudación (Range) y SHA-256.
/// [onBytes] recibe los bytes acumulados del fichero.
Future<void> downloadVerified(String url, File target, int size, String sha256hex,
    void Function(int got) onBytes, bool Function() cancelled) async {
  final part = File('${target.path}.part');
  final client = http.Client();
  try {
    for (var attempt = 1;; attempt++) {
      var have = part.existsSync() ? part.lengthSync() : 0;
      if (have > size) {
        part.deleteSync();
        have = 0;
      }
      if (have >= size) break;
      try {
        await _fetchInto(client, url, part, have, size, onBytes, cancelled);
        break;
      } on DownloadCancelled {
        throw Exception('Cancelado');
      } catch (e) {
        final network = e is SocketException || e is http.ClientException || e is TimeoutException;
        if (!network || attempt >= _maxAttempts) rethrow;
        await Future<void>.delayed(Duration(seconds: 2 * attempt));
        if (cancelled()) throw Exception('Cancelado');
      }
    }
  } finally {
    client.close();
  }
  if (!await verifySha256(part.path, sha256hex)) {
    part.deleteSync();
    throw Exception('El fichero ${target.uri.pathSegments.last} está dañado (SHA-256 incorrecto). Vuelve a intentarlo.');
  }
  if (target.existsSync()) target.deleteSync();
  part.renameSync(target.path);
}

Future<void> _fetchInto(http.Client client, String url, File part, int have, int expSize,
    void Function(int got) onBytes, bool Function() cancelled) async {
  final req = http.Request('GET', Uri.parse(url));
  if (have > 0) req.headers['Range'] = 'bytes=$have-';
  final resp = await client.send(req).timeout(const Duration(seconds: 30));
  if (resp.statusCode == 200 && have > 0) {
    have = 0; // el servidor no admite reanudación
  } else if (resp.statusCode != 200 && resp.statusCode != 206) {
    throw Exception('Error HTTP ${resp.statusCode} descargando ${url.split('/').last}');
  }
  final sink = part.openWrite(mode: have > 0 ? FileMode.append : FileMode.write);
  var got = have;
  try {
    await for (final chunk in resp.stream.timeout(const Duration(seconds: 60))) {
      if (cancelled()) throw DownloadCancelled();
      sink.add(chunk);
      got += chunk.length;
      onBytes(got);
    }
  } finally {
    await sink.flush();
    await sink.close();
  }
  if (got < expSize) throw http.ClientException('Conexión cortada en el byte $got de $expSize', Uri.parse(url));
}

Future<bool> verifySha256(String path, String expected) => Isolate.run(() async {
      final digest = await sha256.bind(File(path).openRead()).first;
      return digest.toString() == expected;
    });

/// Mensaje claro para el usuario a partir de un error de red o de disco.
String friendlyDownloadError(Object e) {
  if (e is SocketException || e is http.ClientException || e is TimeoutException) {
    return 'Sin conexión con el servidor (GitHub, NuGet o PyPI). Comprueba internet y vuelve a '
        'intentarlo: la descarga sigue donde se quedó.';
  }
  if (e is TlsException) {
    return 'No se pudo abrir una conexión segura. Comprueba la fecha y hora del equipo.';
  }
  if (e is FileSystemException) {
    return 'No se pudo guardar (${e.osError?.message ?? e.message}). Comprueba el espacio libre.';
  }
  final t = '$e';
  return t.startsWith('Exception: ') ? t.substring('Exception: '.length) : t;
}
