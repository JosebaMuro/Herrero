// Gestor de modelos: mensajes de error y, con HERRERO_DL=1, descarga real del
// OCR desde la release de GitHub (redirecciones, reanudación y SHA-256).
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/ai/model_manager.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _RealHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final ca = Platform.environment['SSL_CERT_FILE'];
    final ctx = SecurityContext(withTrustedRoots: true);
    if (ca != null) ctx.setTrustedCertificates(ca);
    return super.createHttpClient(ctx)..findProxy = HttpClient.findProxyFromEnvironment;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('errores de descarga con mensaje claro', () {
    final f = ModelManager.friendlyDownloadError;
    expect(f(const SocketException('Failed host lookup')), contains('Sin conexión'));
    expect(f(http.ClientException('Connection closed')), contains('Sin conexión'));
    expect(f(TimeoutException('lento')), contains('Sin conexión'));
    expect(f(const HandshakeException('x')), contains('conexión segura'));
    expect(f(const FileSystemException('x', '/a', OSError('No space left on device', 28))), contains('espacio libre'));
    expect(f(Exception('Error HTTP 404 descargando a.onnx')), 'Error HTTP 404 descargando a.onnx');
  });

  test('el APK de release pide permiso de internet', () {
    // Flutter solo lo pone en debug y profile: sin él, ninguna descarga funciona en el móvil.
    final man = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(man, contains('<uses-permission android:name="android.permission.INTERNET"/>'));
  });

  final dir = Platform.environment['HERRERO_DL'];
  if (dir == null) return;

  test('descarga real del OCR desde GitHub', () async {
    HttpOverrides.global = _RealHttp();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), (call) async => dir);
    final mgr = ModelManager.instance;
    await mgr.fetchManifest();
    expect(mgr.manifests.length, 3);
    final ocr = catalog.firstWhere((m) => m.task == ModelTask.plans);
    await mgr.download(ocr);
    final st = mgr.status[ocr.id]!;
    expect(st.state, DlState.installed, reason: st.error);
    for (final f in ocr.files) {
      expect(File('$dir/models/ocr/$f').lengthSync(), mgr.fileSize(ocr, f));
    }
    // reanudación: se deja medio fichero en .part y se vuelve a descargar
    final rec = File('$dir/models/ocr/ppocrv4_rec.onnx');
    File('${rec.path}.part').writeAsBytesSync(rec.readAsBytesSync().sublist(0, 3000000));
    rec.deleteSync();
    await mgr.download(ocr);
    expect(mgr.status[ocr.id]!.state, DlState.installed, reason: mgr.status[ocr.id]!.error);
    expect(rec.lengthSync(), mgr.fileSize(ocr, 'ppocrv4_rec.onnx'));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
