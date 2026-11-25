// Alternativa en castellano: jina-embeddings-v2-base-es y SmolLM3 con
// razonamiento. Con HERRERO_REASON_ES=<carpeta de models-reason-es-v1> y
// LD_LIBRARY_PATH=<pub-cache>/onnxruntime-1.4.1/linux prueba también los
// modelos reales (tokenizadores, embeddings y razonamiento).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/ai/bpe_tokenizer.dart';
import 'package:herrero/ai/comprehension_core.dart';
import 'package:herrero/ai/local_text.dart';
import 'package:herrero/ai/model_manager.dart';
import 'package:herrero/engine/model.dart';
import 'package:herrero/engine/understanding.dart';

/// Tokenizador BPE mínimo con el post-procesador indicado.
BpeTokenizer _tok(Map<String, dynamic>? post) => BpeTokenizer.fromJson({
      'model': {
        'type': 'BPE',
        'vocab': {'<s>': 0, '</s>': 2, 'h': 5, 'o': 6, 'ho': 7, '<|begin_of_text|>': 9},
        'merges': ['h o'],
      },
      'added_tokens': [
        {'id': 0, 'content': '<s>', 'special': true},
        {'id': 2, 'content': '</s>', 'special': true},
        {'id': 9, 'content': '<|begin_of_text|>', 'special': true},
      ],
      'post_processor': post,
    });

void main() {
  group('catálogo y elección', () {
    test('cada tarea tiene la alternativa en castellano', () {
      final jina = catalog.firstWhere((m) => m.id == 'jina-es');
      final smol = catalog.firstWhere((m) => m.id == 'smollm3-3b');
      expect(jina.task, ModelTask.understand);
      expect(smol.task, ModelTask.reason);
      expect(smol.pcOnly, isTrue);
      expect(ModelManager.hasChoice(ModelTask.understand), isTrue);
      expect(ModelManager.hasChoice(ModelTask.reason), isTrue);
      // otra carpeta: cada release trae su manifest.json
      expect(jina.subdir, 'reason-es');
      expect(smol.subdir, 'reason-es');
      expect(catalog.firstWhere((m) => m.id == 'e5-small').subdir, 'reason');
      // el multilingüe sigue siendo el de serie
      expect(catalog.firstWhere((m) => m.task == ModelTask.understand).id, 'e5-small');
      expect(catalog.firstWhere((m) => m.task == ModelTask.reason).id, 'qwen3-0.6b');
      expect(smol.files, contains(llmModelFile('smollm3')));
      expect(smol.files.where((f) => f.contains('.onnx_data')), isNotEmpty);
    });

    test('prefijos de los embeddings', () {
      expect(embedSpecFor('jinaes').query, '');
      expect(embedSpecFor('e5s').query, 'query: ');
      expect(intentPassages('').first.$2, isNot(startsWith('passage: ')));
      expect(intentPassages().first.$2, startsWith('passage: '));
    });
  });

  group('tokenizador BPE con post-procesador', () {
    test('RoBERTa: <s> ... </s>', () {
      final t = _tok({
        'type': 'RobertaProcessing',
        'sep': ['</s>', 2],
        'cls': ['<s>', 0],
      });
      expect(t.encode('ho'), [7]);
      expect(t.encodeWithSpecials('ho'), [0, 7, 2]);
    });

    test('plantilla de Llama 3 y sin post-procesador', () {
      final t = _tok({
        'type': 'TemplateProcessing',
        'single': [
          {'SpecialToken': {'id': '<|begin_of_text|>', 'type_id': 0}},
          {'Sequence': {'id': 'A', 'type_id': 0}},
        ],
        'special_tokens': {
          '<|begin_of_text|>': {'id': '<|begin_of_text|>', 'ids': [9], 'tokens': ['<|begin_of_text|>']},
        },
      });
      expect(t.encodeWithSpecials('ho'), [9, 7]);
      expect(_tok(null).encodeWithSpecials('ho'), [7]);
    });
  });

  group('razonamiento', () {
    test('la conversación deja pensar y la ficha se fuerza después', () {
      final c = llmThinkChat('nave de 24 m de luz', StructureType.nave);
      expect(c, contains('Reasoning Mode: /think'));
      expect(c, contains(llmThinkHint));
      expect(c, endsWith('<|im_start|>assistant\n<think>\n'));
      for (final (q, a) in llmExamples) {
        expect(c, contains('Petición: $q<|im_end|>\n<|im_start|>assistant\n$a<|im_end|>'));
      }
      final r = llmRequestFor('/m', 'smollm3', 'nave de 24 m de luz', StructureType.nave);
      expect(r.thinkBudget, greaterThan(0));
      expect(r.afterThink, llmSeed(StructureType.nave));
      expect(r.file, 'smollm3_model_q4.onnx');
      final q = llmRequestFor('/m', 'qwen3', 'nave', StructureType.nave);
      expect(q.thinkBudget, 0);
      expect(q.file, 'qwen3_model_int8.onnx');
      expect(q.prompt, llmChat('nave', StructureType.nave));
    });
  });

  final dir = Platform.environment['HERRERO_REASON_ES'];
  if (dir == null) return;
  final man = jsonDecode(File('$dir/manifest.json').readAsStringSync()) as Map<String, dynamic>;

  test('tokenizadores iguales que Hugging Face', () async {
    for (final prefix in ['jinaes', 'smollm3']) {
      final t = await BpeTokenizer.fromFile('$dir/${prefix}_tokenizer.json');
      for (final x in man['models'][prefix]['tokenizer_tests'] as List) {
        expect(t.encodeWithSpecials(x['text'] as String), (x['ids'] as List).cast<int>(),
            reason: '$prefix: ${x['text']}');
      }
    }
    // el prompt de razonamiento se tokeniza igual que en la prueba de Python
    final t = await BpeTokenizer.fromFile('$dir/smollm3_tokenizer.json');
    for (final r in man['models']['smollm3']['reference'] as List) {
      final type = StructureType.values.byName(r['tipo'] as String);
      expect(t.encode(llmThinkChat(r['prompt'] as String, type)), (r['prompt_ids'] as List).cast<int>());
    }
  });

  test('embeddings en castellano: referencia y tipología', () async {
    final ref = man['models']['jinaes']['reference'];
    final v = (await runEmbedSync(EmbedRequest(dir, [ref['text'] as String], prefix: 'jinaes')))[0];
    final head = (ref['head'] as List).cast<num>();
    for (var i = 0; i < head.length; i++) {
      expect(v[i], closeTo(head[i].toDouble(), 0.02));
    }
    final engine = ComprehensionEngine(dir, embed: jinaEsSpec);
    expect(engine.embedReady, isTrue);
    final r = await engine.rank('quiero proteger el coche del granizo en el patio');
    // ignore: avoid_print
    print(r.take(3).map((e) => '${e.$1.name} ${e.$2.toStringAsFixed(3)}').join(', '));
    expect(r.first.$1, StructureType.marquesina);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('SmolLM3 razona y rellena la ficha', () async {
    expect(ComprehensionEngine(dir).reasonReady('smollm3'), isTrue);
    for (final r in (man['models']['smollm3']['reference'] as List).take(2)) {
      final p = r['prompt'] as String;
      final type = StructureType.values.byName(r['tipo'] as String);
      final partial = <String>[];
      final res = await runLlmSync(llmRequestFor(dir, 'smollm3', p, type), partial.add);
      final j = parseLlmJson(res.text, llmSeed(type));
      // ignore: avoid_print
      print('${res.time.inSeconds} s; razonamiento: ${res.thought}\n -> ${llmSeed(type)}${res.text}');
      expect(res.thought, isNotEmpty);
      expect(partial.first, startsWith(thinkingLabel));
      expect(j, isNotNull);
      expect(j!['tipo'], type.name);
      final u = understand(p, llm: j);
      // ignore: avoid_print
      print('   -> ${u.spec.length} x ${u.spec.width} x ${u.spec.height}, ${u.spec.roofing}; ${u.notes.join(' / ')}');
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
