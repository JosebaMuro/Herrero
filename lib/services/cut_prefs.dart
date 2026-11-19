import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../engine/cutting.dart';

const _key = 'cut_settings_v1';

/// Carga los ajustes del optimizador de corte guardados (si los hay).
Future<void> loadCutSettings() async {
  try {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw != null) CutSettings.current = CutSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    // ajustes corruptos o sin almacenamiento: se usan los de fábrica
  }
}

Future<void> saveCutSettings(CutSettings s) async {
  CutSettings.current = s;
  try {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, jsonEncode(s.toJson()));
  } catch (_) {}
}
