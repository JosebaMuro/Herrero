import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/plans/pdf_text.dart';

void main() {
  final f = Platform.environment['HERRERO_PDF'];
  test('texto de PDF', () {
    final r = PdfTextReader.read(File(f!).readAsBytesSync());
    // ignore: avoid_print
    print('${r.tokens.length} textos, ${r.pages} páginas, ${r.pageWidth}x${r.pageHeight}');
    for (final t in r.tokens.take(80)) {
      // ignore: avoid_print
      print('  $t');
    }
    expect(r.tokens, isNotEmpty);
  }, skip: f == null);
}
