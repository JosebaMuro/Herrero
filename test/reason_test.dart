// Comprensión de la petición: reglas, finalidad, razonamiento de oficio y
// fusión con la IA. Con HERRERO_REASON=<carpeta de models-reason-v1> y
// LD_LIBRARY_PATH=<pub-cache>/onnxruntime-1.4.1/linux prueba también los
// modelos reales (tokenizadores, embeddings y LLM).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/ai/bpe_tokenizer.dart';
import 'package:herrero/ai/comprehension.dart';
import 'package:herrero/ai/local_text.dart';
import 'package:herrero/engine/designer.dart';
import 'package:herrero/engine/model.dart';
import 'package:herrero/engine/reasoning.dart';
import 'package:herrero/engine/understanding.dart';

/// Peticiones coloquiales con la tipología esperada.
const colloquial = <(StructureType, String)>[
  (StructureType.marquesina, 'Tejavana para guardar el tractor, unos ocho metros de largo, en Soria'),
  (StructureType.escalera, 'Necesito algo para subir al altillo del taller, hay 3 metros de altura'),
  (StructureType.marquesina, 'un sitio cubierto para aparcar dos coches con placas solares encima'),
  (StructureType.portico, 'una estructura para colgar un polipasto de 2 toneladas en el taller, 6 m de luz'),
  (StructureType.nave, 'un almacén de 40 por 20 con 7 metros libres en Teruel con cerramiento de panel'),
  (StructureType.estanteria, 'poner baldas metálicas para palets, cuatro alturas'),
  (StructureType.marquesina, 'un techo para dar sombra en la terraza del bar'),
  (StructureType.pasarela, 'algo para cruzar por encima de la carretera andando'),
  (StructureType.valla, 'cerrar la finca con postes y malla'),
  (StructureType.entreplanta, 'una plataforma para poner el aire acondicionado encima del tejado'),
  (StructureType.nave, 'quiero hacer una cuadra para 10 caballos'),
  (StructureType.cancela, 'una puerta grande para que entre el tractor a la finca'),
  (StructureType.barandilla, 'que no se caigan los niños por el hueco de la escalera'),
  (StructureType.torre, 'levantar el depósito de gasoil a 3 metros del suelo'),
  (StructureType.poste, 'un soporte para el cartel de mi negocio junto a la carretera'),
  (StructureType.escalera, 'bajar al sótano desde el patio'),
  (StructureType.pasarela, 'unir las dos naves por arriba para pasar con carretillas'),
];

/// Otras formas de pedir, sin palabras del catálogo (para los embeddings).
const unseen = <(StructureType, String)>[
  (StructureType.marquesina, 'quiero proteger el coche del granizo en el patio'),
  (StructureType.nave, 'un edificio grande para meter las cosechadoras y el grano'),
  (StructureType.entreplanta, 'ganar metros en el local haciendo un piso por dentro'),
  (StructureType.escalera, 'necesito poder llegar a la azotea desde la calle'),
  (StructureType.estanteria, 'donde colocar las cajas de la tienda en altura'),
  (StructureType.valla, 'separar mi terreno del vecino con algo metálico'),
  (StructureType.cancela, 'algo que se abra para que entren los coches a la urbanización'),
  (StructureType.poste, 'sujetar una bandera bien alta en la rotonda'),
];

void main() {
  group('comprensión sin modelos', () {
    test('caso de Joseba: todo sale del texto', () {
      final u = understand('Marquesina para 2 coches de 5,5 x 5 m y 2,4 m de alto, panel sándwich, galvanizada');
      expect(u.type, StructureType.marquesina);
      expect(u.typeSource, DataSource.text);
      expect([u.spec.length, u.spec.width, u.spec.height], [5.5, 5.0, 2.4]);
      expect(u.spec.roofing, startsWith('panel sándwich'));
      expect(u.spec.finish, contains('galvanizado'));
      for (final f in ['length', 'width', 'height', 'roofing', 'finish']) {
        expect(u.sources[f], DataSource.text, reason: f);
      }
    });

    test('tipología por palabras y por finalidad', () {
      var ok = 0;
      for (final (exp, p) in colloquial) {
        if (understand(p).type == exp) ok++;
      }
      expect(ok, greaterThanOrEqualTo(colloquial.length - 1));
      expect(understand('escalera para subir al altillo').type, StructureType.escalera);
      expect(understand('nave para guardar el tractor').type, StructureType.nave);
      expect(understand('quiero proteger el coche del granizo en el patio').type, StructureType.marquesina);
      expect(understand('separar mi terreno del vecino con algo metálico').type, StructureType.valla);
      expect(understand('algo que se abra para que entren los coches').type, StructureType.cancela);
      expect(understand('nave para proteger la maquinaria de la lluvia').type, StructureType.nave);
      expect(understand('pérgola para cubrir los coches').type, StructureType.marquesina);
    });

    test('razonamiento de oficio: vehículos, caballos y carretillas', () {
      final u = understand('un techado para aparcar tres coches');
      expect(u.type, StructureType.marquesina);
      expect([u.spec.length, u.spec.width], [7.5, 5.0]);
      expect(u.sources['length'], DataSource.deduced);
      expect(u.notes.join(' '), contains('3 plazas'));
      final t = understand('Tejavana para guardar el tractor, unos ocho metros de largo, en Soria');
      expect(t.spec.length, 8.0); // lo del texto manda sobre la deducción
      expect(t.sources['length'], DataSource.text);
      expect(t.spec.height, greaterThanOrEqualTo(4.0));
      final c = understand('quiero hacer una cuadra para 10 caballos');
      expect(c.spec.length, 35.0);
      final p = understand('unir las dos naves por arriba para pasar con carretillas');
      expect(p.spec.width, 2.0);
      expect(p.spec.liveLoad, greaterThanOrEqualTo(5.0));
    });

    test('números con letra', () {
      expect(spellNumbers('unos ocho metros de largo y dos coches'), 'unos 8 metros de largo y 2 coches');
      expect(spellNumbers('nave a dos aguas'), 'nave a dos aguas');
      expect(spellNumbers('cuatro alturas y tres y medio metros'), '4 alturas y 3.5 metros');
    });

    test('la IA solo aporta lo que respalda el texto', () {
      const prompt = 'Tejavana para guardar el tractor en mi pueblo de Soria, con techo de chapa';
      final u = understand(prompt, llm: {
        'tipo': 'marquesina',
        'largo_m': 12, // inventado: no está en el texto
        'ubicacion': 'Soria',
        'cubierta': 'chapa grecada',
        'acabado': 'galvanizado', // inventado
      });
      expect(u.spec.length, isNot(12.0));
      expect(u.sources['finish'], isNot(DataSource.ai));
      expect(u.notes.join(' '), contains('Se descartan'));
      final burgos = understand('un techo para dar sombra en la terraza del bar', llm: {'ubicacion': 'Burgos'});
      expect(burgos.sources['city'], isNot(DataSource.ai));
    });

    test('cambios del usuario en la ficha', () {
      final u = understand('marquesina para 2 coches', overrides: {'height': 3.0, 'roofing': 'policarbonato'});
      expect(u.spec.height, 3.0);
      expect(u.spec.roofing, contains('policarbonato'));
      expect(u.sources['height'], DataSource.user);
      final f = understand('marquesina para 2 coches', forceType: StructureType.nave);
      expect(f.type, StructureType.nave);
    });

    test('la ficha se calcula para todas las tipologías', () {
      for (final (_, p) in [...colloquial, ...unseen]) {
        final u = understand(p);
        final d = designFromSpec(u.spec, p);
        expect(d.members, isNotEmpty, reason: p);
      }
    });

    test('JSON del LLM tolerante', () {
      const seed = '{"tipo": "marquesina", "';
      expect(parseLlmJson('largo_m": 5,5, "ancho_m": 5}', seed), {'tipo': 'marquesina', 'largo_m': 5.5, 'ancho_m': 5});
      expect(parseLlmJson('largo_m": 8, "ubicacion": "Sor', seed)?['largo_m'], 8);
      expect(parseLlmJson('basura sin json'), isNull);
    });

    test('regex de Qwen adaptada a Dart', () {
      final p = BpeTokenizer.dartPattern("(?i:'s|'t)|[^\\r\\n\\p{L}\\p{N}]?\\p{L}+");
      expect(p, "(?:'[sS]|'[tT])|[^\\r\\n\\p{L}\\p{N}]?\\p{L}+");
      expect(RegExp(p, unicode: true).allMatches("It'S pérgola").map((m) => m[0]), ['It', "'S", ' pérgola']);
    });
  });

  final dir = Platform.environment['HERRERO_REASON'];
  if (dir == null) return;
  final man = jsonDecode(File('$dir/manifest.json').readAsStringSync()) as Map<String, dynamic>;

  test('tokenizadores iguales que Hugging Face', () async {
    final e5 = await UnigramTokenizer.fromFile('$dir/e5s_tokenizer.json');
    for (final t in man['models']['e5s']['tokenizer_tests'] as List) {
      expect(e5.encode(t['text'] as String), (t['ids'] as List).cast<int>(), reason: t['text'] as String);
    }
    final q = await BpeTokenizer.fromFile('$dir/qwen3_tokenizer.json');
    for (final t in man['models']['qwen3']['tokenizer_tests'] as List) {
      expect(q.encode(t['text'] as String), (t['ids'] as List).cast<int>(), reason: t['text'] as String);
    }
    final ref = man['models']['qwen3']['reference'];
    expect(q.decode((ref['output_ids'] as List).cast<int>()), ref['output_text']);
  });

  test('embeddings: referencia y tipología por significado', () async {
    final ref = man['models']['e5s']['reference'];
    final v = (await runEmbedSync(EmbedRequest(dir, [ref['text'] as String])))[0];
    final head = (ref['head'] as List).cast<num>();
    for (var i = 0; i < head.length; i++) {
      expect(v[i], closeTo(head[i].toDouble(), 0.02));
    }
    final sw = Stopwatch()..start();
    final passages = intentPassages();
    final pv = await runEmbedSync(EmbedRequest(dir, [for (final p in passages) p.$2], threads: 4));
    final index = [for (var i = 0; i < passages.length; i++) (passages[i].$1, pv[i])];
    // ignore: avoid_print
    print('índice de ${passages.length} frases en ${sw.elapsedMilliseconds} ms');
    var ok = 0, okWith = 0;
    final all = [...colloquial, ...unseen];
    for (final (exp, p) in all) {
      final q = (await runEmbedSync(EmbedRequest(dir, ['query: $p'])))[0];
      final r = rankTypes(q, index);
      final u = understand(p, ranking: r);
      if (r.first.$1 == exp) ok++;
      if (u.type == exp) okWith++;
      // ignore: avoid_print
      print('${u.type == exp ? 'OK' : 'XX'} ${r.take(2).map((e) => '${e.$1.name} ${e.$2.toStringAsFixed(3)}').join(', ')} -> ${u.type.name}  $p');
    }
    // ignore: avoid_print
    print('solo embeddings: $ok/${all.length}; comprensión completa: $okWith/${all.length}');
    expect(okWith, greaterThanOrEqualTo(all.length - 3));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('LLM: ficha de la petición', () async {
    for (final p in [
      'Tejavana para guardar el tractor, unos ocho metros de largo, en mi pueblo de Soria, techo de chapa',
      'Marquesina para 2 coches de 5,5 x 5 m y 2,4 m de alto, panel sándwich, galvanizada',
    ]) {
      final type = understand(p).type;
      final r = await runLlmSync(LlmRequest(modelDir: dir, prompt: llmChat(p, type)));
      final j = parseLlmJson(r.text, llmSeed(type));
      // ignore: avoid_print
      print('${r.ids.length} tokens (prompt ${r.promptTokens} en $prefillMs ms) en ${r.time.inMilliseconds} ms: ${llmSeed(type)}${r.text}');
      expect(j, isNotNull);
      final u = understand(p, llm: j);
      // ignore: avoid_print
      print('   -> ${u.type.name} ${u.spec.length} x ${u.spec.width} x ${u.spec.height}, ${u.spec.roofing}, '
          'nieve ${u.spec.snow}; ${u.notes.join(' / ')}');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
