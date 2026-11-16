import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'plan_token.dart';

/// Lector mínimo de texto de PDF (sin dependencias): objetos, flujos
/// FlateDecode, flujos de objetos, fuentes con ToUnicode / WinAnsi /
/// Differences, XObjects de formulario y operadores de texto. Pensado para
/// planos exportados desde CAD; si el PDF no tiene texto (escaneado o con
/// textos convertidos en líneas) devuelve una lista vacía y se usa el OCR.
class PdfTextReader {
  final Uint8List bytes;
  final String _s; // latin1 1:1 con los bytes
  final Map<int, _PdfObj> _objs = {};

  PdfTextReader(this.bytes) : _s = latin1.decode(bytes, allowInvalid: true) {
    _scan();
  }

  static PlanReading read(Uint8List bytes, {int maxPages = 3}) {
    final r = PdfTextReader(bytes);
    final pages = r._pages();
    final best = <PlanToken>[];
    var bw = 0.0, bh = 0.0, off = 0.0;
    for (final p in pages.take(maxPages)) {
      try {
        final (toks, w, h) = r._pageText(p);
        for (final t in toks) {
          best.add(PlanToken(t.text, t.x0, t.y0 + off, t.x1, t.y1 + off,
              vertical: t.vertical, confidence: t.confidence));
        }
        bw = math.max(bw, w);
        bh = off + h;
        off += h;
      } catch (_) {}
    }
    return PlanReading(best, 'pdf-texto', pages: pages.length, pageWidth: bw, pageHeight: bh);
  }

  // ------------------------------------------------------------------ objetos
  void _scan() {
    final re = RegExp(r'(\d+)\s+(\d+)\s+obj\b');
    for (final m in re.allMatches(_s)) {
      final num = int.parse(m[1]!);
      final start = m.end;
      final end = _s.indexOf('endobj', start);
      if (end < 0) continue;
      var body = _s.substring(start, end);
      Uint8List? stream;
      final si = body.indexOf('stream');
      if (si >= 0 && body.lastIndexOf('endstream') > si) {
        var ds = start + si + 6;
        if (_s.codeUnitAt(ds) == 13) ds++;
        if (_s.codeUnitAt(ds) == 10) ds++;
        var de = _s.indexOf('endstream', ds);
        var e = de;
        while (e > ds && (_s.codeUnitAt(e - 1) == 10 || _s.codeUnitAt(e - 1) == 13)) {
          e--;
        }
        final dict = body.substring(0, si);
        final lenM = RegExp(r'/Length\s+(\d+)(?!\s+\d+\s+R)').firstMatch(dict);
        if (lenM != null) {
          final l = int.parse(lenM[1]!);
          if (ds + l <= bytes.length && l <= de - ds) e = ds + l;
        }
        stream = Uint8List.sublistView(bytes, ds, e);
        body = dict;
      }
      _objs[num] = _PdfObj(body, stream);
    }
    // flujos de objetos (PDF 1.5+)
    for (final o in _objs.values.toList()) {
      if (!RegExp(r'/Type\s*/ObjStm').hasMatch(o.dict) || o.stream == null) continue;
      try {
        final data = latin1.decode(_decode(o), allowInvalid: true);
        final n = int.parse(RegExp(r'/N\s+(\d+)').firstMatch(o.dict)![1]!);
        final first = int.parse(RegExp(r'/First\s+(\d+)').firstMatch(o.dict)![1]!);
        final nums = RegExp(r'\d+').allMatches(data.substring(0, first)).map((m) => int.parse(m[0]!)).toList();
        for (var i = 0; i < n && 2 * i + 1 < nums.length; i++) {
          final a = first + nums[2 * i + 1];
          final b = i + 1 < n && 2 * i + 3 < nums.length ? first + nums[2 * i + 3] : data.length;
          _objs.putIfAbsent(nums[2 * i], () => _PdfObj(data.substring(a, math.min(b, data.length)), null));
        }
      } catch (_) {}
    }
  }

  Uint8List _decode(_PdfObj o) {
    final raw = o.stream!;
    if (!o.dict.contains('FlateDecode')) return raw;
    try {
      return Uint8List.fromList(ZLibCodec().decode(raw));
    } catch (_) {
      try {
        return Uint8List.fromList(ZLibCodec(raw: true).decode(raw.length > 2 ? raw.sublist(2) : raw));
      } catch (_) {
        return Uint8List(0);
      }
    }
  }

  _PdfObj? _get(int? n) => n == null ? null : _objs[n];

  static int? _ref(String dict, String key) {
    final m = RegExp('/$key\\s+(\\d+)\\s+\\d+\\s+R').firstMatch(dict);
    return m == null ? null : int.parse(m[1]!);
  }

  /// Diccionario (en línea o por referencia) asociado a una clave.
  String? _dictOf(String dict, String key) {
    final m = RegExp('/$key\\s*(<<|\\d+\\s+\\d+\\s+R)').firstMatch(dict);
    if (m == null) return null;
    if (m[1] == '<<') return _balanced(dict, m.start + m[0]!.length - 2);
    return _get(_ref(dict, key))?.dict;
  }

  static String _balanced(String s, int at) {
    var depth = 0;
    for (var i = at; i < s.length - 1; i++) {
      if (s[i] == '<' && s[i + 1] == '<') {
        depth++;
        i++;
      } else if (s[i] == '>' && s[i + 1] == '>') {
        depth--;
        i++;
        if (depth == 0) return s.substring(at, i + 1);
      }
    }
    return s.substring(at);
  }

  /// Entradas "/Nombre n 0 R" de un diccionario.
  static Map<String, int> _entries(String? dict) {
    final out = <String, int>{};
    if (dict == null) return out;
    for (final m in RegExp(r'/([^\s/<>\[\]()]+)\s+(\d+)\s+\d+\s+R').allMatches(dict)) {
      out[m[1]!] = int.parse(m[2]!);
    }
    return out;
  }

  // ------------------------------------------------------------------ páginas
  List<_PdfObj> _pages() {
    final out = <_PdfObj>[];
    final cat = _objs.values.where((o) => RegExp(r'/Type\s*/Catalog').hasMatch(o.dict)).firstOrNull;
    final seen = <int>{};
    void walk(int? n) {
      if (n == null || !seen.add(n)) return;
      final o = _objs[n];
      if (o == null) return;
      if (RegExp(r'/Type\s*/Pages').hasMatch(o.dict)) {
        final kids = RegExp(r'/Kids\s*\[([^\]]*)\]').firstMatch(o.dict);
        if (kids != null) {
          for (final k in RegExp(r'(\d+)\s+\d+\s+R').allMatches(kids[1]!)) {
            walk(int.parse(k[1]!));
          }
        }
      } else if (RegExp(r'/Type\s*/Page\b').hasMatch(o.dict)) {
        out.add(o);
      }
    }

    if (cat != null) walk(_ref(cat.dict, 'Pages'));
    if (out.isEmpty) {
      final keys = _objs.keys.toList()..sort();
      for (final k in keys) {
        if (RegExp(r'/Type\s*/Page(?![s\w])').hasMatch(_objs[k]!.dict)) out.add(_objs[k]!);
      }
    }
    return out;
  }

  String? _inherited(_PdfObj page, String key) {
    var o = page;
    for (var i = 0; i < 20; i++) {
      final d = _dictOf(o.dict, key);
      if (d != null) return d;
      final arr = RegExp('/$key\\s*\\[([^\\]]*)\\]').firstMatch(o.dict);
      if (arr != null) return arr[1];
      final p = _get(_ref(o.dict, 'Parent'));
      if (p == null) return null;
      o = p;
    }
    return null;
  }

  (List<PlanToken>, double, double) _pageText(_PdfObj page) {
    final mb = _inherited(page, 'MediaBox');
    var box = [0.0, 0.0, 595.0, 842.0];
    if (mb != null) {
      final nums = RegExp(r'-?\d+(?:\.\d+)?').allMatches(mb).map((m) => double.parse(m[0]!)).toList();
      if (nums.length >= 4) box = nums.sublist(0, 4);
    }
    final pw = box[2] - box[0], ph = box[3] - box[1];
    final res = _inherited(page, 'Resources') ?? '';
    final runs = <_Run>[];
    final contents = <int>[];
    final arr = RegExp(r'/Contents\s*\[([^\]]*)\]').firstMatch(page.dict);
    if (arr != null) {
      contents.addAll(RegExp(r'(\d+)\s+\d+\s+R').allMatches(arr[1]!).map((m) => int.parse(m[1]!)));
    } else {
      final c = _ref(page.dict, 'Contents');
      if (c != null) contents.add(c);
    }
    final data = BytesBuilder();
    for (final c in contents) {
      final o = _objs[c];
      if (o?.stream == null) continue;
      data.add(_decode(o!));
      data.addByte(10);
    }
    _interpret(latin1.decode(data.takeBytes(), allowInvalid: true), res, _M.identity, runs, 0);
    final toks = _group(runs, box[0], box[3]);
    return (toks, pw, ph);
  }

  // ------------------------------------------------------------------ fuentes
  final Map<int, _Font> _fonts = {};

  _Font _font(int ref) => _fonts.putIfAbsent(ref, () {
        final d = _objs[ref]?.dict ?? '';
        final type0 = RegExp(r'/Subtype\s*/Type0').hasMatch(d);
        final f = _Font(type0 ? 2 : 1);
        final tu = _get(_ref(d, 'ToUnicode'));
        if (tu?.stream != null) _parseCMap(latin1.decode(_decode(tu!), allowInvalid: true), f);
        // Differences
        final enc = _dictOf(d, 'Encoding');
        final diff = RegExp(r'/Differences\s*\[([^\]]*)\]').firstMatch(enc ?? d);
        if (diff != null) {
          var code = 0;
          for (final t in RegExp(r'(\d+)|/([^\s/\[\]]+)').allMatches(diff[1]!)) {
            if (t[1] != null) {
              code = int.parse(t[1]!);
            } else {
              final u = _glyph(t[2]!);
              if (u != null) f.diff[code] = u;
              code++;
            }
          }
        }
        if (type0) {
          // anchos de la fuente CID descendiente (/DW y /W)
          final dfs = RegExp(r'/DescendantFonts\s*\[\s*(\d+)\s+\d+\s+R').firstMatch(d);
          final dfi = d.indexOf(RegExp(r'/DescendantFonts\s*\[\s*<<'));
          final cid = dfs != null
              ? _objs[int.parse(dfs[1]!)]?.dict
              : (dfi >= 0 ? _balanced(d, d.indexOf('<<', dfi)) : null);
          if (cid != null) {
            final dw = RegExp(r'/DW\s+(\d+)').firstMatch(cid);
            if (dw != null) f.defaultWidth = double.parse(dw[1]!);
            final wRef = _ref(cid, 'W');
            var wArr = wRef != null ? _objs[wRef]?.dict : RegExp(r'/W\s*\[([\s\S]*)\]').firstMatch(cid)?[1];
            // referencias a sub-listas (p. ej. "/W[0 11 0 R]")
            wArr = wArr?.replaceAllMapped(RegExp(r'(\d+)\s+\d+\s+R'), (m) => _objs[int.parse(m[1]!)]?.dict ?? '');
            if (wArr != null) {
              final toks = RegExp(r'\[|\]|-?\d+(?:\.\d+)?').allMatches(wArr).map((m) => m[0]!).toList();
              var i = 0;
              while (i < toks.length) {
                if (toks[i] == '[' || toks[i] == ']') {
                  i++;
                  continue;
                }
                final c0 = double.parse(toks[i]).toInt();
                if (i + 1 < toks.length && toks[i + 1] == '[') {
                  i += 2;
                  var c = c0;
                  while (i < toks.length && toks[i] != ']') {
                    f.widths[c++] = double.parse(toks[i++]);
                  }
                  i++;
                } else if (i + 2 < toks.length) {
                  final c1 = double.parse(toks[i + 1]).toInt();
                  final w = double.parse(toks[i + 2]);
                  for (var c = c0; c <= c1 && c - c0 < 65536; c++) {
                    f.widths[c] = w;
                  }
                  i += 3;
                } else {
                  break;
                }
              }
            }
          }
        }
        final fc = RegExp(r'/FirstChar\s+(\d+)').firstMatch(d);
        final ws = RegExp(r'/Widths\s*\[([^\]]*)\]').firstMatch(d);
        if (fc != null && ws != null) {
          final first = int.parse(fc[1]!);
          final list = RegExp(r'-?\d+(?:\.\d+)?').allMatches(ws[1]!).toList();
          for (var i = 0; i < list.length; i++) {
            f.widths[first + i] = double.parse(list[i][0]!);
          }
        }
        return f;
      });

  static void _parseCMap(String s, _Font f) {
    int hex(String h) => int.parse(h, radix: 16);
    String uni(String h) {
      final sb = StringBuffer();
      for (var i = 0; i + 4 <= h.length; i += 4) {
        sb.writeCharCode(hex(h.substring(i, i + 4)));
      }
      if (h.length == 2) sb.writeCharCode(hex(h));
      return sb.toString();
    }

    for (final b in RegExp(r'beginbfchar([\s\S]*?)endbfchar').allMatches(s)) {
      for (final m in RegExp(r'<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]*)>').allMatches(b[1]!)) {
        f.map[hex(m[1]!)] = uni(m[2]!);
        if (m[1]!.length >= 4) f.bytes = 2;
      }
    }
    for (final b in RegExp(r'beginbfrange([\s\S]*?)endbfrange').allMatches(s)) {
      for (final m in RegExp(r'<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]+)>\s*(<([0-9a-fA-F]+)>|\[([^\]]*)\])')
          .allMatches(b[1]!)) {
        final lo = hex(m[1]!), hi = hex(m[2]!);
        if (m[1]!.length >= 4) f.bytes = 2;
        if (hi - lo > 5000) continue;
        if (m[4] != null) {
          final base = hex(m[4]!.length > 4 ? m[4]!.substring(m[4]!.length - 4) : m[4]!);
          final prefix = m[4]!.length > 4 ? uni(m[4]!.substring(0, m[4]!.length - 4)) : '';
          for (var c = lo; c <= hi; c++) {
            f.map[c] = prefix + String.fromCharCode(base + c - lo);
          }
        } else {
          final items = RegExp(r'<([0-9a-fA-F]*)>').allMatches(m[5]!).toList();
          for (var c = lo; c <= hi && c - lo < items.length; c++) {
            f.map[c] = uni(items[c - lo][1]!);
          }
        }
      }
    }
  }

  static String? _glyph(String n) {
    const t = {
      'space': ' ', 'period': '.', 'comma': ',', 'hyphen': '-', 'minus': '-', 'slash': '/', 'colon': ':',
      'semicolon': ';', 'parenleft': '(', 'parenright': ')', 'plus': '+', 'equal': '=', 'percent': '%',
      'degree': '°', 'multiply': 'x', 'underscore': '_', 'quotesingle': "'", 'quotedbl': '"', 'numbersign': '#',
      'zero': '0', 'one': '1', 'two': '2', 'three': '3', 'four': '4', 'five': '5', 'six': '6', 'seven': '7',
      'eight': '8', 'nine': '9', 'aacute': 'á', 'eacute': 'é', 'iacute': 'í', 'oacute': 'ó', 'uacute': 'ú',
      'ntilde': 'ñ', 'Ntilde': 'Ñ', 'Aacute': 'Á', 'Eacute': 'É', 'Iacute': 'Í', 'Oacute': 'Ó', 'Uacute': 'Ú',
      'ordmasculine': 'º', 'ordfeminine': 'ª', 'twosuperior': '²', 'threesuperior': '³', 'Phi': 'Ø',
      'Oslash': 'Ø', 'oslash': 'ø', 'periodcentered': '·', 'asterisk': '*', 'less': '<', 'greater': '>',
    };
    if (t.containsKey(n)) return t[n];
    if (n.length == 1) return n;
    final u = RegExp(r'^uni([0-9A-Fa-f]{4})$').firstMatch(n);
    if (u != null) return String.fromCharCode(int.parse(u[1]!, radix: 16));
    return null;
  }

  // ---------------------------------------------------------- intérprete
  void _interpret(String c, String res, _M ctm0, List<_Run> runs, int depth) {
    if (depth > 6) return;
    final fontRefs = _entries(_dictOf(res, 'Font'));
    final xobjs = _entries(_dictOf(res, 'XObject'));
    var ctm = ctm0;
    final stack = <_M>[];
    var tm = _M.identity, tlm = _M.identity;
    _Font? font;
    var fs = 10.0, tl = 0.0, tc = 0.0, tw = 0.0, th = 1.0, rise = 0.0;
    final ops = <Object>[];

    void show(List<Object> parts) {
      final f = font ?? _Font(1);
      final sb = StringBuffer();
      var adv = 0.0; // en unidades de texto
      for (final p in parts) {
        if (p is num) {
          final d = -p / 1000 * fs * th;
          if (p < -180) sb.write(' ');
          adv += d;
          continue;
        }
        final bytes = p as List<int>;
        final step = f.bytes;
        for (var i = 0; i + step <= bytes.length; i += step) {
          final code = step == 2 ? (bytes[i] << 8) | bytes[i + 1] : bytes[i];
          final u = f.map[code] ?? f.diff[code] ?? (step == 1 ? _cp1252(code) : '');
          sb.write(u);
          final w0 = (f.widths[code] ?? f.defaultWidth) / 1000;
          adv += (w0 * fs + tc + (code == 32 && step == 1 ? tw : 0)) * th;
        }
      }
      final text = sb.toString();
      final trm = _M(fs * th, 0, 0, fs, 0, rise).mul(tm).mul(ctm);
      final size = math.sqrt(trm.c * trm.c + trm.d * trm.d);
      final ang = math.atan2(trm.b, trm.a);
      final scale = math.sqrt(trm.a * trm.a + trm.b * trm.b) / (fs * th == 0 ? 1 : fs * th);
      if (text.trim().isNotEmpty && size > 0.5) {
        runs.add(_Run(text, trm.e, trm.f, ang, size, adv * scale));
      }
      tm = _M(1, 0, 0, 1, adv, 0).mul(tm);
    }

    double n(int i) => (ops[i] as num).toDouble();

    for (final tok in _Lexer(c).tokens()) {
      if (tok is! _Op) {
        ops.add(tok);
        continue;
      }
      final k = ops.length;
      switch (tok.name) {
        case 'q':
          stack.add(ctm);
          break;
        case 'Q':
          if (stack.isNotEmpty) ctm = stack.removeLast();
          break;
        case 'cm':
          if (k >= 6) ctm = _M(n(k - 6), n(k - 5), n(k - 4), n(k - 3), n(k - 2), n(k - 1)).mul(ctm);
          break;
        case 'BT':
          tm = _M.identity;
          tlm = _M.identity;
          break;
        case 'Tf':
          if (k >= 2 && ops[k - 2] is _Name) {
            final ref = fontRefs[(ops[k - 2] as _Name).v];
            font = ref == null ? null : _font(ref);
            fs = n(k - 1);
          }
          break;
        case 'TL':
          if (k >= 1) tl = n(k - 1);
          break;
        case 'Tc':
          if (k >= 1) tc = n(k - 1);
          break;
        case 'Tw':
          if (k >= 1) tw = n(k - 1);
          break;
        case 'Tz':
          if (k >= 1) th = n(k - 1) / 100;
          break;
        case 'Ts':
          if (k >= 1) rise = n(k - 1);
          break;
        case 'Td':
          if (k >= 2) tm = tlm = _M(1, 0, 0, 1, n(k - 2), n(k - 1)).mul(tlm);
          break;
        case 'TD':
          if (k >= 2) {
            tl = -n(k - 1);
            tm = tlm = _M(1, 0, 0, 1, n(k - 2), n(k - 1)).mul(tlm);
          }
          break;
        case 'Tm':
          if (k >= 6) tm = tlm = _M(n(k - 6), n(k - 5), n(k - 4), n(k - 3), n(k - 2), n(k - 1));
          break;
        case 'T*':
          tm = tlm = _M(1, 0, 0, 1, 0, -tl).mul(tlm);
          break;
        case 'Tj':
          if (k >= 1 && ops[k - 1] is List<int>) show([ops[k - 1]]);
          break;
        case "'":
          tm = tlm = _M(1, 0, 0, 1, 0, -tl).mul(tlm);
          if (k >= 1 && ops[k - 1] is List<int>) show([ops[k - 1]]);
          break;
        case '"':
          tm = tlm = _M(1, 0, 0, 1, 0, -tl).mul(tlm);
          if (k >= 1 && ops[k - 1] is List<int>) show([ops[k - 1]]);
          break;
        case 'TJ':
          if (k >= 1 && ops[k - 1] is _Arr) show((ops[k - 1] as _Arr).items);
          break;
        case 'Do':
          if (k >= 1 && ops[k - 1] is _Name) {
            final ref = xobjs[(ops[k - 1] as _Name).v];
            final o = _get(ref);
            if (o != null && o.stream != null && RegExp(r'/Subtype\s*/Form').hasMatch(o.dict)) {
              var m = ctm;
              final mm = RegExp(r'/Matrix\s*\[([^\]]*)\]').firstMatch(o.dict);
              if (mm != null) {
                final v = RegExp(r'-?\d*\.?\d+(?:[eE]-?\d+)?').allMatches(mm[1]!).map((e) => double.parse(e[0]!)).toList();
                if (v.length == 6) m = _M(v[0], v[1], v[2], v[3], v[4], v[5]).mul(ctm);
              }
              final r2 = _dictOf(o.dict, 'Resources') ?? res;
              _interpret(latin1.decode(_decode(o), allowInvalid: true), r2, m, runs, depth + 1);
            }
          }
          break;
      }
      ops.clear();
    }
  }

  static String _cp1252(int c) {
    if (c < 32) return '';
    if (c < 128 || c >= 160) return String.fromCharCode(c);
    const m = {128: '€', 150: '-', 151: '-', 145: "'", 146: "'", 147: '"', 148: '"', 183: '·'};
    return m[c] ?? '';
  }

  /// Une los trozos de texto contiguos en la misma línea.
  static List<PlanToken> _group(List<_Run> runs, double ox, double top) {
    final out = <PlanToken>[];
    _Run? cur;
    var text = StringBuffer();
    var endX = 0.0, endY = 0.0;
    void flush() {
      if (cur == null) return;
      final r = cur!;
      final t = text.toString().trim();
      if (t.isNotEmpty) {
        final len = math.sqrt(math.pow(endX - r.x, 2) + math.pow(endY - r.y, 2));
        final vertical = (r.angle.abs() - math.pi / 2).abs() < 0.3;
        final x = r.x - ox, y = top - r.y;
        if (vertical) {
          final up = r.angle > 0;
          out.add(up
              ? PlanToken(t, x - r.size, y - len, x, y, vertical: true)
              : PlanToken(t, x, y, x + r.size, y + len, vertical: true));
        } else {
          out.add(PlanToken(t, x, y - r.size, x + math.max(len, r.size * t.length * 0.5), y));
        }
      }
      cur = null;
      text = StringBuffer();
    }

    for (final r in runs) {
      final c = cur;
      if (c != null && (r.angle - c.angle).abs() < 0.05 && (r.size - c.size).abs() < c.size * 0.2) {
        // distancia en la dirección del texto y perpendicular
        final dx = r.x - endX, dy = r.y - endY;
        final along = dx * math.cos(c.angle) + dy * math.sin(c.angle);
        final perp = -dx * math.sin(c.angle) + dy * math.cos(c.angle);
        if (perp.abs() < c.size * 0.3 && along > -c.size * 0.5 && along < c.size * 0.8) {
          if (along > c.size * 0.1) text.write(' ');
          text.write(r.text);
          endX = r.x + r.width * math.cos(r.angle);
          endY = r.y + r.width * math.sin(r.angle);
          continue;
        }
      }
      flush();
      cur = r;
      text.write(r.text);
      endX = r.x + r.width * math.cos(r.angle);
      endY = r.y + r.width * math.sin(r.angle);
    }
    flush();
    return out;
  }
}

class _PdfObj {
  final String dict;
  final Uint8List? stream;
  _PdfObj(this.dict, this.stream);
}

class _Font {
  int bytes;
  final Map<int, String> map = {};
  final Map<int, String> diff = {};
  final Map<int, double> widths = {};
  double defaultWidth = 550;
  _Font(this.bytes);
}

class _Run {
  final String text;
  final double x, y, angle, size, width;
  _Run(this.text, this.x, this.y, this.angle, this.size, this.width);
}

/// Matriz afín de PDF [a b c d e f].
class _M {
  final double a, b, c, d, e, f;
  const _M(this.a, this.b, this.c, this.d, this.e, this.f);
  static const identity = _M(1, 0, 0, 1, 0, 0);
  _M mul(_M o) => _M(
        a * o.a + b * o.c,
        a * o.b + b * o.d,
        c * o.a + d * o.c,
        c * o.b + d * o.d,
        e * o.a + f * o.c + o.e,
        e * o.b + f * o.d + o.f,
      );
}

class _Op {
  final String name;
  _Op(this.name);
}

class _Name {
  final String v;
  _Name(this.v);
}

class _Arr {
  final List<Object> items;
  _Arr(this.items);
}

/// Analizador léxico de flujos de contenido.
class _Lexer {
  final String s;
  int i = 0;
  _Lexer(this.s);

  static bool _ws(int c) => c == 32 || c == 10 || c == 13 || c == 9 || c == 12 || c == 0;
  static bool _delim(int c) => '()<>[]{}/%'.codeUnits.contains(c);

  Iterable<Object> tokens() sync* {
    while (true) {
      final t = _next();
      if (t == null) return;
      if (t is _Op && t.name == 'BI') {
        // imagen en línea: se salta hasta EI
        final id = s.indexOf('ID', i);
        if (id < 0) return;
        final ei = RegExp(r'\sEI(?=\s|$)').firstMatch(s.substring(id + 2));
        i = ei == null ? s.length : id + 2 + ei.end;
        continue;
      }
      yield t;
    }
  }

  Object? _next() {
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (_ws(c)) {
        i++;
      } else if (c == 37) {
        // comentario
        while (i < s.length && s.codeUnitAt(i) != 10 && s.codeUnitAt(i) != 13) {
          i++;
        }
      } else {
        break;
      }
    }
    if (i >= s.length) return null;
    final c = s.codeUnitAt(i);
    if (c == 40) return _str();
    if (c == 60) {
      if (i + 1 < s.length && s.codeUnitAt(i + 1) == 60) {
        // diccionario en línea: se salta
        final end = s.indexOf('>>', i);
        i = end < 0 ? s.length : end + 2;
        return _Name('');
      }
      final end = s.indexOf('>', i);
      final hex = s.substring(i + 1, end < 0 ? s.length : end).replaceAll(RegExp(r'\s'), '');
      i = end < 0 ? s.length : end + 1;
      final h = hex.length.isOdd ? '${hex}0' : hex;
      return [for (var k = 0; k + 2 <= h.length; k += 2) int.tryParse(h.substring(k, k + 2), radix: 16) ?? 0];
    }
    if (c == 91) {
      i++;
      final items = <Object>[];
      while (true) {
        final save = i;
        while (i < s.length && _ws(s.codeUnitAt(i))) {
          i++;
        }
        if (i >= s.length) break;
        if (s.codeUnitAt(i) == 93) {
          i++;
          break;
        }
        i = save;
        final t = _next();
        if (t == null) break;
        items.add(t);
      }
      return _Arr(items);
    }
    if (c == 93 || c == 62 || c == 123 || c == 125) {
      i++;
      return _next();
    }
    if (c == 47) {
      final st = ++i;
      while (i < s.length && !_ws(s.codeUnitAt(i)) && !_delim(s.codeUnitAt(i))) {
        i++;
      }
      return _Name(s.substring(st, i));
    }
    final st = i;
    while (i < s.length && !_ws(s.codeUnitAt(i)) && !_delim(s.codeUnitAt(i))) {
      i++;
    }
    if (i == st) {
      i++;
      return _next();
    }
    final w = s.substring(st, i);
    final v = num.tryParse(w);
    if (v != null) return v;
    return _Op(w);
  }

  List<int> _str() {
    i++; // (
    final out = <int>[];
    var depth = 1;
    while (i < s.length) {
      final c = s.codeUnitAt(i++);
      if (c == 92 && i < s.length) {
        final e = s.codeUnitAt(i++);
        switch (e) {
          case 110:
            out.add(10);
            break;
          case 114:
            out.add(13);
            break;
          case 116:
            out.add(9);
            break;
          case 98:
            out.add(8);
            break;
          case 102:
            out.add(12);
            break;
          case 10:
            break;
          case 13:
            if (i < s.length && s.codeUnitAt(i) == 10) i++;
            break;
          default:
            if (e >= 48 && e <= 55) {
              var v = e - 48;
              for (var k = 0; k < 2 && i < s.length; k++) {
                final d = s.codeUnitAt(i);
                if (d < 48 || d > 55) break;
                v = v * 8 + d - 48;
                i++;
              }
              out.add(v & 0xFF);
            } else {
              out.add(e);
            }
        }
      } else if (c == 40) {
        depth++;
        out.add(c);
      } else if (c == 41) {
        depth--;
        if (depth == 0) break;
        out.add(c);
      } else {
        out.add(c);
      }
    }
    return out;
  }
}
