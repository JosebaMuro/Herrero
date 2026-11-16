import 'dart:convert';
import 'dart:io';

/// Tokenizador BPE de CLIP (compatible con el de OpenAI / HF CLIPTokenizer).
class ClipTokenizer {
  final Map<String, int> encoder;
  final Map<String, int> bpeRanks;
  final Map<int, String> byteEncoder;
  final Map<String, String> _cache = {};
  final int bos;
  final int eos;
  final int pad;

  static final _pat = RegExp(
    r"<\|startoftext\|>|<\|endoftext\|>|'s|'t|'re|'ve|'m|'ll|'d|[\p{L}]+|[\p{N}]|[^\s\p{L}\p{N}]+",
    unicode: true,
    caseSensitive: false,
  );

  ClipTokenizer._(this.encoder, this.bpeRanks, this.byteEncoder)
    : bos = encoder['<|startoftext|>'] ?? 49406,
      eos = encoder['<|endoftext|>'] ?? 49407,
      pad = encoder['!'] ?? 0;

  static Map<int, String> _bytesToUnicode() {
    final bs = <int>[
      for (var i = '!'.codeUnitAt(0); i <= '~'.codeUnitAt(0); i++) i,
      for (var i = 0xA1; i <= 0xAC; i++) i,
      for (var i = 0xAE; i <= 0xFF; i++) i,
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
    return {for (var i = 0; i < bs.length; i++) bs[i]: String.fromCharCode(cs[i])};
  }

  static ClipTokenizer fromStrings(String vocabJson, String merges) {
    final enc = (json.decode(vocabJson) as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int));
    final lines = const LineSplitter().convert(merges);
    final ranks = <String, int>{};
    // Igual que CLIP: se omite la cabecera y se toman 49152-256-2 fusiones
    final end = (49152 - 256 - 2 + 1).clamp(1, lines.length);
    for (var i = 1; i < end; i++) {
      final l = lines[i].trim();
      if (l.isEmpty) continue;
      ranks[l] = i - 1;
    }
    return ClipTokenizer._(enc, ranks, _bytesToUnicode());
  }

  static Future<ClipTokenizer> fromDir(String dir) async {
    final v = await File('$dir${Platform.pathSeparator}vocab.json').readAsString();
    final m = await File('$dir${Platform.pathSeparator}merges.txt').readAsString();
    return fromStrings(v, m);
  }

  String _bpe(String token) {
    final cached = _cache[token];
    if (cached != null) return cached;
    var word = <String>[...token.split('').sublist(0, token.length - 1), '${token[token.length - 1]}</w>'];
    if (token.length == 1) word = ['$token</w>'];
    while (word.length > 1) {
      int? best;
      var bi = -1;
      for (var i = 0; i < word.length - 1; i++) {
        final r = bpeRanks['${word[i]} ${word[i + 1]}'];
        if (r != null && (best == null || r < best)) {
          best = r;
          bi = i;
        }
      }
      if (best == null) break;
      final first = word[bi], second = word[bi + 1];
      final nw = <String>[];
      var i = 0;
      while (i < word.length) {
        if (i < word.length - 1 && word[i] == first && word[i + 1] == second) {
          nw.add(first + second);
          i += 2;
        } else {
          nw.add(word[i]);
          i++;
        }
      }
      word = nw;
    }
    final out = word.join(' ');
    _cache[token] = out;
    return out;
  }

  /// Devuelve 77 ids (BOS + texto + EOS + relleno).
  List<int> encode(String text, {int maxLength = 77}) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
    final ids = <int>[];
    for (final m in _pat.allMatches(clean)) {
      final tok = m.group(0)!;
      final mapped = utf8.encode(tok).map((b) => byteEncoder[b]!).join();
      for (final piece in _bpe(mapped).split(' ')) {
        final id = encoder[piece];
        if (id != null) ids.add(id);
      }
    }
    final body = ids.length > maxLength - 2 ? ids.sublist(0, maxLength - 2) : ids;
    final res = [bos, ...body, eos];
    while (res.length < maxLength) {
      res.add(pad);
    }
    return res;
  }
}
