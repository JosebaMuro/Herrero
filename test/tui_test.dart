import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/engine/designer.dart';
import 'package:herrero/engine/understanding.dart';
import 'package:herrero/tui/support.dart';
import 'package:herrero/tui/term.dart';

void main() {
  group('teclado', () {
    test('flechas, Enter, borrar y Esc', () {
      final k = parseKeys([0x1b, 0x5b, 0x41, 0x0d, 0x7f, 0x61]);
      expect(k.map((e) => e.k).toList(), [K.up, K.enter, K.backspace, K.char]);
      expect(k.last.ch, 'a');
      expect(parseKeys([0x1b]).single.k, K.esc);
    });

    test('teclas de función de la consola de Linux y de xterm', () {
      expect(parseKeys('\x1b[[B'.codeUnits).single.k, K.f2);
      expect(parseKeys('\x1bOQ'.codeUnits).single.k, K.f2);
      expect(parseKeys('\x1b[6~'.codeUnits).single.k, K.pageDown);
      expect(parseKeys('\x1b[1;5C'.codeUnits).single.k, K.right);
    });

    test('Ctrl+G y letras con tilde (UTF-8)', () {
      expect(parseKeys([0x07]).single.isCtrl('g'), isTrue);
      final k = parseKeys('añ'.runes.expand((r) => String.fromCharCode(r).codeUnits).toList());
      expect(parseKeys([0x61, 0xc3, 0xb1]).map((e) => e.ch).join(), 'añ');
      expect(k, isNotEmpty);
    });
  });

  group('campo de texto', () {
    test('escribir, mover y borrar palabra', () {
      final f = TextField();
      for (final c in 'nave de 20'.split('')) {
        f.handle(Key(K.char, c));
      }
      expect(f.text, 'nave de 20');
      f.handle(const Key(K.ctrl, 'w'));
      expect(f.text, 'nave de ');
      f.handle(const Key(K.home));
      f.handle(const Key(K.delete));
      expect(f.text, 'ave de ');
      f.remember();
      f.set('');
      f.handle(const Key(K.up));
      expect(f.text, 'ave de'); // el historial guarda el texto sin espacios sobrantes
    });
  });

  test('ajuste de texto a la anchura', () {
    expect(fit('abcdef', 4), 'abc…');
    expect(fit('ab', 4), 'ab  ');
    expect(fit('7', 3, right: true), '  7');
    final l = wrap('uno dos tres cuatro cinco seis', 10);
    expect(l.every((s) => textWidth(s) <= 10), isTrue);
    expect(l.join(' '), 'uno dos tres cuatro cinco seis');
  });

  test('calcular, informe y exportación sin IA', () {
    const p = 'nave a dos aguas de 30 x 15 m, 6 m al alero, panel sándwich, en Vitoria';
    final u = understand(p);
    final d = designFromSpec(u.spec, p);
    final rep = plainReport(u, d);
    expect(rep, contains('HERRERO'));
    expect(rep, contains('Despiece'));
    expect(fichaRows(u), isNotEmpty);
    final md = memoriaMarkdown(d);
    expect(md, contains('## Comprobaciones'));
    expect(md, contains('técnico competente'));
    final tmp = Directory.systemTemp.createTempSync('herrero_tui');
    try {
      final files = exportDesign(d, tmp.path);
      expect(files.where((f) => f.endsWith('despiece.csv')), hasLength(1));
      expect(files.where((f) => f.endsWith('planos.dxf')), hasLength(1));
      expect(File(files.firstWhere((f) => f.endsWith('planos.dxf'))).lengthSync(), greaterThan(1000));
    } finally {
      tmp.deleteSync(recursive: true);
    }
  });

  test('carpeta de modelos compartida con la app', () {
    expect(reasonModelsDir('/x/y'), '/x/y');
    if (Platform.isLinux) expect(reasonModelsDir(), endsWith('es.herrero.herrero/models/reason'));
  });
}
