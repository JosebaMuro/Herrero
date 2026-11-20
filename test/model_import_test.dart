import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/ai/accel.dart';
import 'package:herrero/ai/engine_plan.dart';
import 'package:herrero/ai/model_import.dart';
import 'package:herrero/ai/model_manager.dart';
import 'package:herrero/ai/onnx_inspect.dart';

/// Gestor de modelos: lectura de cabeceras ONNX, reconocimiento de ficheros importados
/// y elección del motor según el hardware.
void main() {
  final tiny = 'test${Platform.pathSeparator}data${Platform.pathSeparator}tiny_accel.onnx';

  group('cabecera ONNX', () {
    test('lee IR, opset, entradas y salidas de un modelo real', () {
      final i = inspectModelFile(tiny);
      expect(i.format, ModelFormat.onnx);
      expect(i.irVersion, greaterThan(0));
      expect(i.onnxOpset, greaterThan(0));
      expect(i.inputs, contains('x'));
      expect(i.outputs, isNotEmpty);
      expect(i.externalData, isFalse);
      expect(ortCompatibilityProblems(i), isEmpty);
    });

    test('un fichero cortado se detecta', () {
      final bytes = File(tiny).readAsBytesSync();
      final cut = File('${Directory.systemTemp.createTempSync('herrero').path}/cortado.onnx')
        ..writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));
      expect(() => inspectModelFile(cut.path), throwsA(isA<ModelFormatException>()));
    });

    test('reconoce formatos que no son ONNX y explica qué hacer', () {
      Uint8List b(String s) => Uint8List.fromList([...s.codeUnits, ...List.filled(16, 0)]);
      expect(sniffFormat(b('GGUF'), 'qwen.gguf'), ModelFormat.gguf);
      expect(sniffFormat(Uint8List.fromList([0, 0, 0, 0, ...'TFL3'.codeUnits, 0, 0]), 'm.tflite'), ModelFormat.tflite);
      final st = Uint8List(16);
      ByteData.sublistView(st).setUint64(0, 120, Endian.little);
      st[8] = 0x7B;
      expect(sniffFormat(st, 'model.safetensors'), ModelFormat.safetensors);
      expect(sniffFormat(Uint8List.fromList([0x50, 0x4B, 3, 4]), 'pytorch_model.bin'), ModelFormat.pytorch);
      expect(sniffFormat(b('{"model": {}}'), 'tokenizer.json'), ModelFormat.json);
      expect(ortCompatibilityProblems(const OnnxInfo(format: ModelFormat.gguf)).single, contains('GGUF'));
    });

    test('rechaza lo que ONNX Runtime 1.20 no puede abrir', () {
      const nuevo = OnnxInfo(format: ModelFormat.onnx, irVersion: 11, opsets: {'': 23});
      expect(ortCompatibilityProblems(nuevo), hasLength(2));
      const raro = OnnxInfo(format: ModelFormat.onnx, irVersion: 8, opsets: {'': 17, 'com.acme': 1});
      expect(ortCompatibilityProblems(raro).single, contains('com.acme'));
      const ext = OnnxInfo(format: ModelFormat.onnx, irVersion: 8, opsets: {'': 17}, externalData: true);
      expect(ortCompatibilityProblems(ext).single, contains('.onnx_data'));
    });
  });

  group('reconocer ficheros importados', () {
    test('por nombre exacto', () {
      final c = candidatesFor('C:\\Descargas\\qwen3_model_int8.onnx', const OnnxInfo(format: ModelFormat.onnx));
      expect(c.single.variant.id, 'qwen3-0.6b');
    });

    test('por las entradas del modelo cuando el nombre es otro', () {
      const unet = OnnxInfo(format: ModelFormat.onnx, irVersion: 8, inputs: ['sample', 'timestep', 'encoder_hidden_states']);
      expect(candidatesFor('model.onnx', unet).map((t) => t.file).toSet(), {'sdturbo_unet_int8.onnx'});
      const det = OnnxInfo(format: ModelFormat.onnx, irVersion: 8, inputs: ['x']);
      expect(candidatesFor('ch_PP-OCRv4_det_infer.onnx', det).single.file, 'ppocrv4_det.onnx');
      // un decodificador de SmolVLM vale para el 256M y el 500M: se pregunta
      const dec = OnnxInfo(format: ModelFormat.onnx, irVersion: 8, inputs: ['inputs_embeds', 'attention_mask', 'position_ids']);
      expect(candidatesFor('decoder_model_merged_int8.onnx', dec).length, 2);
      expect(candidatesFor('decoder_model_merged_int8_500.onnx', dec).single.file, 'smolvlm500_decoder_int8.onnx');
    });

    test('tokenizadores y configuraciones por el nombre', () {
      const j = OnnxInfo(format: ModelFormat.json);
      expect(candidatesFor('Qwen3-0.6B-tokenizer.json', j).single.file, 'qwen3_tokenizer.json');
      final only = catalog.firstWhere((m) => m.id == 'e5-small');
      expect(candidatesFor('tokenizer.json', j, only: only).single.file, 'e5s_tokenizer.json');
      expect(candidatesFor('foto.png', const OnnxInfo(format: ModelFormat.unknown)), isEmpty);
    });

    test('rechaza un ONNX que no tiene las entradas que usa la app', () async {
      final unet = allTargets().firstWhere((t) => t.file == 'sdturbo_unet_int8.onnx');
      final c = await checkImport(tiny, unet);
      expect(c.ok, isFalse);
      expect(c.errors.single, contains('encoder_hidden_states'));
    });

    test('rechaza un tokenizador que no es JSON', () async {
      final f = File('${Directory.systemTemp.createTempSync('herrero').path}/tokenizer.json')..writeAsStringSync('hola');
      final t = allTargets().firstWhere((t) => t.file == 'qwen3_tokenizer.json');
      final c = await checkImport(f.path, t);
      expect(c.ok, isFalse);
    });

    test('acepta un ONNX compatible que el motor de la app abre', () async {
      final det = allTargets().firstWhere((t) => t.file == 'ppocrv4_det.onnx');
      final c = await checkImport(tiny, det, officialSha: 'otro', officialSize: 1);
      expect(c.errors, isEmpty);
      expect(c.warnings.single, contains('No es idéntico'));
    }, skip: Platform.environment['HERRERO_ORT_TEST'] == '1' ? false : 'necesita ONNX Runtime (HERRERO_ORT_TEST=1)');
  });

  group('motor según el hardware', () {
    const win = HardwareInfo(platform: 'Windows', gpus: ['NVIDIA GeForce RTX 3060']);
    test('Windows con NVIDIA: DirectML y aviso de CUDA; con el paquete, CUDA', () {
      final d = decideEngine(ModelTask.reason, win);
      expect(d.engine, AiEngine.auto);
      expect(d.runsOn, contains('DirectML'));
      expect(d.tip, contains('CUDA'));
      final c = decideEngine(ModelTask.reason, win, packs: {'cuda'});
      expect(c.runsOn, contains('CUDA'));
      expect(c.tip, isEmpty);
    });

    test('modelos pequeños en CPU', () {
      expect(decideEngine(ModelTask.understand, win).engine, AiEngine.cpu);
      expect(decideEngine(ModelTask.plans, win).engine, AiEngine.cpu);
    });

    test('Android: NNAPI solo donde sirve y nada si es anterior a 8.1', () {
      const viejo = HardwareInfo(platform: 'Android', androidSdk: 26);
      expect(decideEngine(ModelTask.photo, viejo).engine, AiEngine.cpu);
      const nuevo = HardwareInfo(platform: 'Android', androidSdk: 34, soc: 'SM8550');
      final foto = decideEngine(ModelTask.photo, nuevo);
      expect(foto.runsOn, contains('NNAPI'));
      expect(foto.runsOn, contains('Snapdragon'));
      expect(decideEngine(ModelTask.reason, nuevo).runsOn, 'CPU');
    });

    test('lo fijado a mano manda, por tarea o en general', () {
      final t = decideEngine(ModelTask.photo, win, override: AiEngine.cpu);
      expect(t.engine, AiEngine.cpu);
      expect(t.manual, isTrue);
      final g = decideEngine(ModelTask.understand, win, global: AiEngine.directml);
      expect(g.engine, AiEngine.directml);
      final falta = decideEngine(ModelTask.photo, win, global: AiEngine.cuda);
      expect(falta.reason, contains('Falta su paquete'));
    });
  });
}
