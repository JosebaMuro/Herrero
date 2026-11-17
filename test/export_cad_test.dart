import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/cad/cad_pdf.dart';
import 'package:herrero/cad/collada.dart';
import 'package:herrero/cad/dxf.dart';
import 'package:herrero/cad/sheets.dart';
import 'package:herrero/engine/catalog.dart';
import 'package:herrero/engine/designer.dart';
import 'package:herrero/views/render_view.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  final out = Platform.environment['HERRERO_OUT'];
  for (final t in typologies) {
    test('exportación CAD ${t.type.name}', () async {
      final d = designFromPrompt(t.example);
      final groups = SceneMesh.groups(d, finishFromSpec(d.spec.finish));
      // una pieza por barra como mínimo, todas con triángulos completos
      expect(groups.length, greaterThanOrEqualTo(d.members.length));
      for (final g in groups) {
        expect(g.tris.length % 9, 0);
        expect(g.tris, isNotEmpty);
        expect(g.layer, matches(RegExp(r'^[A-Z0-9_]+$')));
      }
      final dae = utf8.decode(colladaModel(groups, title: t.type.name));
      expect(dae, startsWith('<?xml'));
      expect(dae, contains('<up_axis>Z_UP</up_axis>'));
      expect('<node '.allMatches(dae).length, groups.length);
      final dxf3 = latin1.decode(modelDxf(groups));
      expect(dxf3, contains('3DFACE'));
      expect(dxf3.trimRight(), endsWith('EOF'));
      final dxf2 = latin1.decode(sheetsDxf(buildSheets(d)));
      expect(dxf2, contains('LTYPE'));
      expect(dxf2.trimRight(), endsWith('EOF'));

      final reg = pw.Font.ttf(File('assets/fonts/Roboto-Regular.ttf').readAsBytesSync().buffer.asByteData());
      final bold = pw.Font.ttf(File('assets/fonts/Roboto-Bold.ttf').readAsBytesSync().buffer.asByteData());
      final doc = pw.Document();
      addCadPages(doc, buildSheets(d), reg, bold);
      final pdf = await doc.save();
      expect(pdf.length, greaterThan(10000));
      if (out != null) {
        File('$out/${t.type.name}.dae').writeAsStringSync(dae);
        File('$out/${t.type.name}_3d.dxf').writeAsStringSync(dxf3, encoding: latin1);
        File('$out/${t.type.name}_planos.dxf').writeAsStringSync(dxf2, encoding: latin1);
        File('$out/${t.type.name}_planos.pdf').writeAsBytesSync(pdf);
      }
    });
  }
}
