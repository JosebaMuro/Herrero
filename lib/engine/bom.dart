import 'model.dart';
import 'profiles.dart';

/// Longitud máxima de barra comercial (mm).
const double maxBar = 12000;
const double kerf = 3; // pérdida por corte de sierra (mm)

/// Agrupa las barras en marcas de despiece y calcula el aprovechamiento de
/// barras comerciales.
void buildBom(Design d) {
  final groups = <String, List<Member>>{};
  for (final m in d.members) {
    final len = (m.length * 1000).roundToDouble();
    final key = '${m.role.index}|${m.profile.name}|${len.toStringAsFixed(0)}|${m.cut}';
    groups.putIfAbsent(key, () => []).add(m);
  }
  final keys = groups.keys.toList()
    ..sort((a, b) {
      final ra = int.parse(a.split('|')[0]), rb = int.parse(b.split('|')[0]);
      if (ra != rb) return ra.compareTo(rb);
      return double.parse(b.split('|')[2]).compareTo(double.parse(a.split('|')[2]));
    });

  final counters = <MemberRole, int>{};
  final pieces = <Piece>[];
  var gi = 0;
  for (final k in keys) {
    final ms = groups[k]!;
    final role = ms.first.role;
    final n = (counters[role] ?? 0) + 1;
    counters[role] = n;
    final mark = '${role.prefix}$n';
    for (final m in ms) {
      m.mark = mark;
      m.group = gi;
    }
    gi++;
    final lenMm = double.parse(k.split('|')[2]);
    pieces.add(Piece(
      mark: mark,
      description: role.label,
      profile: ms.first.profile,
      lengthMm: lenMm,
      qty: ms.length,
      cut: ms.first.cut,
    ));
  }
  d.pieces = pieces;
  d.stock = planStock(pieces);
}

/// Optimización de corte (First-Fit Decreasing) por perfil.
List<StockPlan> planStock(List<Piece> pieces) {
  final byProfile = <String, List<double>>{};
  final profiles = <String, SteelProfile>{};
  for (final p in pieces) {
    profiles[p.profile.name] = p.profile;
    for (var i = 0; i < p.qty; i++) {
      var l = p.lengthMm;
      // piezas mayores que la barra comercial: empalme
      while (l > maxBar) {
        byProfile.putIfAbsent(p.profile.name, () => []).add(maxBar);
        l -= maxBar;
      }
      byProfile.putIfAbsent(p.profile.name, () => []).add(l);
    }
  }
  final plans = <StockPlan>[];
  for (final e in byProfile.entries) {
    final prof = profiles[e.key]!;
    final lens = [...e.value]..sort((a, b) => b.compareTo(a));
    final longest = lens.first;
    // Perfiles laminados (IPE/HEB) en barras de 12 m; tubos y angulares en 6 m
    final used = lens.fold<double>(0, (s, l) => s + l);
    StockPlan? best;
    for (final bar in [6000.0, 12000.0]) {
      if (longest > bar) continue;
      final bins = _ffd(lens, bar);
      final plan = StockPlan(prof, bar, bins.length, used, bins);
      if (best == null || plan.wastePct < best.wastePct - 0.5) best = plan;
    }
    plans.add(best!);
  }
  plans.sort((a, b) => a.profile.name.compareTo(b.profile.name));
  return plans;
}

List<List<double>> _ffd(List<double> lens, double bar) {
  final bins = <List<double>>[];
  final free = <double>[];
  for (final l in lens) {
    var placed = false;
    for (var i = 0; i < bins.length; i++) {
      if (free[i] >= l + kerf) {
        bins[i].add(l);
        free[i] -= l + kerf;
        placed = true;
        break;
      }
    }
    if (!placed) {
      bins.add([l]);
      free.add(bar - l);
    }
  }
  return bins;
}

/// Exporta el despiece a CSV (separador ;)
String bomCsv(Design d) {
  final sb = StringBuffer();
  sb.writeln('Marca;Descripción;Perfil;Longitud (mm);Cantidad;Corte;kg/ud;kg total');
  for (final p in d.pieces) {
    sb.writeln(
        '${p.mark};${p.description};${p.profile.name};${p.lengthMm.toStringAsFixed(0)};${p.qty};${p.cut};${p.unitKg.toStringAsFixed(1)};${p.totalKg.toStringAsFixed(1)}');
  }
  sb.writeln();
  sb.writeln('Marca;Chapa;Ancho (mm);Alto (mm);Espesor (mm);Cantidad;kg total;Notas');
  for (final p in d.plates) {
    sb.writeln(
        '${p.mark};${p.description};${p.w.toStringAsFixed(0)};${p.h.toStringAsFixed(0)};${p.t.toStringAsFixed(0)};${p.qty};${p.totalKg.toStringAsFixed(1)};${p.notes}');
  }
  sb.writeln();
  sb.writeln('Tornillería;Especificación;Cantidad;Uso');
  for (final b in d.bolts) {
    sb.writeln('${b.description};${b.spec};${b.qty};${b.use}');
  }
  sb.writeln();
  sb.writeln('Unión soldada;Tipo;Garganta a (mm);Long. por unión (mm);Nº uniones;Total (m);Consumible (kg)');
  for (final w in d.welds) {
    sb.writeln(
        '${w.joint};${w.type};${w.throat.toStringAsFixed(0)};${w.lengthPerJoint.toStringAsFixed(0)};${w.count};${w.totalMeters.toStringAsFixed(1)};${w.consumableKg.toStringAsFixed(2)}');
  }
  return sb.toString().replaceAll('.', ',').replaceAll('IPE,', 'IPE.');
}
