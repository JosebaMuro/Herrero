import '../engine/model.dart';
import 'comprehension_core.dart';
import 'local_text.dart';
import 'model_gate.dart';
import 'model_manager.dart';

export 'comprehension_core.dart';

/// Comprensión local de la petición con los modelos instalados (app).
class Comprehension {
  Comprehension._() {
    // con poca RAM, el índice de embeddings se suelta al salir de la ficha
    ModelGate.instance.onDropCaches(() => _engine = null);
  }
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
    final engine = await _get();
    return ModelGate.instance.run(ModelTask.understand,
        () => engine.rank(prompt, threads: threads, engine: mgr.engineFor(ModelTask.understand)));
  }

  /// Lanza el LLM para leer la petición con la tipología ya decidida.
  Future<LlmJob?> read(String prompt, StructureType type, void Function(String) onPartial) async {
    final mgr = ModelManager.instance;
    if (!mgr.reasonReady) return null;
    final job = (await _get()).read(prompt, type, onPartial,
        prefix: mgr.reasoner.files.first.split('_').first,
        threads: mgr.device?.recommendedThreads ?? 4,
        engine: mgr.engineFor(ModelTask.reason));
    final release = ModelGate.instance.hold(ModelTask.reason, job.cancel);
    job.future.whenComplete(release).ignore();
    return job;
  }
}
