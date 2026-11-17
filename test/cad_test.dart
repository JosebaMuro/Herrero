import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/cad/cad_painter.dart';
import 'package:herrero/cad/sheets.dart';
import 'package:herrero/engine/catalog.dart';
import 'package:herrero/engine/designer.dart';
import 'package:herrero/views/drawing_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final out = Platform.environment['HERRERO_OUT'];
  setUpAll(() async {
    final loader = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    await loader.load();
  });
  for (final t in typologies) {
    testWidgets('planos CAD ${t.type.name}', (tester) async {
      await tester.runAsync(() async {
        final d = designFromPrompt(t.example);
        final sheets = buildSheets(d);
        expect(sheets.length, greaterThanOrEqualTo(6));
        for (final s in sheets) {
          expect(s.ents, isNotEmpty);
          final (x0, y0, x1, y1) = s.bounds;
          expect(x0, greaterThanOrEqualTo(-1), reason: '${s.number} se sale por la izquierda');
          expect(y0, greaterThanOrEqualTo(-1), reason: '${s.number} se sale por abajo');
          expect(x1, lessThanOrEqualTo(s.width + 1), reason: '${s.number} se sale por la derecha');
          expect(y1, lessThanOrEqualTo(s.height + 1), reason: '${s.number} se sale por arriba');
        }
        if (out != null) {
          for (final s in sheets) {
            final img = await paintToImage((c, sz) => CadPainter(s).paint(c, sz), const Size(1680, 1188), 1);
            final bd = await img.toByteData(format: ui.ImageByteFormat.png);
            File('$out/cad_${t.type.name}_${s.number}.png').writeAsBytesSync(bd!.buffer.asUint8List());
          }
        }
      });
    });
  }
}
