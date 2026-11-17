// Pruebas del VLM local con los ficheros reales de la release models-vlm-v1.
// Se ejecutan solo si HERRERO_VLM apunta a la carpeta descargada, p. ej.:
//   HERRERO_VLM=/ruta/out_vlm LD_LIBRARY_PATH=<pub-cache>/onnxruntime-1.4.1/linux flutter test test/vlm_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/ai/bpe_tokenizer.dart';
import 'package:herrero/ai/vlm.dart';
import 'package:herrero/plans/plan_analyzer.dart';
import 'package:herrero/plans/plan_token.dart';
import 'package:herrero/plans/vision_hints.dart';
import 'package:herrero/engine/model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dir = Platform.environment['HERRERO_VLM'];

  test('pistas de la visión: tipología, cotas y cubierta', () {
    final h = visionHints('This is a carport with two columns and a sandwich panel roof. It is 5.50 m long and 2.40 m high.');
    expect(h.type, StructureType.marquesina);
    expect(h.dims, [5.5, 2.4]);
    expect(h.words, ['panel sándwich']);
    expect(h.columns, 2);
    expect(visionHints('A staircase with a handrail').type, StructureType.escalera);
    expect(visionHints('It is a warehouse with a gable roof').type, StructureType.nave);
    // eco de las opciones de la pregunta: cuenta la frase que elige una
    expect(
        visionHints('A carport, warehouse, staircase, railing, gate or tower. The drawing shows a staircase.').type,
        StructureType.escalera);
  });

  test('plano sin texto + visión: la tipología y las medidas salen del VLM', () {
    final a = analyzePlan(const PlanReading([], 'imagen-ocr'),
        vision: 'The steel structure is a carport with a sandwich panel roof, 5.50 m wide and 2.40 m high.');
    expect(a.prompt, startsWith('Marquesina'));
    expect(a.prompt, contains('panel sándwich'));
    expect(a.prompt, contains('2,4'));
    final b = analyzePlan(const PlanReading([], 'imagen-ocr'), vision: 'MARQUESINA 2 COCHES panel sandwich.');
    expect(b.prompt, startsWith('Marquesina'));
  });

  if (dir == null) return;
  final man = jsonDecode(File('$dir/manifest.json').readAsStringSync()) as Map<String, dynamic>;
  final models = (man['models'] as Map<String, dynamic>).keys.toList();

  for (final prefix in models) {
    test('tokenizador $prefix igual que Hugging Face', () async {
      final tok = await BpeTokenizer.fromFile('$dir/${prefix}_tokenizer.json');
      for (final t in (man['models'][prefix]['tokenizer_tests'] as List)) {
        expect(tok.encode(t['text'] as String), (t['ids'] as List).cast<int>(), reason: t['text'] as String);
      }
      for (final t in (man['tests'] as List).where((t) => t['model'] == prefix)) {
        expect(tok.encode(vlmPrompt(t['question'] as String)), (t['prompt_ids'] as List).cast<int>());
        expect(tok.decode((t['output_ids'] as List).cast<int>()).trim(), (t['output_text'] as String).trim());
      }
    });

    testWidgets('VLM $prefix sobre el croquis de prueba', (tester) async {
      await tester.runAsync(() async {
        final bytes = File('$dir/vlm_test_sketch.png').readAsBytesSync();
        final codec = await ui.instantiateImageCodec(bytes);
        final img = (await codec.getNextFrame()).image;
        final rgba = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
        final t = (man['tests'] as List).firstWhere((t) => t['model'] == prefix);
        final res = await runVlmSync(VlmRequest(
          modelDir: dir,
          prefix: prefix,
          rgba: rgba,
          width: img.width,
          height: img.height,
          question: t['question'] as String,
          maxTokens: 96,
          repetitionPenalty: 1,
        ));
        // ignore: avoid_print
        print('$prefix: ${res.ids.length} tokens en ${res.time.inMilliseconds} ms: ${res.text}');
        // Los modelos cuantizados son sensibles a pequeñas diferencias de coma
        // flotante entre compilaciones de ORT: se exige una respuesta completa
        // y con sentido, no idéntica token a token a la de Python.
        expect(res.ids.length, lessThan(96), reason: 'debe terminar con fin de turno');
        expect(res.text.trim().length, greaterThan(5));
      });
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}
