import 'model.dart';
import 'profiles.dart';

/// Filas "parte → material" de un diseño, para el resumen, el PDF y la vista 3D.
List<(String, String)> materialRows(Design d) {
  final s = d.spec;
  final g = s.grade;
  final rows = <(String, String)>[
    ('Estructura', '${g.name} (${g.norm}) · ${g.description}'),
    ('Propiedades', 'fy = ${_n(g.fy)} N/mm² · E = ${_n(g.e / 1000)} GPa · ${_n(g.density)} kg/m³'),
    ('Acabado', s.finish),
  ];
  if (s.roofing.isNotEmpty) {
    rows.add((s.type.hasRoof ? 'Cubierta' : 'Suelo / peldaño', s.roofing));
  }
  if (s.cladding.isNotEmpty) rows.add(('Cerramiento', s.cladding));
  for (final e in s.parts.entries) {
    rows.add(('${e.key[0].toUpperCase()}${e.key.substring(1)} (indicado)', prefLabel(e.value)));
  }
  final weld = d.welds.isNotEmpty ? d.welds.first.process : g.weld;
  rows.add(('Soldadura', weld));
  rows.add(('Tornillería', g.bolts));
  return rows;
}

/// Texto legible de una preferencia de perfil por parte.
String prefLabel(String v) => switch (v) {
      final x when x.endsWith('*') => '${x.substring(0, x.length - 1)}e (espesor según cálculo)',
      'tubo' => 'tubo (SHS/RHS)',
      'angle' => 'angular',
      'round' => 'redondo',
      _ => v.toUpperCase(),
    };

/// Etiqueta del peso total según el material.
String metalLabel(SteelGrade g) => switch (g.kind) {
      MaterialKind.aluminium => 'Aluminio total',
      MaterialKind.stainless => 'Inox total',
      _ => 'Acero total',
    };

String _n(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 1).replaceAll('.', ',');
