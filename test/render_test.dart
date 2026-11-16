import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/engine/designer.dart';
import 'package:herrero/services/export.dart';
import 'package:herrero/views/drawing_utils.dart';
import 'package:herrero/views/iso_view.dart';
import 'package:herrero/views/plan_view.dart';
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

  final prompts = {
    'nave': 'Nave a dos aguas de 30 x 15 m, 6 m de altura al alero, pórticos cada 6 m, panel sándwich, en Vitoria',
    'marq': 'Marquesina para 2 coches de 5,5 x 5 m y 2,4 m de alto, chapa grecada, galvanizada',
    'alt': 'Altillo de 8 x 4 m a 3 m de altura para almacén, suelo de tramex',
  };
  for (final e in prompts.entries) {
    testWidgets('dibujos ${e.key}', (tester) async {
      await tester.runAsync(() async {
        final d = designFromPrompt(e.value);
        final iso = await paintToImage((c, s) => IsoPainter(d).paint(c, s), const Size(900, 640), 1);
        final mesh = SceneMesh.build(d, Finish.galvanizado);
        final ren = await paintToImage((c, s) => RenderPainter(mesh, OrbitCamera()).paint(c, s), const Size(900, 600), 1);
        expect(iso.width, 900);
        expect(ren.width, 900);
        final sheets = <ui.Image>[];
        for (final v in SheetView.values) {
          sheets.add(await paintToImage((c, s) => SheetPainter(d, v).paint(c, s), const Size(1188, 840), 1));
        }
        final pdf = await buildPdf(d);
        expect(pdf.length, greaterThan(10000));
        if (out != null) {
          await _save(iso, '$out/${e.key}_iso.png');
          await _save(ren, '$out/${e.key}_render.png');
          for (var i = 0; i < sheets.length; i++) {
            await _save(sheets[i], '$out/${e.key}_sheet$i.png');
          }
          File('$out/${e.key}.pdf').writeAsBytesSync(pdf);
        }
      });
    });
  }
}
