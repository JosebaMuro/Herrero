import 'dart:async';

import '../engine/comprehension_aids.dart';
import '../engine/model.dart';
import 'comprehension_core.dart';
import 'learned_examples.dart';
import 'local_text.dart';
import 'model_gate.dart';
import 'model_manager.dart';
import 'remote_settings.dart';

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
    final mgr = ModelManager.instance;
    final dir = (await mgr.dir(mgr.embedder.subdir)).path;
    final reasonDir = (await mgr.dir(mgr.reasoner.subdir)).path;
    final spec = embedSpecFor(mgr.embedder.files.first.split('_').first);
    final e = _engine;
    if (e == null || e.dir != dir || e.reasonDir != reasonDir || e.embed.prefix != spec.prefix) {
      _engine = ComprehensionEngine(dir, reasonDir: reasonDir, embed: spec);
    }
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

  /// Hay con qué razonar la ficha: el endpoint de Ajustes o el LLM local.
  Future<bool> canReason() async =>
      (await RemoteLlmStore.instance.load()).usable || ModelManager.instance.reasonReady;

  /// Lanza el LLM para leer la petición con la tipología ya decidida: el
  /// endpoint (FreeLLMAPI…) si está activado en Ajustes y, si falla, el local.
  Future<LlmJob?> read(String prompt, StructureType type, void Function(String) onPartial) async {
    final remote = await RemoteLlmStore.instance.load();
    if (remote.usable) return _readRemote(remote, prompt, type, onPartial);
    return _readLocal(prompt, type, onPartial);
  }

  Future<LlmJob> _readRemote(
      RemoteLlmSettings s, String prompt, StructureType type, void Function(String) onPartial) async {
    final pickEngine = ModelManager.instance.embedReady ? await _get() : null;
    final examples = pickEngine == null
        ? pickExamples(prompt, type, pool: [...llmExamplePool, ...await LearnedExamples.instance.load()])
        : await _examples(pickEngine, prompt, type);
    final completer = Completer<LlmResult>();
    var cancelled = false;
    LlmJob? current = startRemoteLlm(s, prompt, type, onPartial, examples: examples);
    current.future.then((r) {
      if (!completer.isCompleted) completer.complete(r);
    }, onError: (Object e) async {
      if (completer.isCompleted || cancelled) return;
      final local = s.fallbackLocal && ModelManager.instance.reasonReady
          ? await _readLocal(prompt, type, onPartial)
          : null;
      if (local == null || cancelled) {
        if (!completer.isCompleted) completer.completeError(e);
        return;
      }
      current = local;
      local.future.then((r) {
        if (!completer.isCompleted) completer.complete(r);
      }, onError: (Object e2) {
        if (!completer.isCompleted) completer.completeError(Exception('$e · local: $e2'));
      });
    });
    return LlmJob(completer.future, () {
      cancelled = true;
      current?.cancel();
      if (!completer.isCompleted) completer.completeError(Exception('Cancelado'));
    });
  }

  Future<LlmJob?> _readLocal(String prompt, StructureType type, void Function(String) onPartial) async {
    final mgr = ModelManager.instance;
    if (!mgr.reasonReady) return null;
    final engine = await _get();
    final prefix = mgr.reasoner.files.first.split('_').first;
    // el modelo que razona lee más despacio: con dos ejemplos le basta
    final examples = await _examples(engine, prompt, type, k: llmThinks(prefix) ? 2 : 3);
    final job = engine.read(prompt, type, onPartial,
        prefix: prefix,
        threads: mgr.device?.recommendedThreads ?? 4,
        engine: mgr.engineFor(ModelTask.reason),
        examples: examples);
    final release = ModelGate.instance.hold(ModelTask.reason, job.cancel);
    job.future.whenComplete(release).ignore();
    return job;
  }

  /// Ejemplos para el LLM: los de serie más las correcciones del usuario,
  /// elegidos por parecido de significado (o por palabras sin embeddings).
  Future<List<(String, String)>> _examples(ComprehensionEngine engine, String prompt, StructureType type,
      {int k = 3}) async {
    final pool = [...llmExamplePool, ...await LearnedExamples.instance.load()];
    final mgr = ModelManager.instance;
    if (mgr.embedReady) {
      try {
        return await ModelGate.instance.run(
            ModelTask.understand,
            () => engine.examplesFor(prompt, type, pool, k: k,
                threads: (mgr.device?.recommendedThreads ?? 4).clamp(1, 4), engine: mgr.engineFor(ModelTask.understand)));
      } catch (_) {}
    }
    return pickExamples(prompt, type, pool: pool, k: k);
  }
}
