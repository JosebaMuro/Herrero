// Ayudas a la comprensión sin modelos: datos leídos por reglas, glosario,
// ejemplos por parecido, coherencia, preguntas y aprender de correcciones.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/ai/learned_examples.dart';
import 'package:herrero/engine/comprehension_aids.dart';
import 'package:herrero/engine/model.dart';
import 'package:herrero/engine/understanding.dart';

void main() {
  test('lee las cifras con su sentido', () {
    final f = readFacts('Nave de 24 m de luz por 40 de fondo, 7 m al alero y cumbrera a 9 m, pórticos cada 5 m');
    Fact? by(String l) => f.where((x) => x.label.startsWith(l)).firstOrNull;
    expect(by('luz')!.value, 24);
    expect(by('luz')!.field, 'width');
    expect(by('fondo')!.value, 40);
    expect(by('fondo')!.field, 'length');
    expect(by('altura al alero')!.value, 7);
    expect(by('altura a cumbrera')!.value, 9);
    expect(by('separación')!.value, 5);
    final c = readFacts('altillo a 3 m del suelo para 500 kg por metro cuadrado');
    expect(c.firstWhere((x) => x.field == 'liveLoad').value, 500);
    expect(c.firstWhere((x) => x.field == 'height').value, 3);
    expect(factsForLlm(f), contains('Datos ya leídos'));
    expect(factsForLlm(const []), '');
  });

  test('las cifras leídas entran en la ficha', () {
    final u = understand('Nave de 24 m de luz por 40 de fondo con 7 m al alero');
    expect(u.spec.width, 24);
    expect(u.spec.length, 40);
    expect(u.spec.height, 7);
    expect(u.sources['height'], DataSource.text);
  });

  test('glosario del oficio en el prompt', () {
    final g = glossaryFor('nave con 7 m al alero y tramex en el altillo');
    expect(g.map((e) => e.$1), containsAll(['alero', 'tramex']));
    expect(glossaryForLlm('nave con alero'), contains('alero'));
    expect(llmUser('nave de 20 m de luz'), allOf(contains('Petición: nave de 20 m de luz'), contains('luz')));
  });

  test('ejemplos elegidos por parecido', () {
    final e = pickExamples('altillo en el taller para almacén', StructureType.entreplanta);
    expect(e, hasLength(3));
    expect(e.first.$2, contains('"tipo": "entreplanta"'));
    // con una similitud externa (embeddings) manda ella
    final last = llmExamplePool.last;
    final s = pickExamples('lo que sea', StructureType.nave, similarity: (q) => q == last.$1 ? 5 : 0);
    expect(s.first, last);
  });

  test('avisos de coherencia', () {
    final u = understand('Nave de 20 m de luz por 30 de fondo, 8 m al alero y cumbrera a 6 m');
    expect(u.warnings.join(), contains('cumbrera'));
    final ok = understand('Nave de 20 m de luz por 30 de fondo, 6 m al alero y cumbrera a 8 m');
    expect(ok.warnings.where((w) => w.contains('cumbrera')), isEmpty);
    final swapped = understand('Nave de 40 m de luz por 20 de fondo');
    expect(swapped.warnings.join(), contains('cambiados'));
  });

  test('preguntas de aclaración y respuesta', () {
    final u = understand('altillo de 6 x 4 metros');
    expect(u.questions.map((q) => q.field), contains('liveLoad'));
    final q = u.questions.firstWhere((q) => q.field == 'liveLoad');
    final r = understand('altillo de 6 x 4 metros', overrides: {'liveLoad': q.options.last.$2});
    expect(r.questions.map((q) => q.field), isNot(contains('liveLoad')));
    expect(r.spec.liveLoad, closeTo(7.5, 0.01));
    expect(clarifyingQuestions(StructureType.nave, {'roofing', 'finish', 'liveLoad'}).map((q) => q.field),
        ['roofing', 'finish']);
  });

  test('las correcciones se guardan como ejemplos', () async {
    final j = fichaJson(StructureType.nave, {'length': 40.0, 'width': 24.0, 'roofing': 'panel sándwich', 'use': ''});
    expect(jsonDecode(j), {'tipo': 'nave', 'largo_m': 40, 'ancho_m': 24, 'cubierta': 'panel sándwich'});
    final tmp = await Directory.systemTemp.createTemp('learned');
    final store = LearnedExamples.instance..dirOverride = tmp;
    await store.clear();
    for (var i = 0; i < LearnedExamples.max + 2; i++) {
      await store.add('petición $i', j);
    }
    await store.add('petición 5', j); // repetida: se mueve al final
    final l = await store.load();
    expect(l, hasLength(LearnedExamples.max));
    expect(l.last.$1, 'petición 5');
    expect(File('${tmp.path}/learned_examples.json').existsSync(), isTrue);
    await tmp.delete(recursive: true);
  });
}
