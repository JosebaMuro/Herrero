import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'model_manager.dart';

/// Paso del flujo de trabajo en que está el usuario. Cada paso usa unos
/// modelos y no otros.
enum WorkflowStep { inicio, comprension, proyecto, planos, foto, facturas, presupuesto }

/// Modelos que necesita cada paso.
const stepTasks = <WorkflowStep, Set<ModelTask>>{
  WorkflowStep.inicio: {},
  WorkflowStep.comprension: {ModelTask.understand, ModelTask.reason},
  WorkflowStep.proyecto: {},
  WorkflowStep.planos: {ModelTask.plans, ModelTask.sketch},
  WorkflowStep.foto: {ModelTask.photo},
  WorkflowStep.facturas: {ModelTask.plans},
  WorkflowStep.presupuesto: {},
};

/// Modo de ahorro de memoria (ajuste de la app).
enum MemoryMode { automatico, siempre, nunca }

extension MemoryModeLabel on MemoryMode {
  String get label => switch (this) {
        MemoryMode.automatico => 'Automático (según la RAM)',
        MemoryMode.siempre => 'Siempre: un modelo cada vez',
        MemoryMode.nunca => 'Nunca: varios modelos a la vez',
      };
}

/// Por debajo de esta RAM se cargan los modelos por turnos.
const lowRamGb = 6.0;

/// Decide si hay que ahorrar memoria (función pura, para las pruebas).
bool needsMemorySaving(MemoryMode mode, double ramGb) => switch (mode) {
      MemoryMode.siempre => true,
      MemoryMode.nunca => false,
      MemoryMode.automatico => ramGb > 0 && ramGb < lowRamGb,
    };

class _Ticket {
  final ModelTask task;
  final void Function() cancel;
  _Ticket(this.task, this.cancel);
}

/// Turnos de carga de modelos.
///
/// Los modelos se abren en un isolate y se liberan al terminar cada
/// trabajo, pero algunos trabajos siguen en segundo plano (el razonamiento
/// rellena la ficha mientras el usuario sigue; la foto IA tarda). Con poca
/// RAM, dos a la vez pueden agotar la memoria y Android cierra la app. En
/// modo ahorro:
///  * al cambiar de paso se cancelan los trabajos de modelos que el paso
///    nuevo no usa y se sueltan las cachés;
///  * solo hay un modelo cargado cada vez: antes de abrir otro se cancela el
///    trabajo de fondo anterior y los trabajos cortos (OCR, embeddings) van
///    en fila.
class ModelGate {
  ModelGate._();
  static final ModelGate instance = ModelGate._();

  MemoryMode mode = MemoryMode.automatico;
  WorkflowStep step = WorkflowStep.inicio;
  final _active = <_Ticket>[];
  Future<void> _queue = Future<void>.value();

  /// Funciones que sueltan cachés en memoria (índice de embeddings, imágenes).
  final _dropCaches = <void Function()>[];

  /// RAM que se usa para decidir (0 = desconocida). Se puede fijar en pruebas.
  double? ramOverride;

  double get ramGb => ramOverride ?? ModelManager.instance.device?.ramGb ?? 0;
  bool get saving => needsMemorySaving(mode, ramGb);

  /// Trabajos activos (para enseñarlo y para las pruebas).
  List<ModelTask> get activeTasks => [for (final t in _active) t.task];

  void onDropCaches(void Function() f) => _dropCaches.add(f);

  Future<void> loadSettings() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final m = sp.getString('ai.memoryMode');
      mode = MemoryMode.values.firstWhere((e) => e.name == m, orElse: () => MemoryMode.automatico);
    } catch (_) {}
  }

  Future<void> setMode(MemoryMode m) async {
    mode = m;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('ai.memoryMode', m.name);
    } catch (_) {}
  }

  /// El usuario entra en un paso del flujo.
  void enter(WorkflowStep s) {
    step = s;
    if (!saving) return;
    final keep = stepTasks[s] ?? const {};
    for (final t in [..._active]) {
      if (!keep.contains(t.task)) {
        _active.remove(t);
        t.cancel();
      }
    }
    dropCaches();
  }

  /// Suelta las cachés en memoria (al cambiar de paso con poca RAM o
  /// cuando el sistema avisa de que falta memoria).
  void dropCaches() {
    for (final f in _dropCaches) {
      try {
        f();
      } catch (_) {}
    }
  }

  /// Antes de abrir un modelo para [task]: en modo ahorro cancela los
  /// trabajos de fondo de otros modelos.
  void _makeRoom(ModelTask task) {
    if (!saving) return;
    for (final t in [..._active]) {
      if (t.task != task) {
        _active.remove(t);
        t.cancel();
      }
    }
  }

  /// Registra un trabajo largo cancelable (LLM, visión, foto). Devuelve la
  /// función que hay que llamar cuando termine.
  void Function() hold(ModelTask task, void Function() cancel) {
    _makeRoom(task);
    final t = _Ticket(task, cancel);
    _active.add(t);
    return () => _active.remove(t);
  }

  /// Ejecuta un trabajo corto con modelo (OCR, embeddings). En modo ahorro
  /// van de uno en uno.
  Future<T> run<T>(ModelTask task, Future<T> Function() job) {
    if (!saving) return job();
    _makeRoom(task);
    final c = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        c.complete(await job());
      } catch (e, st) {
        c.completeError(e, st);
      }
    });
    return c.future;
  }
}
