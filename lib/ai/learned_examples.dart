import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Correcciones del usuario guardadas como ejemplos (petición, ficha) para que
/// el LLM local aprenda de ellas: se añaden a los ejemplos de serie y se eligen
/// por parecido con cada petición nueva. Solo en este dispositivo.
class LearnedExamples {
  LearnedExamples._();
  static final instance = LearnedExamples._();

  static const max = 30;
  List<(String, String)>? _cache;

  /// Para pruebas: carpeta donde guardar en lugar de la de la app.
  Directory? dirOverride;

  Future<File> _file() async {
    final d = dirOverride ?? await getApplicationSupportDirectory();
    return File('${d.path}/learned_examples.json');
  }

  Future<List<(String, String)>> load() async {
    if (_cache != null) return _cache!;
    try {
      final f = await _file();
      if (await f.exists()) {
        final l = jsonDecode(await f.readAsString()) as List;
        _cache = [for (final e in l) ((e as Map)['peticion'] as String, e['ficha'] as String)];
        return _cache!;
      }
    } catch (_) {}
    return _cache = [];
  }

  /// Guarda (o actualiza) la corrección de una petición; los más antiguos salen.
  Future<void> add(String prompt, String ficha) async {
    final p = prompt.trim();
    if (p.isEmpty) return;
    final l = [...await load()]..removeWhere((e) => e.$1 == p);
    l.add((p, ficha));
    _cache = l.length > max ? l.sublist(l.length - max) : l;
    try {
      final f = await _file();
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode([
        for (final (q, a) in _cache!) {'peticion': q, 'ficha': a}
      ]));
    } catch (_) {}
  }

  Future<void> clear() async {
    _cache = [];
    try {
      final f = await _file();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
