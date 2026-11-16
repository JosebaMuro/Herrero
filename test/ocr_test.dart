import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/plans/ocr_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dir = Platform.environment['HERRERO_OCR'];
  final img = Platform.environment['HERRERO_OCR_IMG'];
  testWidgets('OCR de un plano', (tester) async {
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(File(img!).readAsBytesSync());
      final fr = await codec.getNextFrame();
      final bd = await fr.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final sw = Stopwatch()..start();
      final toks = ocrSync(OcrRequest(
          modelDir: dir!, rgba: bd!.buffer.asUint8List(), width: fr.image.width, height: fr.image.height));
      // ignore: avoid_print
      print('${toks.length} textos en ${sw.elapsedMilliseconds} ms');
      for (final t in toks) {
        // ignore: avoid_print
        print('  $t  ${t.confidence.toStringAsFixed(2)}');
      }
      expect(toks, isNotEmpty);
    });
  }, skip: dir == null || img == null);
}
