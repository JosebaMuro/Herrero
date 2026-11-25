import 'dart:convert';
import 'dart:io';

/// Tokenizador BPE a nivel de byte (estilo GPT-2) leído de un tokenizer.json
/// de Hugging Face. Cubre lo que usan SmolLM2/SmolVLM y Qwen: tokens añadidos
/// (especiales), dígitos separados uno a uno, la expresión regular de GPT-2 o
/// la del pre-tokenizador `Split` del fichero, y normalización NFC.
class BpeTokenizer {
  final Map<String, int> vocab;
  final List<String> idToToken;
  final Map<String, int> _ranks;
  final List<String> _added; // contenido de los tokens añadidos, del más largo al más corto
  final Set<int> special;
  final bool splitDigits;
  final RegExp _words;
  final bool _nfc;
  final Map<String, List<int>> _cache = {};

  /// Tokens especiales que pone el post-procesador antes y después del texto
  /// (RoBERTa: <s> ... </s>; Llama 3: <|begin_of_text|> ...).
  final List<int> prefixIds;
  final List<int> suffixIds;

  BpeTokenizer._(this.vocab, this.idToToken, this._ranks, this._added, this.special, this.splitDigits, this._words,
      this._nfc, this.prefixIds, this.suffixIds);

  static Future<BpeTokenizer> fromFile(String path) async =>
      fromJson(jsonDecode(await File(path).readAsString()) as Map<String, dynamic>);

  static BpeTokenizer fromJson(Map<String, dynamic> j) {
    final model = j['model'] as Map<String, dynamic>;
    final vocab = <String, int>{
      for (final e in (model['vocab'] as Map<String, dynamic>).entries) e.key: (e.value as num).toInt()
    };
    final ranks = <String, int>{};
    final merges = model['merges'] as List;
    for (var i = 0; i < merges.length; i++) {
      final m = merges[i];
      final pair = m is String ? m : '${(m as List)[0]} ${m[1]}';
      ranks[pair] = i;
    }
    final added = <String>[];
    final special = <int>{};
    for (final a in (j['added_tokens'] as List? ?? const [])) {
      final c = a['content'] as String;
      final id = (a['id'] as num).toInt();
      vocab[c] = id;
      added.add(c);
      if (a['special'] == true) special.add(id);
    }
    added.sort((a, b) => b.length.compareTo(a.length));
    var maxId = 0;
    for (final v in vocab.values) {
      if (v > maxId) maxId = v;
    }
    final itos = List<String>.filled(maxId + 1, '');
    vocab.forEach((k, v) => itos[v] = k);
    final pre = jsonEncode(j['pre_tokenizer'] ?? const {});
    final digits = pre.contains('"Digits"') && pre.contains('"individual_digits":true');
    RegExp? split;
    void scan(Object? n) {
      if (n is! Map) return;
      final pat = n['pattern'];
      if (n['type'] == 'Split' && pat is Map && pat['Regex'] is String) {
        split = RegExp(dartPattern(pat['Regex'] as String), unicode: true);
      }
      for (final c in (n['pretokenizers'] as List? ?? const [])) {
        scan(c);
      }
    }

    scan(j['pre_tokenizer']);
    final nfc = jsonEncode(j['normalizer'] ?? const {}).contains('"NFC"');
    final (pre_, post_) = _postProcessor(j['post_processor'], vocab);
    return BpeTokenizer._(vocab, itos, ranks, added, special, digits, split ?? _gpt2, nfc, pre_, post_);
  }

  /// Tokens que añade el post-procesador de Hugging Face a una sola frase.
  static (List<int>, List<int>) _postProcessor(Object? p, Map<String, int> vocab) {
    if (p is! Map) return (const [], const []);
    int? idOf(Object? e) => e is List && e.length == 2 ? (e[1] as num).toInt() : null;
    switch (p['type']) {
      case 'RobertaProcessing':
      case 'BertProcessing':
        final c = idOf(p['cls']), s = idOf(p['sep']);
        return ([?c], [?s]);
      case 'TemplateProcessing':
        final before = <int>[], after = <int>[];
        var seen = false;
        final specials = p['special_tokens'] as Map? ?? const {};
        for (final it in (p['single'] as List? ?? const [])) {
          if (it is! Map) continue;
          if (it.containsKey('Sequence')) {
            seen = true;
          } else if (it['SpecialToken'] is Map) {
            final name = it['SpecialToken']['id'] as String;
            final ids = (specials[name]?['ids'] as List?)?.map((e) => (e as num).toInt()) ??
                [if (vocab[name] != null) vocab[name]!];
            (seen ? after : before).addAll(ids);
          }
        }
        return (before, after);
      case 'Sequence':
        final before = <int>[], after = <int>[];
        for (final q in (p['processors'] as List? ?? const [])) {
          final (b, a) = _postProcessor(q, vocab);
          before.addAll(b);
          after.addAll(a);
        }
        return (before, after);
    }
    return (const [], const []);
  }

  /// Como [encode] y con los tokens del post-procesador (lo que da
  /// `tokenizer.encode(texto)` de Hugging Face por defecto).
  List<int> encodeWithSpecials(String text) => [...prefixIds, ...encode(text), ...suffixIds];

  /// Adapta una expresión regular de Hugging Face (Oniguruma) a Dart: los
  /// grupos `(?i:...)` sin distinguir mayúsculas pasan a clases [aA].
  static String dartPattern(String p) {
    final out = StringBuffer();
    var i = 0;
    while (i < p.length) {
      if (p.startsWith('(?i:', i)) {
        var depth = 1, k = i + 4;
        final inner = StringBuffer();
        while (k < p.length && depth > 0) {
          final c = p[k];
          if (c == '\\' && k + 1 < p.length) {
            inner.write(p.substring(k, k + 2));
            k += 2;
            continue;
          }
          if (c == '(') depth++;
          if (c == ')') depth--;
          if (depth > 0) {
            final l = c.toLowerCase(), u = c.toUpperCase();
            inner.write(l != u ? '[$l$u]' : c);
          }
          k++;
        }
        out.write('(?:$inner)');
        i = k;
      } else {
        out.write(p[i]);
        i++;
      }
    }
    return out.toString();
  }

  /// NFC para lo que se escribe en español: vocal o n + tilde, diéresis o
  /// virgulilla combinantes -> carácter compuesto.
  static String composeNfc(String s) {
    if (!s.contains(RegExp('[\u0300-\u036f]'))) return s;
    const marks = {0x301: 'aeiouAEIOUyY', 0x300: 'aeiouAEIOU', 0x308: 'aeiouAEIOUy', 0x303: 'nNaoAO', 0x327: 'cC'};
    const composed = {
      0x301: 'áéíóúÁÉÍÓÚýÝ',
      0x300: 'àèìòùÀÈÌÒÙ',
      0x308: 'äëïöüÄËÏÖÜÿ',
      0x303: 'ñÑãõÃÕ',
      0x327: 'çÇ',
    };
    final out = StringBuffer();
    final r = s.runes.toList();
    for (var i = 0; i < r.length; i++) {
      if (i + 1 < r.length && marks.containsKey(r[i + 1])) {
        final k = marks[r[i + 1]]!.indexOf(String.fromCharCode(r[i]));
        if (k >= 0) {
          out.write(composed[r[i + 1]]![k]);
          i++;
          continue;
        }
      }
      out.writeCharCode(r[i]);
    }
    return out.toString();
  }

  static final _gpt2 = RegExp(r"""'s|'t|'re|'ve|'m|'ll|'d| ?\p{L}+| ?\p{N}+| ?[^\s\p{L}\p{N}]+|\s+(?!\S)|\s+""",
      unicode: true);
  static final _digit = RegExp(r'\p{N}', unicode: true);

  /// Tabla byte -> carácter visible de GPT-2.
  static final List<String> _b2u = () {
    final bs = <int>[
      for (var i = 33; i <= 126; i++) i,
      for (var i = 161; i <= 172; i++) i,
      for (var i = 174; i <= 255; i++) i,
    ];
    final cs = [...bs];
    var n = 0;
    for (var b = 0; b < 256; b++) {
      if (!bs.contains(b)) {
        bs.add(b);
        cs.add(256 + n);
        n++;
      }
    }
    final out = List<String>.filled(256, '');
    for (var i = 0; i < bs.length; i++) {
      out[bs[i]] = String.fromCharCode(cs[i]);
    }
    return out;
  }();
  static final Map<int, int> _u2b = {for (var b = 0; b < 256; b++) _b2u[b].codeUnitAt(0): b};

  List<int> encode(String text) {
    if (_nfc) text = composeNfc(text);
    final ids = <int>[];
    var i = 0;
    while (i < text.length) {
      // siguiente token añadido (el primero en aparecer; a igualdad, el más largo)
      var best = -1;
      String? tok;
      for (final a in _added) {
        final k = text.indexOf(a, i);
        if (k >= 0 && (best < 0 || k < best)) {
          best = k;
          tok = a;
        }
      }
      final end = best < 0 ? text.length : best;
      if (end > i) _encodeText(text.substring(i, end), ids);
      if (tok == null) break;
      ids.add(vocab[tok]!);
      i = best + tok.length;
    }
    return ids;
  }

  void _encodeText(String s, List<int> ids) {
    final pieces = <String>[];
    if (splitDigits) {
      var last = 0;
      for (final m in _digit.allMatches(s)) {
        if (m.start > last) pieces.add(s.substring(last, m.start));
        pieces.add(m.group(0)!);
        last = m.end;
      }
      if (last < s.length) pieces.add(s.substring(last));
    } else {
      pieces.add(s);
    }
    for (final p in pieces) {
      for (final m in _words.allMatches(p)) {
        final w = m.group(0)!;
        final mapped = utf8.encode(w).map((b) => _b2u[b]).join();
        ids.addAll(_cache.putIfAbsent(mapped, () => _bpe(mapped)));
      }
    }
  }

  List<int> _bpe(String word) {
    if (vocab.containsKey(word)) return [vocab[word]!];
    var parts = [for (final r in word.runes) String.fromCharCode(r)];
    while (parts.length > 1) {
      var bestRank = 1 << 30, bestI = -1;
      for (var i = 0; i + 1 < parts.length; i++) {
        final r = _ranks['${parts[i]} ${parts[i + 1]}'];
        if (r != null && r < bestRank) {
          bestRank = r;
          bestI = i;
        }
      }
      if (bestI < 0) break;
      final a = parts[bestI], b = parts[bestI + 1];
      final merged = <String>[];
      for (var i = 0; i < parts.length; i++) {
        if (i + 1 < parts.length && parts[i] == a && parts[i + 1] == b) {
          merged.add(a + b);
          i++;
        } else {
          merged.add(parts[i]);
        }
      }
      parts = merged;
    }
    return [for (final p in parts) vocab[p] ?? 0];
  }

  String decode(List<int> ids, {bool skipSpecial = true}) {
    final bytes = <int>[];
    final sb = StringBuffer();
    void flush() {
      if (bytes.isEmpty) return;
      sb.write(utf8.decode(bytes, allowMalformed: true));
      bytes.clear();
    }

    for (final id in ids) {
      if (id < 0 || id >= idToToken.length) continue;
      final t = idToToken[id];
      if (special.contains(id) || _added.contains(t)) {
        if (skipSpecial && special.contains(id)) continue;
        flush();
        sb.write(t);
        continue;
      }
      for (final r in t.runes) {
        final b = _u2b[r];
        if (b != null) bytes.add(b);
      }
    }
    flush();
    return sb.toString();
  }
}
