// Aceleración de la IA para la app (Flutter). Toda la lógica está en ort_core.dart
// (Dart puro, compartido con la TUI); aquí solo se adapta el estado de los paquetes de
// aceleración a Listenable para la interfaz.
import 'package:flutter/foundation.dart';

import 'ort_core.dart';

export 'ort_core.dart';

/// Paquetes de aceleración para la interfaz (ListenableBuilder).
class GpuPacks extends GpuPackStore implements Listenable {
  GpuPacks._() {
    ortLog = (m) => debugPrint(m);
  }
  static final GpuPacks instance = GpuPacks._();

  static String? dirFor(String id) => GpuPackStore.dirFor(id);
  static String? cacheDirFor(String id) => GpuPackStore.cacheDirFor(id);
}
