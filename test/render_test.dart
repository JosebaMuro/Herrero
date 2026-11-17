import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/engine/catalog.dart';
import 'package:herrero/engine/designer.dart';
import 'package:herrero/services/export.dart';
import 'package:herrero/views/drawing_utils.dart';
import 'package:herrero/views/iso_view.dart';
import 'package:herrero/views/render_view.dart';

Future<void> _save(ui.Image img, String path) async {
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(bd!.buffer.asUint8List());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final out = Platform.environment['HERRERO_OUT'];
  setUpAll(() async {
    final loader = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    await loader.load();
  });

  final prompts = {for (final t in typologies) t.type.name: t.example};
  for (final e in prompts.entries) {
    testWidgets('dibujos ${e.key}', (tester) async {
      await tester.runAsync(() async {
        final d = designFromPrompt(e.value);
        final iso = await paintToImage((c, s) => IsoPainter(d).paint(c, s), const Size(900, 640), 1);
        final sw = Stopwatch()..start();
        final (_, ren) = await renderHq(d, finishFromSpec(d.spec.finish), OrbitCamera(), width: 900, height: 600, ss: 1);
        // ignore: avoid_print
        print('${e.key}: render z-buffer 900x600 en ${sw.elapsedMilliseconds} ms');
        expect(iso.width, 900);
        expect(ren.width, 900);
        final pdf = await buildPdf(d);
        expect(pdf.length, greaterThan(10000));
        if (out != null) {
          await _save(iso, '$out/${e.key}_iso.png');
          await _save(ren, '$out/${e.key}_render.png');
          File('$out/${e.key}.pdf').writeAsBytesSync(pdf);
        }
      });
    });
  }
}
