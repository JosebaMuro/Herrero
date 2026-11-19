/// Optimizador de corte de perfiles (nesting 1D).
///
/// A partir del despiece calcula, por perfil, cuántas barras comerciales hay
/// que pedir, el plan de corte de cada barra y los retales que sobran.
///
/// Método: para cada longitud comercial admitida se llenan las barras una a
/// una con la combinación de piezas que más aprovecha la barra (mochila
/// exacta en mm, empezando siempre por la pieza más larga pendiente) y se
/// repite el mismo patrón mientras queden piezas iguales. Se compara con
/// «primero que quepa decreciente» (FFD) y se queda el mejor. Si se permite
/// mezclar longitudes, cada barra se cambia por la más corta en la que caben
/// sus piezas. Gana la opción con menos metros comprados.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'model.dart';
import 'profiles.dart';

/// Qué longitudes de barra comercial se admiten.
enum BarMode {
  auto('Según perfil'),
  only6('Solo 6 m'),
  only12('Solo 12 m');

  final String label;
  const BarMode(this.label);
}

/// Ajustes del optimizador (los guarda la pantalla del pedido).
class CutSettings {
  /// Ancho de corte de la sierra (mm).
  final int kerf;

  /// Despunte: lo que se descarta en cada extremo de la barra (mm).
  final int trim;

  /// Retal mínimo que se guarda para reutilizar (mm); por debajo es chatarra.
  final int minRemnant;

  final BarMode mode;

  /// Permite pedir barras de distinta longitud del mismo perfil.
  final bool mixLengths;

  const CutSettings({
    this.kerf = 3,
    this.trim = 0,
    this.minRemnant = 500,
    this.mode = BarMode.auto,
    this.mixLengths = true,
  });

  static CutSettings current = const CutSettings();

  CutSettings copyWith({int? kerf, int? trim, int? minRemnant, BarMode? mode, bool? mixLengths}) => CutSettings(
        kerf: kerf ?? this.kerf,
        trim: trim ?? this.trim,
        minRemnant: minRemnant ?? this.minRemnant,
        mode: mode ?? this.mode,
        mixLengths: mixLengths ?? this.mixLengths,
      );

  Map<String, Object> toJson() =>
      {'kerf': kerf, 'trim': trim, 'minRemnant': minRemnant, 'mode': mode.name, 'mix': mixLengths};

  factory CutSettings.fromJson(Map<String, dynamic> j) {
    int i(String k, int def) => (j[k] is num) ? (j[k] as num).round().clamp(0, 2000) : def;
    return CutSettings(
      kerf: i('kerf', 3),
      trim: i('trim', 0),
      minRemnant: i('minRemnant', 500),
      mode: BarMode.values.firstWhere((m) => m.name == j['mode'], orElse: () => BarMode.auto),
      mixLengths: j['mix'] is bool ? j['mix'] as bool : true,
    );
  }

  /// Longitudes comerciales (mm) para una familia de perfil, la habitual primero.
  List<int> lengthsFor(ProfileFamily f) {
    switch (mode) {
      case BarMode.only6:
        return const [6000];
      case BarMode.only12:
        return const [12000];
      case BarMode.auto:
        switch (f) {
          case ProfileFamily.ipe:
          case ProfileFamily.heb:
          case ProfileFamily.upn:
            return const [12000, 6000];
          case ProfileFamily.shs:
          case ProfileFamily.rhs:
          case ProfileFamily.chs:
            return const [6000, 12000];
          case ProfileFamily.angle:
          case ProfileFamily.flat:
          case ProfileFamily.round:
            return const [6000];
        }
    }
  }
}

/// Un corte dentro de una barra.
class Cut {
  final String mark;
  final int length; // mm
  /// Tramo de una pieza más larga que la barra («tramo 1/2»), si lo es.
  final String note;
  const Cut(this.mark, this.length, [this.note = '']);
  @override
  String toString() => '$mark $length${note.isEmpty ? '' : ' ($note)'}';
}

/// Una barra comercial con sus cortes.
class CutBar {
  final int length; // mm
  final List<Cut> cuts;
  final int kerf;
  final int trim;
  CutBar(this.length, this.cuts, {required this.kerf, required this.trim});

  int get usedMm => cuts.fold(0, (s, c) => s + c.length);

  /// Lo que queda al final de la barra tras despuntes y cortes.
  int get remnantMm {
    final usable = length - 2 * trim;
    // cada pieza lleva su corte salvo que la última llegue justo al final
    var r = usable - usedMm - cuts.length * kerf;
    if (r < 0) r = 0;
    return r;
  }

  /// Clave para agrupar barras con el mismo patrón de corte.
  String get signature => '$length:${(cuts.map((c) => '${c.mark}/${c.length}/${c.note}').toList()..sort()).join(',')}';
}

/// Un patrón de corte que se repite en [repeat] barras iguales.
class CutPattern {
  final CutBar bar;
  final int repeat;
  const CutPattern(this.bar, this.repeat);
}

/// Pedido y plan de corte de un perfil.
class StockPlan {
  final SteelProfile profile;
  final List<CutBar> barList;
  final CutSettings settings;

  /// Mínimo teórico de barras de la longitud principal (cota inferior).
  final int lowerBound;

  /// Piezas que superan la barra más larga y van empalmadas.
  final List<String> spliced;

  StockPlan(this.profile, this.barList, this.settings, {this.lowerBound = 0, this.spliced = const []});

  int get bars => barList.length;

  /// Longitud de barra principal (la más pedida).
  double get barLength {
    if (barList.isEmpty) return 0;
    final n = <int, int>{};
    for (final b in barList) {
      n[b.length] = (n[b.length] ?? 0) + 1;
    }
    final best = n.entries.reduce((a, b) => a.value > b.value || (a.value == b.value && a.key > b.key) ? a : b);
    return best.key.toDouble();
  }

  /// Nº de barras por longitud, la más larga primero: {12000: 3, 6000: 1}.
  Map<int, int> get barsByLength {
    final n = <int, int>{};
    for (final b in barList) {
      n[b.length] = (n[b.length] ?? 0) + 1;
    }
    final keys = n.keys.toList()..sort((a, b) => b.compareTo(a));
    return {for (final k in keys) k: n[k]!};
  }

  /// «3 × 12 m + 1 × 6 m».
  String get orderText => barsByLength.entries.map((e) => '${e.value} × ${_m(e.key)} m').join(' + ');

  double get purchasedMm => barList.fold<double>(0, (s, b) => s + b.length);
  double get usedMm => barList.fold<double>(0, (s, b) => s + b.usedMm);
  double get purchasedKg => purchasedMm / 1000 * profile.kgm;

  /// Retales aprovechables (≥ retal mínimo), de mayor a menor.
  List<int> get remnants =>
      [for (final b in barList) if (b.remnantMm >= settings.minRemnant) b.remnantMm]..sort((a, b) => b.compareTo(a));

  double get remnantMm => remnants.fold<double>(0, (s, r) => s + r);

  /// Merma total: todo lo comprado que no va a pieza (incluye retales).
  double get wastePct => purchasedMm == 0 ? 0 : 100 * (1 - usedMm / purchasedMm);

  /// Chatarra: merma sin contar los retales que se guardan.
  double get scrapPct => purchasedMm == 0 ? 0 : 100 * (purchasedMm - usedMm - remnantMm) / purchasedMm;

  /// Barras agrupadas por patrón de corte idéntico, las más repetidas primero.
  List<CutPattern> get patterns {
    final groups = <String, List<CutBar>>{};
    for (final b in barList) {
      groups.putIfAbsent(b.signature, () => []).add(b);
    }
    final out = [for (final g in groups.values) CutPattern(g.first, g.length)];
    out.sort((a, b) {
      final l = b.bar.length.compareTo(a.bar.length);
      if (l != 0) return l;
      final r = b.repeat.compareTo(a.repeat);
      if (r != 0) return r;
      return b.bar.usedMm.compareTo(a.bar.usedMm);
    });
    return out;
  }

  /// Está demostrado que no se puede hacer con menos barras.
  bool get isOptimal => bars <= lowerBound;
}

String _m(int mm) => mm % 1000 == 0 ? '${mm ~/ 1000}' : (mm / 1000).toStringAsFixed(1).replaceAll('.', ',');

/// Calcula el pedido de barras y el plan de corte para todo el despiece.
List<StockPlan> optimizeCuts(List<Piece> pieces, [CutSettings? settings]) {
  final s = settings ?? CutSettings.current;
  final byProfile = <String, List<_Item>>{};
  final profiles = <String, SteelProfile>{};
  for (final p in pieces) {
    profiles[p.profile.name] = p.profile;
    final len = p.lengthMm.round();
    if (len <= 0) continue;
    for (var i = 0; i < p.qty; i++) {
      byProfile.putIfAbsent(p.profile.name, () => []).add(_Item(p.mark, len));
    }
  }
  final plans = <StockPlan>[];
  for (final e in byProfile.entries) {
    plans.add(_planProfile(profiles[e.key]!, e.value, s));
  }
  plans.sort((a, b) => a.profile.name.compareTo(b.profile.name));
  return plans;
}

class _Item {
  final String mark;
  final int length;
  final String note;
  const _Item(this.mark, this.length, [this.note = '']);
}

StockPlan _planProfile(SteelProfile prof, List<_Item> raw, CutSettings s) {
  final lengths = s.lengthsFor(prof.family);
  final maxLen = lengths.reduce(math.max);
  final maxCap = maxLen - 2 * s.trim;

  // Piezas más largas que la barra más larga: tramos de barra entera + resto.
  final items = <_Item>[];
  final spliced = <String>{};
  for (final it in raw) {
    if (it.length <= maxCap) {
      items.add(it);
      continue;
    }
    spliced.add(it.mark);
    final n = (it.length / maxCap).ceil();
    var rest = it.length;
    for (var k = 1; k <= n; k++) {
      final l = math.min(rest, maxCap);
      items.add(_Item(it.mark, l, 'tramo $k/$n'));
      rest -= l;
    }
  }

  List<CutBar>? best;
  var bestLb = 0;
  for (final primary in lengths) {
    final cap = primary - 2 * s.trim;
    if (items.any((i) => i.length > cap)) continue;
    final lb = _lowerBound([for (final i in items) i.length + s.kerf], cap + s.kerf);
    for (final bins in [_greedyExact(items, cap, s.kerf), _ffd(items, cap, s.kerf)]) {
      var bars = [for (final b in bins) CutBar(primary, b, kerf: s.kerf, trim: s.trim)];
      if (s.mixLengths) bars = [for (final b in bars) _shrink(b, lengths, s)];
      if (best == null || _better(bars, best)) {
        best = bars;
        bestLb = lb;
      }
    }
  }
  return StockPlan(prof, best ?? const [], s, lowerBound: bestLb, spliced: spliced.toList()..sort());
}

/// Cota inferior de barras (L2 de Martello y Toth): para cada umbral α, las
/// piezas de más de media barra van cada una en la suya y las de entre α y
/// media barra solo pueden llenar los huecos que dejan las grandes en las que
/// caben; lo que no quepa pide barras nuevas.
int _lowerBound(List<int> w, int c) {
  final total = w.fold<int>(0, (a, x) => a + x);
  var best = (total / c).ceil();
  final alphas = {0, ...w.where((x) => 2 * x <= c)};
  for (final alpha in alphas) {
    var n1 = 0, n2 = 0, sum2 = 0, sum3 = 0;
    for (final x in w) {
      if (x > c - alpha) {
        n1++;
      } else if (2 * x > c) {
        n2++;
        sum2 += x;
      } else if (x >= alpha) {
        sum3 += x;
      }
    }
    final free = n2 * c - sum2;
    final l = n1 + n2 + (sum3 > free ? ((sum3 - free) / c).ceil() : 0);
    if (l > best) best = l;
  }
  return best;
}

/// Menos metros comprados; a igualdad, menos barras.
bool _better(List<CutBar> a, List<CutBar> b) {
  final la = a.fold<int>(0, (s, x) => s + x.length), lb = b.fold<int>(0, (s, x) => s + x.length);
  if (la != lb) return la < lb;
  return a.length < b.length;
}

/// Cambia la barra por la longitud comercial más corta en la que caben sus cortes.
CutBar _shrink(CutBar b, List<int> lengths, CutSettings s) {
  final need = b.cuts.fold<int>(0, (a, c) => a + c.length + s.kerf) - s.kerf;
  final fits = [for (final l in lengths) if (l - 2 * s.trim >= need) l]..sort();
  if (fits.isEmpty || fits.first >= b.length) return b;
  return CutBar(fits.first, b.cuts, kerf: s.kerf, trim: s.trim);
}

/// First-Fit Decreasing.
List<List<Cut>> _ffd(List<_Item> items, int cap, int kerf) {
  final sorted = [...items]..sort((a, b) => b.length.compareTo(a.length));
  final bins = <List<Cut>>[];
  final free = <int>[];
  final c = cap + kerf; // la última pieza no necesita corte detrás
  for (final it in sorted) {
    final w = it.length + kerf;
    var placed = false;
    for (var i = 0; i < bins.length; i++) {
      if (free[i] >= w) {
        bins[i].add(Cut(it.mark, it.length, it.note));
        free[i] -= w;
        placed = true;
        break;
      }
    }
    if (!placed) {
      bins.add([Cut(it.mark, it.length, it.note)]);
      free.add(c - w);
    }
  }
  return bins;
}

/// Llenado exacto barra a barra: la pieza más larga pendiente + la mejor
/// combinación del resto (mochila 0/1 por mm con lotes binarios), y el mismo
/// patrón se repite mientras haya piezas.
List<List<Cut>> _greedyExact(List<_Item> items, int cap, int kerf) {
  // inventario por tipo (marca, longitud, nota)
  final keys = <String, _Item>{};
  final count = <String, int>{};
  for (final it in items) {
    final k = '${it.mark}|${it.length}|${it.note}';
    keys[k] = it;
    count[k] = (count[k] ?? 0) + 1;
  }
  final c = cap + kerf;
  final bins = <List<Cut>>[];
  var guard = 0;
  while (count.values.any((n) => n > 0) && guard++ < 100000) {
    // pieza más larga pendiente
    final remaining = [for (final k in count.keys) if (count[k]! > 0) k]
      ..sort((a, b) => keys[b]!.length.compareTo(keys[a]!.length));
    final first = remaining.first;
    final pattern = <String, int>{first: 1};
    final room = c - (keys[first]!.length + kerf);
    if (room > 0) {
      // lotes binarios de cada tipo con lo que queda disponible
      final lotK = <String>[];
      final lotN = <int>[];
      final lotW = <int>[];
      for (final k in remaining) {
        var avail = count[k]! - (k == first ? 1 : 0);
        final w = keys[k]!.length + kerf;
        if (w > room) continue;
        avail = math.min(avail, room ~/ w);
        var b = 1;
        while (avail > 0) {
          final take = math.min(b, avail);
          lotK.add(k);
          lotN.add(take);
          lotW.add(take * w);
          avail -= take;
          b *= 2;
        }
      }
      if (lotK.isNotEmpty) {
        final reach = Uint8List(room + 1)..[0] = 1;
        final taken = [for (var i = 0; i < lotK.length; i++) Uint8List(room + 1)];
        var bestC = 0;
        for (var i = 0; i < lotK.length && bestC < room; i++) {
          final w = lotW[i];
          for (var x = room; x >= w; x--) {
            if (reach[x] == 0 && reach[x - w] == 1) {
              reach[x] = 1;
              taken[i][x] = 1;
              if (x > bestC) bestC = x;
            }
          }
        }
        var x = bestC;
        for (var i = lotK.length - 1; i >= 0 && x > 0; i--) {
          if (taken[i][x] == 1) {
            pattern[lotK[i]] = (pattern[lotK[i]] ?? 0) + lotN[i];
            x -= lotW[i];
          }
        }
      }
    }
    // cuántas barras iguales salen con este patrón
    var reps = 1 << 30;
    for (final e in pattern.entries) {
      reps = math.min(reps, count[e.key]! ~/ e.value);
    }
    if (reps < 1) reps = 1;
    for (var r = 0; r < reps; r++) {
      final bar = <Cut>[];
      final order = pattern.keys.toList()..sort((a, b) => keys[b]!.length.compareTo(keys[a]!.length));
      for (final k in order) {
        final it = keys[k]!;
        for (var j = 0; j < pattern[k]!; j++) {
          bar.add(Cut(it.mark, it.length, it.note));
        }
      }
      bins.add(bar);
    }
    for (final e in pattern.entries) {
      count[e.key] = count[e.key]! - e.value * reps;
    }
  }
  return bins;
}

/// Plan de corte en texto (para CSV/PDF): una línea por patrón.
List<String> cutPlanLines(StockPlan st) => [
      for (final p in st.patterns)
        '${p.repeat} × ${_m(p.bar.length)} m: ${p.bar.cuts.map((c) => '${c.mark} ${c.length}${c.note.isEmpty ? '' : ' (${c.note})'}').join(' + ')}'
            ' · sobra ${p.bar.remnantMm} mm${p.bar.remnantMm >= st.settings.minRemnant ? ' (retal)' : ''}',
    ];
