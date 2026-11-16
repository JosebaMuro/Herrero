import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/ai/clip_tokenizer.dart';

void main() {
  final dir = Platform.environment['HERRERO_MODELS'];
  test('tokenizador CLIP = referencia', () async {
    if (dir == null) return;
    final m = jsonDecode(File('$dir/manifest.json').readAsStringSync()) as Map<String, dynamic>;
    final tt = m['tokenizer_test'] as Map<String, dynamic>;
    final tok = await ClipTokenizer.fromDir(dir);
    final ids = tok.encode(tt['prompt'] as String);
    final ref = (tt['ids'] as List).cast<int>();
    expect(ids.take(ref.length).toList(), ref);

  }, skip: dir == null ? 'sin HERRERO_MODELS' : false);
}
