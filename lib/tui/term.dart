// Terminal en modo crudo para la TUI: teclas, tamaño, colores y dibujo de pantalla
// completa. Sin dependencias: secuencias ANSI que entienden la consola de Linux (modo
// texto, sin escritorio), xterm, GNOME Terminal, Konsole, Windows Terminal…
import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ---------------------------------------------------------------------------
// Teclas
// ---------------------------------------------------------------------------

enum K {
  char,
  enter,
  backspace,
  delete,
  tab,
  shiftTab,
  esc,
  up,
  down,
  left,
  right,
  home,
  end,
  pageUp,
  pageDown,
  f1,
  f2,
  f3,
  f4,
  f5,
  ctrl, // Ctrl + letra (en [ch], en minúscula)
}

class Key {
  final K k;
  final String ch;
  const Key(this.k, [this.ch = '']);
  bool isChar(String c) => k == K.char && ch == c;
  bool isCtrl(String c) => k == K.ctrl && ch == c;
  @override
  String toString() => k == K.char ? 'char($ch)' : k == K.ctrl ? 'ctrl($ch)' : k.name;
}

const _escSeq = <String, K>{
  '[A': K.up,
  '[B': K.down,
  '[C': K.right,
  '[D': K.left,
  'OA': K.up,
  'OB': K.down,
  'OC': K.right,
  'OD': K.left,
  '[H': K.home,
  '[F': K.end,
  'OH': K.home,
  'OF': K.end,
  '[1~': K.home,
  '[7~': K.home,
  '[4~': K.end,
  '[8~': K.end,
  '[3~': K.delete,
  '[5~': K.pageUp,
  '[6~': K.pageDown,
  '[Z': K.shiftTab,
  'OP': K.f1,
  'OQ': K.f2,
  'OR': K.f3,
  'OS': K.f4,
  '[11~': K.f1,
  '[12~': K.f2,
  '[13~': K.f3,
  '[14~': K.f4,
  '[15~': K.f5,
  // consola de Linux (modo texto)
  '[[A': K.f1,
  '[[B': K.f2,
  '[[C': K.f3,
  '[[D': K.f4,
  '[[E': K.f5,
};

/// Convierte los bytes leídos del teclado en teclas.
List<Key> parseKeys(List<int> bytes) {
  final out = <Key>[];
  var i = 0;
  while (i < bytes.length) {
    final b = bytes[i];
    if (b == 0x1b) {
      if (i + 1 >= bytes.length) {
        out.add(const Key(K.esc));
        i++;
        continue;
      }
      final next = bytes[i + 1];
      if (next != 0x5b && next != 0x4f) {
        // Alt+tecla o Esc suelto seguido de otra tecla
        out.add(const Key(K.esc));
        i++;
        continue;
      }
      // secuencia CSI / SS3: hasta la letra final (o ~)
      var j = i + 2;
      if (next == 0x5b && j < bytes.length && bytes[j] == 0x5b) j++; // ESC [ [ X (consola)
      while (j < bytes.length && !(bytes[j] >= 0x40 && bytes[j] <= 0x7e && !(j == i + 2 && bytes[j] == 0x5b))) {
        j++;
      }
      final seq = String.fromCharCodes(bytes.sublist(i + 1, j < bytes.length ? j + 1 : bytes.length));
      // quitar modificadores tipo 1;5C
      final plain = seq.replaceFirst(RegExp(r'^\[1;\d'), '[');
      final k = _escSeq[seq] ?? _escSeq[plain];
      if (k != null) out.add(Key(k));
      i = j + 1;
      continue;
    }
    if (b == 0x0d || b == 0x0a) {
      out.add(const Key(K.enter));
      if (b == 0x0d && i + 1 < bytes.length && bytes[i + 1] == 0x0a) i++;
      i++;
      continue;
    }
    if (b == 0x7f || b == 0x08) {
      out.add(const Key(K.backspace));
      i++;
      continue;
    }
    if (b == 0x09) {
      out.add(const Key(K.tab));
      i++;
      continue;
    }
    if (b < 0x20) {
      out.add(Key(K.ctrl, String.fromCharCode(b + 0x60)));
      i++;
      continue;
    }
    // UTF-8: longitud por el primer byte
    final len = b >= 0xf0
        ? 4
        : b >= 0xe0
            ? 3
            : b >= 0xc0
                ? 2
                : 1;
    final end = i + len > bytes.length ? bytes.length : i + len;
    final s = utf8.decode(bytes.sublist(i, end), allowMalformed: true);
    for (final r in s.runes) {
      out.add(Key(K.char, String.fromCharCode(r)));
    }
    i = end;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Estilos y líneas
// ---------------------------------------------------------------------------

/// Estilo SGR (colores de 16, válidos en la consola de Linux).
class St {
  final String sgr;
  const St(this.sgr);
  static const none = St('');
  static const bold = St('1');
  static const dim = St('2');
  static const inverse = St('7');
  static const red = St('31');
  static const green = St('32');
  static const yellow = St('33');
  static const blue = St('34');
  static const magenta = St('35');
  static const cyan = St('36');
  static const white = St('37');
  static const boldRed = St('1;31');
  static const boldGreen = St('1;32');
  static const boldYellow = St('1;33');
  static const boldCyan = St('1;36');
  static const boldWhite = St('1;37');
  static const header = St('1;37;41'); // blanco sobre rojo (la forja)
  static const selected = St('1;30;43'); // negro sobre amarillo
  static const bar = St('30;47');
  St operator +(St o) => St([sgr, o.sgr].where((s) => s.isNotEmpty).join(';'));
}

class Seg {
  final String text;
  final St st;
  const Seg(this.text, [this.st = St.none]);
}

/// Una línea de pantalla hecha de tramos con estilo.
class Line {
  final List<Seg> segs;
  Line([List<Seg>? s]) : segs = s ?? [];
  Line.of(String text, [St st = St.none]) : segs = [Seg(text, st)];
  Line add(String text, [St st = St.none]) {
    segs.add(Seg(text, st));
    return this;
  }

  int get width => segs.fold(0, (a, s) => a + textWidth(s.text));
  String get plain => segs.map((s) => s.text).join();
}

/// Solo ASCII (consolas con fuentes muy limitadas): lo fija Terminal(ascii: true).
bool asciiMode = false;

/// Elige el carácter Unicode o su equivalente ASCII.
String g(String unicode, String ascii) => asciiMode ? ascii : unicode;

/// Columnas que ocupa un texto (sin caracteres anchos: suficiente para castellano).
int textWidth(String s) => s.runes.length;

/// Corta o rellena [s] a [w] columnas.
String fit(String s, int w, {bool right = false}) {
  final r = s.runes.toList();
  if (r.length > w) return w <= 1 ? String.fromCharCodes(r.take(w)) : '${String.fromCharCodes(r.take(w - 1))}${g('…', '~')}';
  final pad = ' ' * (w - r.length);
  return right ? '$pad$s' : '$s$pad';
}

/// Parte un texto en líneas de como mucho [w] columnas, por palabras.
List<String> wrap(String text, int w) {
  if (w < 4) return [text];
  final out = <String>[];
  for (final para in text.split('\n')) {
    var cur = '';
    for (final word in para.split(' ')) {
      if (cur.isEmpty) {
        cur = word;
      } else if (textWidth(cur) + 1 + textWidth(word) <= w) {
        cur = '$cur $word';
      } else {
        out.add(cur);
        cur = word;
      }
      while (textWidth(cur) > w) {
        final r = cur.runes.toList();
        out.add(String.fromCharCodes(r.take(w)));
        cur = String.fromCharCodes(r.skip(w));
      }
    }
    out.add(cur);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Terminal
// ---------------------------------------------------------------------------

class Terminal {
  Terminal({this.ascii = false}) {
    asciiMode = ascii;
  }

  /// Sin caracteres de dibujo ni flechas (fuentes de consola muy limitadas).
  final bool ascii;

  final _keys = StreamController<Key>.broadcast();
  StreamSubscription<List<int>>? _in;
  final List<StreamSubscription<ProcessSignal>> _sigs = [];
  void Function()? onResize;
  bool _active = false;

  Stream<Key> get keys => _keys.stream;

  int get cols {
    try {
      return stdout.terminalColumns;
    } catch (_) {
      return 80;
    }
  }

  int get rows {
    try {
      return stdout.terminalLines;
    } catch (_) {
      return 24;
    }
  }

  String get hLine => ascii ? '-' : '─';
  String get vLine => ascii ? '|' : '│';
  String get bullet => ascii ? '*' : '•';
  String get arrow => ascii ? '>' : '▸';
  String get blockFull => ascii ? '#' : '█';
  String get blockLight => ascii ? '.' : '░';

  void start() {
    if (_active) return;
    _active = true;
    stdin.echoMode = false;
    stdin.lineMode = false;
    // pantalla alternativa, sin cursor, sin ajuste de línea
    stdout.write('\x1b[?1049h\x1b[?25l\x1b[?7l\x1b[2J');
    _in = stdin.listen((b) {
      for (final k in parseKeys(b)) {
        _keys.add(k);
      }
    });
    try {
      _sigs.add(ProcessSignal.sigwinch.watch().listen((_) => onResize?.call()));
    } catch (_) {}
    for (final s in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
      try {
        _sigs.add(s.watch().listen((_) {
          stop();
          exit(130);
        }));
      } catch (_) {}
    }
  }

  void stop() {
    if (!_active) return;
    _active = false;
    _in?.cancel();
    for (final s in _sigs) {
      s.cancel();
    }
    _sigs.clear();
    stdout.write('\x1b[0m\x1b[?7h\x1b[?25h\x1b[?1049l');
    try {
      stdin.lineMode = true;
      stdin.echoMode = true;
    } catch (_) {}
  }

  /// Dibuja la pantalla entera. [cursor]: (fila, columna) donde mostrar el cursor.
  void draw(List<Line> lines, {(int, int)? cursor}) {
    final w = cols, h = rows;
    final sb = StringBuffer('\x1b[H');
    for (var y = 0; y < h; y++) {
      final line = y < lines.length ? lines[y] : Line();
      var used = 0;
      for (final s in line.segs) {
        if (used >= w) break;
        var t = s.text;
        final tw = textWidth(t);
        if (used + tw > w) t = String.fromCharCodes(t.runes.take(w - used));
        if (s.st.sgr.isNotEmpty) sb.write('\x1b[${s.st.sgr}m');
        sb.write(t);
        if (s.st.sgr.isNotEmpty) sb.write('\x1b[0m');
        used += textWidth(t);
      }
      sb.write('\x1b[0m\x1b[K');
      if (y < h - 1) sb.write('\r\n');
    }
    if (cursor != null) {
      sb.write('\x1b[${cursor.$1 + 1};${cursor.$2 + 1}H\x1b[?25h');
    } else {
      sb.write('\x1b[?25l');
    }
    stdout.write(sb.toString());
  }
}

// ---------------------------------------------------------------------------
// Campo de texto de una línea
// ---------------------------------------------------------------------------

class TextField {
  String text = '';
  int pos = 0;
  final List<String> history = [];
  int _hist = -1;

  void set(String t) {
    text = t;
    pos = t.runes.length;
  }

  /// Procesa una tecla. Devuelve true si la ha usado.
  bool handle(Key k) {
    final r = text.runes.toList();
    switch (k.k) {
      case K.char:
        r.insert(pos, k.ch.runes.first);
        pos++;
      case K.backspace:
        if (pos == 0) return true;
        r.removeAt(pos - 1);
        pos--;
      case K.delete:
        if (pos >= r.length) return true;
        r.removeAt(pos);
      case K.left:
        if (pos > 0) pos--;
        return true;
      case K.right:
        if (pos < r.length) pos++;
        return true;
      case K.home:
        pos = 0;
        return true;
      case K.end:
        pos = r.length;
        return true;
      case K.ctrl:
        if (k.ch == 'a') {
          pos = 0;
          return true;
        }
        if (k.ch == 'e') {
          pos = r.length;
          return true;
        }
        if (k.ch == 'u') {
          r.removeRange(0, pos);
          pos = 0;
        } else if (k.ch == 'k') {
          r.removeRange(pos, r.length);
        } else if (k.ch == 'w') {
          var p = pos;
          while (p > 0 && r[p - 1] == 0x20) {
            p--;
          }
          while (p > 0 && r[p - 1] != 0x20) {
            p--;
          }
          r.removeRange(p, pos);
          pos = p;
        } else {
          return false;
        }
      case K.up:
        if (history.isEmpty) return true;
        _hist = _hist < 0 ? history.length - 1 : (_hist > 0 ? _hist - 1 : 0);
        set(history[_hist]);
        return true;
      case K.down:
        if (_hist < 0) return true;
        _hist++;
        if (_hist >= history.length) {
          _hist = -1;
          set('');
        } else {
          set(history[_hist]);
        }
        return true;
      default:
        return false;
    }
    text = String.fromCharCodes(r);
    return true;
  }

  void remember() {
    final t = text.trim();
    if (t.isEmpty) return;
    history.remove(t);
    history.add(t);
    _hist = -1;
  }

  /// Ventana visible de [w] columnas y columna del cursor dentro de ella.
  (String, int) view(int w) {
    final r = text.runes.toList();
    var start = 0;
    if (pos >= w) start = pos - w + 1;
    final vis = String.fromCharCodes(r.skip(start).take(w));
    return (vis, pos - start);
  }
}
