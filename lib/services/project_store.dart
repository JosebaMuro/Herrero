import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../engine/model.dart';
import '../engine/spec_json.dart';

/// Un apunte del historial del proyecto (creado, recalculado, presupuestado…).
class HistoryEntry {
  final DateTime at;
  final String text;
  const HistoryEntry(this.at, this.text);
  Map<String, Object?> toJson() => {'at': at.toIso8601String(), 't': text};
  static HistoryEntry fromJson(Map<String, Object?> j) =>
      HistoryEntry(DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime(2000), j['t'] as String? ?? '');
}

/// Estado de un proyecto en el taller.
enum ProjectStatus { borrador, presupuestado, aceptado, fabricacion, montaje, terminado, descartado }

extension ProjectStatusLabel on ProjectStatus {
  String get label => switch (this) {
        ProjectStatus.borrador => 'Borrador',
        ProjectStatus.presupuestado => 'Presupuestado',
        ProjectStatus.aceptado => 'Aceptado',
        ProjectStatus.fabricacion => 'En fabricación',
        ProjectStatus.montaje => 'En montaje',
        ProjectStatus.terminado => 'Terminado',
        ProjectStatus.descartado => 'Descartado',
      };
}

/// Lo que aparece en la lista de proyectos. Se guarda todo junto en
/// `index.json` para listar sin abrir cada proyecto (poca memoria y rápido
/// aunque haya cientos).
class ProjectSummary {
  final String id;
  final String name;
  final String client;
  final String type; // etiqueta de la tipología
  final String dims;
  final double kg;
  final double? budget; // total sin IVA del último presupuesto
  final ProjectStatus status;
  final DateTime created;
  final DateTime updated;
  const ProjectSummary({
    required this.id,
    required this.name,
    this.client = '',
    this.type = '',
    this.dims = '',
    this.kg = 0,
    this.budget,
    this.status = ProjectStatus.borrador,
    required this.created,
    required this.updated,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'client': client,
        'type': type,
        'dims': dims,
        'kg': double.parse(kg.toStringAsFixed(1)),
        if (budget != null) 'budget': double.parse(budget!.toStringAsFixed(2)),
        'status': status.name,
        'created': created.toIso8601String(),
        'updated': updated.toIso8601String(),
      };

  static ProjectSummary fromJson(Map<String, Object?> j) => ProjectSummary(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        client: j['client'] as String? ?? '',
        type: j['type'] as String? ?? '',
        dims: j['dims'] as String? ?? '',
        kg: (j['kg'] as num?)?.toDouble() ?? 0,
        budget: (j['budget'] as num?)?.toDouble(),
        status: _status(j['status']),
        created: DateTime.tryParse(j['created'] as String? ?? '') ?? DateTime(2000),
        updated: DateTime.tryParse(j['updated'] as String? ?? '') ?? DateTime(2000),
      );
}

ProjectStatus _status(Object? v) =>
    ProjectStatus.values.firstWhere((s) => s.name == v, orElse: () => ProjectStatus.borrador);

/// Proyecto completo: ficha, texto pedido, datos del cliente, historial y
/// ajustes del presupuesto. El diseño no se guarda: se recalcula al abrir.
class ProjectRecord {
  String id;
  String name;
  String client;
  String site; // dirección o población de la obra
  String notes;
  String prompt;
  StructureSpec spec;
  String finish; // nombre del enum Finish
  ProjectStatus status;
  DateTime created;
  DateTime updated;
  List<HistoryEntry> history;

  /// Ajustes del presupuesto propios de este proyecto (precios fijados a
  /// mano por línea, margen, transporte…), en el formato de `budget.dart`.
  Map<String, Object?> budget;

  /// Total del último presupuesto calculado (para la lista).
  double? budgetTotal;

  ProjectRecord({
    required this.id,
    required this.name,
    this.client = '',
    this.site = '',
    this.notes = '',
    required this.prompt,
    required this.spec,
    this.finish = 'galvanizado',
    this.status = ProjectStatus.borrador,
    required this.created,
    required this.updated,
    List<HistoryEntry>? history,
    Map<String, Object?>? budget,
    this.budgetTotal,
  })  : history = history ?? [],
        budget = budget ?? {};

  Map<String, Object?> toJson() => {
        'v': 1,
        'id': id,
        'name': name,
        'client': client,
        'site': site,
        'notes': notes,
        'prompt': prompt,
        'spec': specToJson(spec),
        'finish': finish,
        'status': status.name,
        'created': created.toIso8601String(),
        'updated': updated.toIso8601String(),
        'history': [for (final h in history) h.toJson()],
        'budget': budget,
        if (budgetTotal != null) 'budgetTotal': budgetTotal,
      };

  static ProjectRecord fromJson(Map<String, Object?> j) => ProjectRecord(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Proyecto',
        client: j['client'] as String? ?? '',
        site: j['site'] as String? ?? '',
        notes: j['notes'] as String? ?? '',
        prompt: j['prompt'] as String? ?? '',
        spec: specFromJson(((j['spec'] as Map?) ?? const {}).cast<String, Object?>()),
        finish: j['finish'] as String? ?? 'galvanizado',
        status: _status(j['status']),
        created: DateTime.tryParse(j['created'] as String? ?? '') ?? DateTime.now(),
        updated: DateTime.tryParse(j['updated'] as String? ?? '') ?? DateTime.now(),
        history: [
          for (final h in (j['history'] as List?) ?? const []) HistoryEntry.fromJson((h as Map).cast<String, Object?>())
        ],
        budget: ((j['budget'] as Map?) ?? const {}).cast<String, Object?>(),
        budgetTotal: (j['budgetTotal'] as num?)?.toDouble(),
      );

  void log(String text) {
    history.add(HistoryEntry(DateTime.now(), text));
    // El historial no crece sin límite: se guardan los 200 últimos apuntes.
    if (history.length > 200) history = history.sublist(history.length - 200);
  }
}

String _dims(StructureSpec s) {
  String n(double v) => v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2).replaceAll('.', ',');
  final parts = [if (s.length > 0) n(s.length), if (s.width > 0) n(s.width)];
  final base = parts.join(' x ');
  return s.height > 0 ? '$base${base.isEmpty ? '' : ' · '}h ${n(s.height)} m' : (base.isEmpty ? '' : '$base m');
}

/// Almacén de proyectos en disco: una carpeta por proyecto
/// (`proyecto.json` y, si la hay, `foto.png`) y un `index.json` con el
/// resumen de todos. Escrituras atómicas (archivo temporal + rename) para no
/// perder un proyecto si la app se cierra a mitad de guardar.
class ProjectStore {
  final Directory root;
  List<ProjectSummary>? _index;

  ProjectStore(this.root) {
    if (!root.existsSync()) root.createSync(recursive: true);
  }

  static final _rnd = Random();

  static String newId() {
    final t = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final r = _rnd.nextInt(1 << 20).toRadixString(36).padLeft(4, '0');
    return '$t$r';
  }

  File get _indexFile => File('${root.path}${Platform.pathSeparator}index.json');
  Directory dirOf(String id) => Directory('${root.path}${Platform.pathSeparator}$id');
  File _recordFile(String id) => File('${dirOf(id).path}${Platform.pathSeparator}proyecto.json');
  File photoFile(String id) => File('${dirOf(id).path}${Platform.pathSeparator}foto.png');

  static void _writeAtomic(File f, List<int> bytes) {
    final tmp = File('${f.path}.tmp');
    tmp.writeAsBytesSync(bytes, flush: true);
    tmp.renameSync(f.path);
  }

  /// Lista de proyectos, del más reciente al más antiguo.
  List<ProjectSummary> list() {
    if (_index != null) return List.unmodifiable(_index!);
    var items = <ProjectSummary>[];
    var rebuilt = false;
    try {
      if (_indexFile.existsSync()) {
        final j = jsonDecode(_indexFile.readAsStringSync());
        items = [for (final e in (j as List)) ProjectSummary.fromJson((e as Map).cast<String, Object?>())];
      } else {
        rebuilt = true;
      }
    } catch (_) {
      rebuilt = true;
    }
    if (rebuilt) items = _rebuildIndex();
    // quita del índice los proyectos cuya carpeta ya no existe
    items = [for (final s in items) if (_recordFile(s.id).existsSync()) s];
    items.sort((a, b) => b.updated.compareTo(a.updated));
    _index = items;
    if (rebuilt) _saveIndex();
    return List.unmodifiable(items);
  }

  List<ProjectSummary> _rebuildIndex() {
    final out = <ProjectSummary>[];
    for (final e in root.listSync()) {
      if (e is! Directory) continue;
      final f = File('${e.path}${Platform.pathSeparator}proyecto.json');
      if (!f.existsSync()) continue;
      try {
        final r = ProjectRecord.fromJson((jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>());
        out.add(_summaryOf(r, 0));
      } catch (_) {}
    }
    return out;
  }

  void _saveIndex() {
    _writeAtomic(_indexFile, utf8.encode(jsonEncode([for (final s in _index!) s.toJson()])));
  }

  ProjectSummary _summaryOf(ProjectRecord r, double kg) => ProjectSummary(
        id: r.id,
        name: r.name,
        client: r.client,
        type: r.spec.type.label,
        dims: _dims(r.spec),
        kg: kg,
        budget: r.budgetTotal,
        status: r.status,
        created: r.created,
        updated: r.updated,
      );

  ProjectRecord? load(String id) {
    final f = _recordFile(id);
    if (!f.existsSync()) return null;
    return ProjectRecord.fromJson((jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>());
  }

  /// Guarda el proyecto y actualiza su línea del índice. [kg] es el peso del
  /// diseño calculado (para mostrarlo en la lista sin recalcular).
  void save(ProjectRecord r, {double? kg}) {
    list();
    r.updated = DateTime.now();
    final d = dirOf(r.id);
    if (!d.existsSync()) d.createSync(recursive: true);
    _writeAtomic(_recordFile(r.id), utf8.encode(jsonEncode(r.toJson())));
    final old = _index!.where((s) => s.id == r.id).firstOrNull;
    _index!.removeWhere((s) => s.id == r.id);
    _index!.insert(0, _summaryOf(r, kg ?? old?.kg ?? 0));
    _saveIndex();
  }

  /// Copia un proyecto (ficha, cliente y presupuesto) con historial nuevo.
  ProjectRecord? duplicate(String id) {
    final r = load(id);
    if (r == null) return null;
    final now = DateTime.now();
    final copy = ProjectRecord.fromJson(r.toJson())
      ..id = newId()
      ..name = '${r.name} (copia)'
      ..status = ProjectStatus.borrador
      ..created = now
      ..history = [];
    copy.log('Duplicado de «${r.name}»');
    final kg = _index?.where((s) => s.id == id).firstOrNull?.kg;
    save(copy, kg: kg);
    final ph = photoFile(id);
    if (ph.existsSync()) ph.copySync(photoFile(copy.id).path);
    return copy;
  }

  void delete(String id) {
    list();
    final d = dirOf(id);
    if (d.existsSync()) d.deleteSync(recursive: true);
    _index!.removeWhere((s) => s.id == id);
    _saveIndex();
  }

  void savePhoto(String id, Uint8List png) {
    final d = dirOf(id);
    if (!d.existsSync()) d.createSync(recursive: true);
    _writeAtomic(photoFile(id), png);
  }

  Uint8List? loadPhoto(String id) {
    final f = photoFile(id);
    return f.existsSync() ? f.readAsBytesSync() : null;
  }

  /// Busca por nombre, cliente, tipología o texto pedido (sin tildes ni mayúsculas).
  List<ProjectSummary> search(String q) {
    final n = _fold(q.trim());
    if (n.isEmpty) return list();
    return [
      for (final s in list())
        if (_fold('${s.name} ${s.client} ${s.type} ${s.dims} ${s.status.label}').contains(n)) s
    ];
  }

  /// Crea un registro nuevo a partir de un diseño recién calculado.
  static ProjectRecord fromDesign(Design d, {String? name, String finish = 'galvanizado'}) {
    final now = DateTime.now();
    final r = ProjectRecord(
      id: newId(),
      name: name ?? '${d.spec.type.label} ${_dims(d.spec)}'.trim(),
      prompt: d.prompt,
      spec: d.spec,
      finish: finish,
      created: now,
      updated: now,
    );
    r.log('Proyecto creado');
    return r;
  }
}

String _fold(String s) {
  const from = 'áéíóúüàèìòùñç';
  const to = 'aeiouuaeiounc';
  final sb = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    sb.write(i >= 0 ? to[i] : ch);
  }
  return sb.toString();
}
