import 'model.dart';
import 'profiles.dart';

/// Serialización de la ficha de la estructura para guardar proyectos.
/// Solo se guarda la ficha (y el texto pedido): el diseño completo se
/// recalcula al abrir, así el archivo ocupa unos pocos kB y no se queda
/// desfasado si mejora el motor de cálculo.
Map<String, Object?> specToJson(StructureSpec s) => {
      'type': s.type.name,
      'length': s.length,
      'width': s.width,
      'height': s.height,
      'slopePct': s.slopePct,
      if (s.bay != null) 'bay': s.bay,
      'roofing': s.roofing,
      'snow': s.snow,
      'wind': s.wind,
      'liveLoad': s.liveLoad,
      'use': s.use,
      'grade': s.grade.name,
      'railing': s.railing,
      'finish': s.finish,
      'pointLoad': s.pointLoad,
      'levels': s.levels,
      'variant': s.variant,
      'parts': s.parts,
      'cladding': s.cladding,
      'notes': s.notes,
      if (!s.fab.isEmpty || s.fab.notes.isNotEmpty) 'fab': fabToJson(s.fab),
    };

double _d(Object? v, double def) => v is num ? v.toDouble() : def;

StructureSpec specFromJson(Map<String, Object?> j) {
  final typeName = j['type'] as String? ?? 'nave';
  final type = StructureType.values.firstWhere((t) => t.name == typeName, orElse: () => StructureType.nave);
  final gradeName = j['grade'] as String? ?? s275.name;
  final grade = allGrades.firstWhere((g) => g.name == gradeName, orElse: () => s275);
  return StructureSpec(
    type: type,
    length: _d(j['length'], 0),
    width: _d(j['width'], 0),
    height: _d(j['height'], 0),
    slopePct: _d(j['slopePct'], 10),
    bay: j['bay'] is num ? (j['bay'] as num).toDouble() : null,
    roofing: j['roofing'] as String? ?? 'chapa grecada',
    snow: _d(j['snow'], 0.5),
    wind: _d(j['wind'], 0.5),
    liveLoad: _d(j['liveLoad'], 0),
    use: j['use'] as String? ?? '',
    grade: grade,
    railing: j['railing'] == true,
    finish: j['finish'] as String? ?? 'pintado (imprimación + esmalte)',
    pointLoad: _d(j['pointLoad'], 0),
    levels: (j['levels'] as num?)?.toInt() ?? 0,
    variant: j['variant'] as String? ?? '',
    parts: {for (final e in ((j['parts'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
    cladding: j['cladding'] as String? ?? '',
    notes: [for (final n in (j['notes'] as List?) ?? const []) '$n'],
    fab: j['fab'] is Map ? fabFromJson((j['fab'] as Map).cast<String, Object?>()) : const Fabrication(),
  );
}

Map<String, Object?> fabToJson(Fabrication f) => {
      'process': f.process,
      'quality': f.quality,
      'exc': f.exc,
      'ndt': f.ndt,
      'siteWelding': f.siteWelding,
      'fullPenetration': f.fullPenetration,
      'continuous': f.continuous,
      'intermittent': f.intermittent,
      'corrosivity': f.corrosivity,
      'corrosivityWhy': f.corrosivityWhy,
      'pressure': f.pressure,
      'vessel': f.vessel,
      'motorized': f.motorized,
      'notes': f.notes,
    };

Fabrication fabFromJson(Map<String, Object?> j) => Fabrication(
      process: j['process'] as String? ?? '',
      quality: j['quality'] as String? ?? '',
      exc: (j['exc'] as num?)?.toInt() ?? 0,
      ndt: [for (final n in (j['ndt'] as List?) ?? const []) '$n'],
      siteWelding: j['siteWelding'] == true,
      fullPenetration: j['fullPenetration'] == true,
      continuous: j['continuous'] == true,
      intermittent: j['intermittent'] == true,
      corrosivity: j['corrosivity'] as String? ?? '',
      corrosivityWhy: j['corrosivityWhy'] as String? ?? '',
      pressure: j['pressure'] == true,
      vessel: j['vessel'] == true,
      motorized: j['motorized'] == true,
      notes: [for (final n in (j['notes'] as List?) ?? const []) '$n'],
    );
