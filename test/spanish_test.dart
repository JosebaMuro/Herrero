import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/engine/autocomplete.dart';
import 'package:herrero/engine/model.dart';
import 'package:herrero/engine/parser.dart';
import 'package:herrero/engine/spanish.dart';
import 'package:herrero/engine/understanding.dart';
import 'package:herrero/engine/vocabulary.dart';

String fix(String s) => fixSpanish(normalize(s));

void main() {
  group('diccionario de castellano', () {
    test('corrige faltas de las palabras del oficio', () {
      expect(fix('escalra de 3 metors con varandilla'), allOf(contains('escalera'), contains('barandilla')));
      expect(fix('barandila de 10 m en la terrasa'), allOf(contains('barandilla'), contains('terraza')));
      expect(fix('canzela corredera'), contains('cancela'));
      expect(fix('balla de 20 m'), contains('valla'));
      expect(fix('reja para la bentana'), contains('ventana'));
      expect(fix('una estructura de yerro'), contains('hierro'));
      expect(fix('tejavana galbanizada'), contains('galvanizada'));
      expect(fix('entreplnta de 6x4'), contains('entreplanta'));
      expect(fix('hestanteria de 3 alturas'), contains('estanteria'));
    });
    test('quita diminutivos', () {
      expect(fix('una escalerita para el altillo'), contains('escalera'));
      expect(fix('puertecita para el jardin'), contains('puerta'));
      expect(fix('portoncito de 3 m'), contains('porton'));
    });
    test('no toca palabras corrientes', () {
      expect(fix('dos plazas de garaje'), contains('plazas'));
      expect(fix('mi cuadrilla quiere una nave'), contains('cuadrilla'));
      expect(fix('cuatro metros'), contains('cuatro'));
      expect(fix('cubierto con chapa'), contains('cubierto'));
    });
    test('avisa de lo que ha corregido', () {
      expect(spanishNote(normalize('escalra de 3 m')), contains('escalera'));
      expect(spanishNote(normalize('escalera de 3 m')), isNull);
    });
    test('entiende la petición con faltas', () {
      final s = parsePrompt('escalra de caracol de 3 metors');
      expect(s.type, StructureType.escalera);
      expect(s.variant, startsWith('caracol'));
      expect(s.height, 3);
      expect(understand('varandilla de vidrio de 6 m').spec.variant, startsWith('vidrio'));
    });
  });

  group('lo pedido manda sobre el complemento', () {
    test('escalera con barandilla es escalera', () {
      expect(parsePrompt('escalera de 3 m con barandilla').type, StructureType.escalera);
      expect(parsePrompt('escalera de caracol con pasamanos').type, StructureType.escalera);
      expect(parsePrompt('barandilla para la escalera').type, StructureType.barandilla);
      expect(parsePrompt('pasarela con barandilla de 8 m').type, StructureType.pasarela);
    });
  });

  group('formas', () {
    test('escaleras', () {
      expect(stairForm(normalize('escalera en L de 3 m')), 'en l');
      expect(stairForm(normalize('escalera de ida y vuelta')), 'en u');
      expect(stairForm(canonicalize(normalize('escalera de caracol'))), 'caracol');
      expect(stairForm(canonicalize(normalize('escalera de zanca central'))), 'zanca central');
      expect(stairForm(canonicalize(normalize('escala marinera para la cubierta'))), 'escala de gato');
      expect(stairForm(normalize('escalera de 3 m')), 'recta');
      expect(stairForm(normalize('escalera en l, variante caracol')), 'caracol');
    });
    test('barandillas', () {
      expect(railForm(normalize('barandilla de vidrio')), 'vidrio');
      expect(railForm(normalize('barandilla de cables de acero')), 'cables');
      expect(railForm(normalize('pasamanos de 4 m')), 'pasamanos a pared');
      expect(railForm(normalize('barandilla con pasamanos de 4 m')), 'barrotes');
      expect(parsePrompt('barandilla industrial de 10 m').variant, contains('rodapié'));
    });
    test('rejas', () {
      expect(isWindowGrille(canonicalize(normalize('reja para la ventana de 1 x 1,2'))), isTrue);
      expect(isWindowGrille(normalize('valla de 20 m')), isFalse);
      final s = parsePrompt('reja de ventana de 1 m de ancho y 1,2 m de alto');
      expect(s.type, StructureType.valla);
      expect(s.variant, startsWith('reja'));
      expect(s.length, 1);
      expect(s.height, 1.2);
    });
    test('la ficha cambia la forma', () {
      final u = understand('escalera de 3 m de altura', overrides: {'variant': 'caracol'});
      expect(u.spec.variant, startsWith('caracol'));
      expect(u.sources['variant'], DataSource.user);
      expect(understand('escalera en L de 3 m').sources['variant'], DataSource.text);
    });
  });

  group('autocompletar', () {
    test('completa la palabra', () {
      expect(suggest('esc').map((s) => s.label), contains('escalera de caracol'));
      expect(suggest('una barand').first.text, 'una barandilla ');
      expect(suggest('pergo').first.label, 'pérgola');
      expect(suggest('Escal').first.label, startsWith('E'));
    });
    test('completa expresiones de varias palabras', () {
      expect(suggest('escalera de car').first.text, 'escalera de caracol ');
      expect(suggest('nave a dos aguas, panel s').first.label, 'panel sándwich');
    });
    test('corrige la palabra mal escrita', () {
      expect(suggest('varandilla').first.label, 'barandilla');
      expect(suggest('escalra').first.label, 'escalera');
    });
    test('propone lo que suele seguir', () {
      final next = suggest('escalera ').map((s) => s.label).toList();
      expect(next, containsAll(['en L', 'de caracol', 'con barandilla']));
      expect(suggest('escalera de caracol de 3 m ').map((s) => s.label), isNot(contains('de caracol')));
      expect(suggest('barandilla de vidrio ').map((s) => s.label), isNot(contains('de vidrio')));
      expect(suggest(''), isEmpty);
    });
    test('respeta el texto tras el cursor', () {
      final s = suggest('escal de 3 m', cursor: 5).first;
      expect(s.text, startsWith('escalera '));
      expect(s.text, endsWith(' de 3 m'));
    });
  });
}
