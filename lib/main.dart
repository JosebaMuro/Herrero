import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'ai/model_gate.dart';
import 'ai/model_manager.dart';
import 'ai/accel.dart';
import 'screens/home_screen.dart';
import 'services/cut_prefs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _tuneMemory();
  await loadCutSettings();
  await ModelGate.instance.loadSettings();
  // el perfil del equipo (RAM) decide si los modelos van por turnos
  unawaited(ModelManager.instance.load().catchError((_) {}));
  // Linux: despertar la gráfica NVIDIA desde el arranque (también sin escritorio), para
  // que CUDA la encuentre lista en la primera petición a la IA.
  if (Platform.isLinux) GpuPacks.instance.load();
  runApp(const HerreroApp());
}

/// Límites de la caché de imágenes: en el móvil, menos (las vistas previas
/// de planos y fotos IA son grandes). Al avisar el sistema de poca memoria
/// se vacía junto con las demás cachés.
void _tuneMemory() {
  final cache = PaintingBinding.instance.imageCache;
  if (Platform.isAndroid || Platform.isIOS) {
    cache.maximumSizeBytes = 48 << 20;
    cache.maximumSize = 60;
  } else {
    cache.maximumSizeBytes = 160 << 20;
    cache.maximumSize = 200;
  }
  ModelGate.instance.onDropCaches(() {
    cache.clear();
    cache.clearLiveImages();
  });
  WidgetsBinding.instance.addObserver(_MemoryObserver());
}

class _MemoryObserver extends WidgetsBindingObserver {
  @override
  void didHaveMemoryPressure() => ModelGate.instance.dropCaches();
}

const forge = Color(0xFFBF360C);

class HerreroApp extends StatelessWidget {
  const HerreroApp({super.key});

  ThemeData _theme(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: forge, brightness: b);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: 'Roboto',
      visualDensity: VisualDensity.standard,
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      cardTheme: const CardThemeData(margin: EdgeInsets.symmetric(vertical: 6)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Herrero · Oficina técnica',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: const HomeScreen(),
    );
  }
}
