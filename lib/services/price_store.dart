import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/budget.dart';
import '../engine/pricing.dart';
import 'project_store.dart';

/// Carpeta de datos de la app (no la de documentos exportados): proyectos y
/// base de precios. En Android es la carpeta privada de la app; en Windows,
/// %APPDATA%\…\Herrero; en Linux, ~/.local/share/…
Future<Directory> dataDir() async {
  final base = await getApplicationSupportDirectory();
  final d = Directory('${base.path}${Platform.pathSeparator}datos');
  if (!d.existsSync()) d.createSync(recursive: true);
  return d;
}

ProjectStore? _projects;

/// Almacén de proyectos (uno por proceso).
Future<ProjectStore> projectStore() async =>
    _projects ??= ProjectStore(Directory('${(await dataDir()).path}${Platform.pathSeparator}proyectos'));

/// Ubicación y radio con que se buscan precios y distribuidores.
class GeoSettings {
  GeoPoint? here;
  String placeName; // «Vitoria-Gasteiz (GPS)», «Elche (escrito)»…
  double radiusKm;
  bool includeUnlocated;
  int maxAgeMonths;
  PricePolicy policy;

  GeoSettings({
    this.here,
    this.placeName = '',
    this.radiusKm = 50,
    this.includeUnlocated = true,
    this.maxAgeMonths = 12,
    this.policy = PricePolicy.mediana,
  });

  PriceQuery get query => PriceQuery(
        here: here,
        radiusKm: radiusKm,
        includeUnlocated: includeUnlocated,
        maxAgeMonths: maxAgeMonths,
        policy: policy,
      );

  Map<String, Object?> toJson() => {
        if (here != null) 'here': here!.toJson(),
        'place': placeName,
        'radius': radiusKm,
        'unlocated': includeUnlocated,
        'age': maxAgeMonths,
        'policy': policy.name,
      };

  static GeoSettings fromJson(Map<String, Object?> j) => GeoSettings(
        here: GeoPoint.fromJson(j['here']),
        placeName: j['place'] as String? ?? '',
        radiusKm: (j['radius'] as num?)?.toDouble() ?? 50,
        includeUnlocated: j['unlocated'] as bool? ?? true,
        maxAgeMonths: (j['age'] as num?)?.toInt() ?? 12,
        policy: PricePolicy.values.firstWhere((p) => p.name == j['policy'], orElse: () => PricePolicy.mediana),
      );
}

/// Base de precios, tarifas del taller y ubicación. Se carga una vez y se
/// guarda en un único JSON compacto (miles de precios ocupan unos cientos de kB).
class PriceStore {
  PriceStore._();
  static final PriceStore instance = PriceStore._();

  PriceBook? _book;
  WorkshopRates rates = WorkshopRates();
  GeoSettings geo = GeoSettings();
  bool _loaded = false;

  Future<File> _file() async => File('${(await dataDir()).path}${Platform.pathSeparator}precios.json');

  Future<PriceBook> book() async {
    await load();
    return _book!;
  }

  Future<void> load() async {
    if (_loaded) return;
    try {
      final f = await _file();
      _book = f.existsSync() ? PriceBook.fromJson((jsonDecode(await f.readAsString()) as Map).cast<String, Object?>()) : PriceBook();
    } catch (_) {
      _book = PriceBook();
    }
    try {
      final sp = await SharedPreferences.getInstance();
      final r = sp.getString('budget.rates');
      if (r != null) rates = WorkshopRates.fromJson((jsonDecode(r) as Map).cast<String, Object?>());
      final g = sp.getString('budget.geo');
      if (g != null) geo = GeoSettings.fromJson((jsonDecode(g) as Map).cast<String, Object?>());
    } catch (_) {}
    _loaded = true;
  }

  Future<void> saveBook() async {
    final f = await _file();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(_book!.toJson()), flush: true);
    await tmp.rename(f.path);
  }

  Future<void> saveSettings() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('budget.rates', jsonEncode(rates.toJson()));
      await sp.setString('budget.geo', jsonEncode(geo.toJson()));
    } catch (_) {}
  }
}
