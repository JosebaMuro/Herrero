// FreeLLMAPI integrado en Android. Android solo deja ejecutar programas que
// vengan dentro del APK como bibliotecas, así que el CI mete ahí (jniLibs, ver
// scripts/android_node.py):
//   libnode.so               Node.js de Termux (arm64)
//   libherrero_*.so          sus bibliotecas, renombradas
//   libfreellmapi_app.so     tar.gz con FreeLLMAPI (JavaScript) y los certificados
// Aquí se descomprime FreeLLMAPI en la carpeta de la app la primera vez.
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';

import 'freellmapi_local.dart';

/// Carpeta de bibliotecas nativas de la app (la de libflutter.so).
String? androidNativeLibDir([String maps = '/proc/self/maps']) {
  try {
    for (final l in File(maps).readAsLinesSync()) {
      final i = l.indexOf('/');
      if (i < 0) continue;
      final path = l.substring(i).trim();
      if (path.endsWith('/libflutter.so') || path.endsWith('/libapp.so')) {
        if (path.contains('!/')) return null; // sin extraer (dentro del APK): no se puede ejecutar
        return File(path).parent.path;
      }
    }
  } catch (_) {}
  return null;
}

Future<FreeLlmApiBundle?> prepareAndroidFreeLlmApi() async {
  final lib = androidNativeLibDir();
  if (lib == null) return null;
  final node = '$lib/libnode.so';
  final pack = File('$lib/libfreellmapi_app.so');
  if (!File(node).existsSync() || !pack.existsSync()) return null;
  final base = '${(await getApplicationSupportDirectory()).path}/freellmapi-pack';
  final stamp = File('$base/.stamp');
  final want = '${pack.lengthSync()}-${pack.lastModifiedSync().millisecondsSinceEpoch}';
  if (!stamp.existsSync() || stamp.readAsStringSync() != want) {
    final tmp = Directory('$base.tmp');
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    final src = pack.path, dst = tmp.path;
    await Isolate.run(() => extractFileToDisk(src, dst));
    final old = Directory(base);
    if (old.existsSync()) old.deleteSync(recursive: true);
    tmp.renameSync(base);
    File('$base/.stamp').writeAsStringSync(want);
  }
  final cache = (await getTemporaryDirectory()).path;
  final cnf = File('$base/openssl.cnf');
  if (!cnf.existsSync()) cnf.writeAsStringSync('# Herrero\n');
  final cert = '$base/cert.pem';
  return FreeLlmApiBundle(
    node: node,
    appDir: '$base/app',
    env: {
      'LD_LIBRARY_PATH': lib,
      'OPENSSL_CONF': cnf.path,
      'SSL_CERT_FILE': cert,
      'NODE_EXTRA_CA_CERTS': cert,
      'TMPDIR': cache,
      'HOME': base,
    },
  );
}
