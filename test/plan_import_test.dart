import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/plans/ocr_engine.dart';
import 'package:herrero/plans/pdf_text.dart';
import 'package:herrero/plans/plan_analyzer.dart';
import 'package:herrero/plans/plan_token.dart';

void _show(PlanAnalysis a) {
  // ignore: avoid_print
  print('PROMPT: ${a.prompt}');
  for (final f in a.findings) {
    // ignore: avoid_print
    print('  ${f.guessed ? '?' : '✓'} ${f.label}: ${f.value}');
  }
  for (final w in a.warnings) {
    // ignore: avoid_print
    print('  ! $w');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final ocrDir = Platform.environment['HERRERO_OCR'];
  final imgs = Platform.environment['HERRERO_PLAN_IMGS'];
  final pdf = Platform.environment['HERRERO_PDF'];

  test('PDF vectorial', () {
    final r = PdfTextReader.read(File(pdf!).readAsBytesSync());
    _show(analyzePlan(r));
  }, skip: pdf == null);

  testWidgets('imágenes por OCR', (tester) async {
    await tester.runAsync(() async {
      for (final path in imgs!.split(',')) {
        final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
        final fr = await codec.getNextFrame();
        final bd = await fr.image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final toks = ocrSync(OcrRequest(
            modelDir: ocrDir!, rgba: bd!.buffer.asUint8List(), width: fr.image.width, height: fr.image.height));
        // ignore: avoid_print
        print('== $path (${toks.length} textos)');
        _show(analyzePlan(PlanReading(toks, 'imagen-ocr')));
      }
    });
  }, skip: ocrDir == null || imgs == null);

  test('analizador con textos sintéticos', () {
    final toks = [
      const PlanToken('NAVE INDUSTRIAL - PLANTA', 0, 0, 300, 20),
      for (var i = 0; i < 5; i++) PlanToken('6000', 100.0 + i * 100, 400, 140.0 + i * 100, 412),
      const PlanToken('30000', 300, 430, 350, 442),
      const PlanToken('15000', 40, 200, 52, 260, vertical: true),
      const PlanToken('+6,50', 600, 100, 640, 112),
      const PlanToken('+8,00', 600, 60, 640, 72),
      const PlanToken('Pilares HEB 220', 600, 300, 700, 312),
      const PlanToken('Cubierta panel sándwich 40 mm', 600, 320, 760, 332),
      const PlanToken('Emplazamiento: Vitoria', 600, 340, 760, 352),
    ];
    final a = analyzePlan(PlanReading(toks, 'pdf-texto'));
    _show(a);
    expect(a.prompt, contains('Nave'));
    expect(a.prompt, contains('30 x 15'));
    expect(a.prompt, contains('cada 6'));
    expect(a.prompt, contains('6,5'));
    expect(a.prompt, contains('HEB 220'));
    expect(a.prompt, contains('sándwich de 40 mm'));
    expect(a.prompt, contains('Vitoria'));
  });
}
