import 'cutting.dart';
import 'model.dart';

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
      density: d.spec.grade.density,
    ));
  }
  d.pieces = pieces;
  d.stock = optimizeCuts(pieces);
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
  sb.writeln();
  sb.writeln('Pedido de barras;Barras;Metros;kg;Merma %;Retales (mm)');
  for (final st in d.stock) {
    sb.writeln(
        '${st.profile.name};${st.orderText};${(st.purchasedMm / 1000).toStringAsFixed(1)};${st.purchasedKg.toStringAsFixed(1)};${st.wastePct.toStringAsFixed(1)};${st.remnants.join(' / ')}');
  }
  sb.writeln();
  sb.writeln('Plan de corte;Barras y cortes (mm)');
  for (final st in d.stock) {
    for (final l in cutPlanLines(st)) {
      sb.writeln('${st.profile.name};$l');
    }
  }
  return sb.toString().replaceAll('.', ',').replaceAll('IPE,', 'IPE.');
}
