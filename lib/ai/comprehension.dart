import '../engine/model.dart';
import 'comprehension_core.dart';
import 'local_text.dart';
import 'model_manager.dart';

export 'comprehension_core.dart';

/// Comprensión local de la petición con los modelos instalados (app).
class Comprehension {
  Comprehension._();
  static final instance = Comprehension._();

  ComprehensionEngine? _engine;

  Future<ComprehensionEngine> _get() async {
    final dir = (await ModelManager.instance.dir('reason')).path;
    if (_engine?.dir != dir) _engine = ComprehensionEngine(dir);
    return _engine!;
  }

  /// Tipologías ordenadas por parecido de significado (vacío si no hay modelo).
  Future<List<(StructureType, double)>> rank(String prompt) async {
    final mgr = ModelManager.instance;
    if (!mgr.embedReady) return const [];
    final threads = (mgr.device?.recommendedThreads ?? 4).clamp(1, 4);
    return (await _get()).rank(prompt, threads: threads, engine: mgr.lightEngine);
  }

  /// Lanza el LLM para leer la petición con la tipología ya decidida.
  Future<LlmJob?> read(String prompt, StructureType type, void Function(String) onPartial) async {
    final mgr = ModelManager.instance;
    if (!mgr.reasonReady) return null;
    return (await _get()).read(prompt, type, onPartial,
        prefix: mgr.reasoner.files.first.split('_').first,
        threads: mgr.device?.recommendedThreads ?? 4,
        engine: mgr.engine);
  }
}
