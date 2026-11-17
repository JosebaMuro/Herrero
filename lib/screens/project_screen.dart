import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:printing/printing.dart';

import '../engine/designer.dart';
import '../engine/materials.dart';
import '../engine/model.dart';
import '../engine/parser.dart';
import '../engine/profiles.dart';
import '../services/export.dart';
import 'package:flutter/gestures.dart';
import '../views/iso_view.dart';
import '../cad/cad.dart';
import '../cad/cad_painter.dart';
import '../cad/sheets.dart';
import '../views/render_view.dart';
import '../views/zrender_view.dart';
import 'ai_photo_screen.dart';
import 'models_screen.dart';

String _n(double v, [int d = 1]) => v.toStringAsFixed(d).replaceAll('.', ',');

class ProjectScreen extends StatefulWidget {
  final Design design;
  const ProjectScreen({super.key, required this.design});
  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> with SingleTickerProviderStateMixin {
  late Design d = widget.design;
  late final TabController _tabs = TabController(length: 7, vsync: this);
  int? _highlight;
  late Finish _finish = finishFromSpec(d.spec.finish);
  bool _exporting = false;
  Uint8List? _aiPhoto;

  void _recalc(StructureSpec s) {
    setState(() {
      d = designFromSpec(s, d.prompt);
      _highlight = null;
      _aiPhoto = null;
    });
  }

  Future<void> _exportPdf() async {
    setState(() => _exporting = true);
    try {
      final path = await exportPdf(d, finish: _finish, aiPhoto: _aiPhoto);
      _toast('PDF guardado en $path');
    } catch (e) {
      _toast('Error al exportar: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _printPdf() async {
    await Printing.layoutPdf(onLayout: (_) => buildPdf(d, finish: _finish, aiPhoto: _aiPhoto), name: 'Herrero');
  }

  Future<void> _exportCsv() async {
    try {
      final path = await exportCsv(d);
      _toast('Despiece CSV guardado en $path');
    } catch (e) {
      _toast('Error: $e');
    }
  }

  /// Exportaciones CAD: planos PDF/DXF, modelo 3D DXF y SketchUp 2017 (.dae).
  Future<void> _exportCad(String kind) async {
    setState(() => _exporting = true);
    try {
      final path = switch (kind) {
        'cadpdf' => await exportCadPdf(d),
        'cadpdfbw' => await exportCadPdf(d, monochrome: true),
        'dxf2d' => await exportSheetsDxf(d),
        'dxf3d' => await exportModelDxf(d, _finish),
        _ => await exportSketchUp(d, _finish),
      };
      _toast(kind == 'dae'
          ? 'Guardado en $path. En SketchUp 2017: Archivo > Importar > COLLADA (*.dae).'
          : 'Guardado en $path');
    } catch (e) {
      _toast('Error al exportar: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(d.spec.type.label, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Ajustar parámetros',
            icon: const Icon(Icons.tune),
            onPressed: () => _editSpec(context),
          ),
          if (_exporting)
            const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
          else
            PopupMenuButton<String>(
              icon: const Icon(Icons.ios_share),
              tooltip: 'Exportar',
              onSelected: (v) {
                if (v == 'pdf') _exportPdf();
                if (v == 'print') _printPdf();
                if (v == 'csv') _exportCsv();
                if (const {'cadpdf', 'cadpdfbw', 'dxf2d', 'dxf3d', 'dae'}.contains(v)) _exportCad(v);
                if (v == 'models') {
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ModelsScreen()));
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'pdf', child: ListTile(leading: Icon(Icons.picture_as_pdf), title: Text('Proyecto completo (PDF)'))),
                PopupMenuItem(value: 'print', child: ListTile(leading: Icon(Icons.print), title: Text('Imprimir / vista previa'))),
                PopupMenuItem(value: 'csv', child: ListTile(leading: Icon(Icons.table_chart), title: Text('Despiece (CSV / Excel)'))),
                PopupMenuDivider(),
                PopupMenuItem(value: 'cadpdf', child: ListTile(leading: Icon(Icons.architecture), title: Text('Planos CAD A3 (PDF)'))),
                PopupMenuItem(value: 'cadpdfbw', child: ListTile(leading: Icon(Icons.print_outlined), title: Text('Planos CAD para plotter (PDF B/N)'))),
                PopupMenuItem(value: 'dxf2d', child: ListTile(leading: Icon(Icons.draw_outlined), title: Text('Planos 2D (DXF)'))),
                PopupMenuItem(value: 'dxf3d', child: ListTile(leading: Icon(Icons.view_in_ar), title: Text('Modelo 3D (DXF)'))),
                PopupMenuItem(value: 'dae', child: ListTile(leading: Icon(Icons.home_work_outlined), title: Text('SketchUp 2017 (.dae)'))),
                PopupMenuDivider(),
                PopupMenuItem(value: 'models', child: ListTile(leading: Icon(Icons.auto_awesome), title: Text('Modelos de IA local'))),
              ],
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_outlined), text: 'Resumen'),
            Tab(icon: Icon(Icons.list_alt), text: 'Despiece'),
            Tab(icon: Icon(Icons.local_fire_department_outlined), text: 'Soldadura'),
            Tab(icon: Icon(Icons.view_in_ar_outlined), text: 'Isométrica'),
            Tab(icon: Icon(Icons.architecture), text: 'Planos'),
            Tab(icon: Icon(Icons.engineering_outlined), text: 'Montaje'),
            Tab(icon: Icon(Icons.photo_camera_outlined), text: 'Render'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _SummaryTab(d: d),
          _BomTab(d: d, onPick: (g) {
            setState(() => _highlight = g);
            _tabs.animateTo(3);
          }),
          _WeldTab(d: d),
          _IsoTab(d: d, highlight: _highlight, onClear: () => setState(() => _highlight = null)),
          _SheetsTab(d: d),
          _AssemblyTab(d: d),
          _RenderTab(
            d: d,
            finish: _finish,
            onFinish: (f) => setState(() => _finish = f),
            hasAiPhoto: _aiPhoto != null,
            onAiPhoto: (png) {
              setState(() => _aiPhoto = png);
              _toast('La foto IA se usará como portada del PDF.');
            },
          ),
        ],
      ),
    );
  }

  Future<void> _editSpec(BuildContext context) async {
    final s = d.spec;
    final res = await showModalBottomSheet<StructureSpec>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SpecEditor(spec: s),
    );
    if (res != null) _recalc(res);
  }
}

// ---------------------------------------------------------------------------

class _SpecEditor extends StatefulWidget {
  final StructureSpec spec;
  const _SpecEditor({required this.spec});
  @override
  State<_SpecEditor> createState() => _SpecEditorState();
}

class _SpecEditorState extends State<_SpecEditor> {
  late StructureType type = widget.spec.type;
  late final _len = TextEditingController(text: _n(widget.spec.length, 2));
  late final _wid = TextEditingController(text: _n(widget.spec.width, 2));
  late final _hei = TextEditingController(text: _n(widget.spec.height, 2));
  late final _slope = TextEditingController(text: _n(widget.spec.slopePct, 1));
  late final _bay = TextEditingController(text: widget.spec.bay == null ? '' : _n(widget.spec.bay!, 2));
  late final _snow = TextEditingController(text: _n(widget.spec.snow, 2));
  late final _wind = TextEditingController(text: _n(widget.spec.wind, 2));
  late final _live = TextEditingController(text: _n(widget.spec.liveLoad, 2));
  late final _point = TextEditingController(text: _n(widget.spec.pointLoad, 1));
  late final _levels = TextEditingController(text: '${widget.spec.levels}');
  late SteelGrade grade = widget.spec.grade;

  double? _p(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.'));

  Widget _field(String label, TextEditingController c, String unit) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, suffixText: unit, isDense: true),
        ),
      );

  /// Al cambiar de tipología se toman los valores por defecto de la nueva.
  void _changeType(StructureType t) {
    if (t == type) return;
    final base = parsePrompt(t.label);
    setState(() {
      type = t;
      _len.text = _n(base.length, 2);
      _wid.text = _n(base.width, 2);
      _hei.text = _n(base.height, 2);
      _slope.text = _n(base.slopePct, 1);
      _bay.text = '';
      _live.text = _n(base.liveLoad, 2);
      _point.text = _n(base.pointLoad, 1);
      _levels.text = '${base.levels}';
      if (!t.hasRoof) _snow.text = '0';
    });
  }

  static const _bayTypes = {
    StructureType.nave,
    StructureType.marquesina,
    StructureType.entreplanta,
    StructureType.cercha,
    StructureType.pasarela,
  };

  @override
  Widget build(BuildContext context) {
    final (lLab, wLab, hLab) = type.dimLabels;
    final showL = !lLab.contains('no aplica') && type != StructureType.escalera;
    final showW = !wLab.contains('no aplica');
    final liveLabel = switch (type) {
      StructureType.barandilla => ('Carga en pasamanos', 'kN/m'),
      StructureType.entreplanta ||
      StructureType.escalera ||
      StructureType.pasarela ||
      StructureType.torre =>
        ('Sobrecarga de uso', 'kN/m²'),
      _ => null,
    };
    final pointLabel = switch (type) {
      StructureType.torre => 'Carga del depósito / equipo',
      StructureType.estanteria => 'Carga por nivel y vano',
      StructureType.portico => 'Carga del polipasto',
      _ => null,
    };
    final showLevels = type == StructureType.estanteria;
    final fields = <Widget>[
      if (showL) _field(lLab, _len, 'm'),
      if (showW) _field(wLab, _wid, 'm'),
      _field(hLab, _hei, 'm'),
      if (type.hasRoof) _field('Pendiente', _slope, '%'),
      if (_bayTypes.contains(type)) _field('Separación entre pórticos / apoyos (vacío = auto)', _bay, 'm'),
      if (type.hasRoof) _field('Nieve sk', _snow, 'kN/m²'),
      _field('Viento qb', _wind, 'kN/m²'),
      if (liveLabel != null) _field(liveLabel.$1, _live, liveLabel.$2),
      if (pointLabel != null) _field(pointLabel, _point, 'kN'),
      if (showLevels) _field('Niveles', _levels, ''),
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Parámetros de cálculo', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          DropdownButtonFormField<StructureType>(
            initialValue: type,
            decoration: const InputDecoration(labelText: 'Tipo de estructura', isDense: true),
            items: [for (final t in StructureType.values) DropdownMenuItem(value: t, child: Text(t.label))],
            onChanged: (v) => _changeType(v ?? type),
          ),
          for (var i = 0; i < fields.length; i += 2)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: fields[i]),
              const SizedBox(width: 8),
              Expanded(child: i + 1 < fields.length ? fields[i + 1] : const SizedBox()),
            ]),
          DropdownButtonFormField<SteelGrade>(
            initialValue: grade,
            decoration: const InputDecoration(labelText: 'Acero', isDense: true),
            items: [for (final g in [s235, s275, s355]) DropdownMenuItem(value: g, child: Text(g.name))],
            onChanged: (v) => setState(() => grade = v ?? grade),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Recalcular'),
            onPressed: () {
              final o = widget.spec;
              final same = type == o.type;
              final base = same ? o : parsePrompt(type.label);
              final s = StructureSpec(
                type: type,
                length: showL ? (_p(_len) ?? base.length).clamp(0.5, 300).toDouble() : base.length,
                width: showW ? (_p(_wid) ?? base.width).clamp(0.3, 80).toDouble() : base.width,
                height: (_p(_hei) ?? base.height).clamp(0.3, 40).toDouble(),
                slopePct: (_p(_slope) ?? base.slopePct).clamp(0, 100).toDouble(),
                bay: _bayTypes.contains(type) ? _p(_bay) : null,
                roofing: base.roofing,
                snow: type.hasRoof ? (_p(_snow) ?? base.snow) : 0,
                wind: _p(_wind) ?? base.wind,
                liveLoad: liveLabel != null ? (_p(_live) ?? base.liveLoad) : base.liveLoad,
                use: base.use,
                grade: grade,
                railing: type == StructureType.entreplanta ? true : base.railing,
                finish: o.finish,
                pointLoad: pointLabel != null ? (_p(_point) ?? base.pointLoad).clamp(0, 5000).toDouble() : base.pointLoad,
                levels: showLevels ? (int.tryParse(_levels.text) ?? base.levels).clamp(1, 12) : base.levels,
                variant: base.variant,
                parts: Map.of(base.parts),
                cladding: base.cladding,
                notes: [],
              );
              Navigator.pop(context, s);
            },
          ),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _Kpi extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _Kpi(this.label, this.value, this.icon);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 165,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

class _SummaryTab extends StatelessWidget {
  final Design d;
  const _SummaryTab({required this.d});
  @override
  Widget build(BuildContext context) {
    final s = d.spec;
    final cs = Theme.of(context).colorScheme;
    final main = <String, String>{};
    for (final p in d.pieces) {
      main.putIfAbsent(p.description, () => p.profile.name);
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('"${d.prompt}"', style: TextStyle(fontStyle: FontStyle.italic, color: cs.onSurfaceVariant)),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        _Kpi(metalLabel(s.grade), '${_n(d.steelKg, 0)} kg', Icons.scale),
        _Kpi('Ratio', '${_n(d.steelRatio.$1)} ${d.steelRatio.$2}', Icons.square_foot),
        _Kpi('Soldadura', '${_n(d.weldMeters)} m', Icons.local_fire_department),
        _Kpi('Consumible', '${_n(d.consumableKg)} kg', Icons.inventory_2_outlined),
        _Kpi('Pintura', '${_n(d.paintM2, 0)} m²', Icons.format_paint_outlined),
        _Kpi('Aprovech. máx.', '${_n(d.maxUtilization * 100, 0)} %', Icons.speed),
      ]),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Interpretación', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            _kv('Tipo', s.type.label),
            for (final (k, v) in [
              (s.type.dimLabels.$1, s.length),
              (s.type.dimLabels.$2, s.width),
              (s.type.dimLabels.$3, s.height),
            ])
              if (!k.contains('no aplica') && v > 0) _kv(k, '${_n(v, 2)} m'),
            if (s.variant.isNotEmpty) _kv('Variante', s.variant),
            if (s.type.hasRoof) _kv('Pendiente', '${_n(s.slopePct)} %'),
            if (d.frameX.length > 2)
              _kv('Modulación', '${d.frameX.length - 1} vanos de ${_n(d.frameX[1] - d.frameX[0], 2)} m'),
            if (s.roofing.isNotEmpty)
              _kv(s.type.hasRoof ? 'Cubierta' : 'Suelo / peldaño / relleno', s.roofing),
            if (s.pointLoad > 0) _kv('Carga concentrada', '${_n(s.pointLoad, 1)} kN'),
            if (s.levels > 0) _kv('Niveles', '${s.levels}'),
            if (s.type.hasRoof) _kv('Nieve', '${_n(s.snow, 2)} kN/m²'),
            if (s.wind > 0) _kv('Viento qb', '${_n(s.wind, 2)} kN/m²'),
            if (s.liveLoad > 0)
              _kv('Uso', '${s.use}${s.use.isEmpty ? '' : ' · '}${_n(s.liveLoad, 2)} ${s.type == StructureType.barandilla ? 'kN/m' : 'kN/m²'}'),
            _kv('Acero / acabado', '${s.grade.name} · ${s.finish}'),
          ]),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Materiales', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            for (final (k, v) in materialRows(d)) _kv(k, v),
          ]),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Perfiles recomendados', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            for (final e in main.entries) _kv(e.key, e.value),
          ]),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Comprobaciones (ELU / ELS)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            for (final c in d.checks) _CheckRow(c),
          ]),
        ),
      ),
      ExpansionTile(
        title: const Text('Hipótesis y normativa'),
        childrenPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          for (final h in d.hypotheses)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('•  '),
                Expanded(child: Text(h, style: const TextStyle(fontSize: 13))),
              ]),
            ),
        ],
      ),
      if (d.norms.isNotEmpty)
        ExpansionTile(
          title: Text('Normativa aplicable (${d.norms.length})'),
          childrenPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final n in d.norms)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${n.code} · ${n.title}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(n.summary, style: const TextStyle(fontSize: 12.5)),
                ]),
              ),
          ],
        ),
      for (final w in d.warnings)
        Card(
          color: cs.errorContainer,
          child: ListTile(
            leading: Icon(Icons.warning_amber, color: cs.onErrorContainer),
            title: Text(w, style: TextStyle(color: cs.onErrorContainer, fontSize: 13)),
          ),
        ),
    ]);
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 140, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
        ]),
      );
}

class _CheckRow extends StatelessWidget {
  final Check c;
  const _CheckRow(this.c);
  @override
  Widget build(BuildContext context) {
    final u = c.utilization;
    final col = u > 1 ? Colors.red : (u > 0.85 ? Colors.orange : Colors.green);
    return Tooltip(
      message: c.detail,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text('${c.element} · ${c.description}',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500))),
            Text('${_n(u * 100, 0)} %', style: TextStyle(color: col, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: u.clamp(0.0, 1.0), color: col, minHeight: 6),
          ),
          Text(c.detail, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _BomTab extends StatelessWidget {
  final Design d;
  final void Function(int group) onPick;
  const _BomTab({required this.d, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final groupOf = <String, int>{};
    for (final m in d.members) {
      groupOf[m.mark] = m.group;
    }
    DataTable table(List<String> cols, List<DataRow> rows) => DataTable(
          headingRowHeight: 36,
          dataRowMinHeight: 32,
          dataRowMaxHeight: 44,
          columnSpacing: 16,
          columns: [for (final c in cols) DataColumn(label: Text(c, style: const TextStyle(fontWeight: FontWeight.w700)))],
          rows: rows,
        );
    Widget section(String t, Widget child) => Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t, style: Theme.of(context).textTheme.titleMedium),
              SingleChildScrollView(scrollDirection: Axis.horizontal, child: child),
            ]),
          ),
        );
    return ListView(padding: const EdgeInsets.all(12), children: [
      Text('Toca una marca para verla resaltada en la isométrica.',
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      section(
        'Perfiles (${_n(d.profilesKg, 0)} kg)',
        table(['Marca', 'Elemento', 'Perfil', 'Long. mm', 'Ud.', 'Corte', 'kg'], [
          for (final p in d.pieces)
            DataRow(
              onSelectChanged: (_) => onPick(groupOf[p.mark] ?? 0),
              cells: [
                DataCell(Chip(label: Text(p.mark), visualDensity: VisualDensity.compact)),
                DataCell(Text(p.description)),
                DataCell(Text(p.profile.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                DataCell(Text(p.lengthMm.toStringAsFixed(0))),
                DataCell(Text('${p.qty}')),
                DataCell(Text(p.cut, style: const TextStyle(fontSize: 12))),
                DataCell(Text(_n(p.totalKg, 0))),
              ],
            ),
        ]),
      ),
      section(
        'Chapas (${_n(d.platesKg, 0)} kg)',
        table(['Marca', 'Descripción', 'Dimensiones mm', 'Ud.', 'kg', 'Notas'], [
          for (final p in d.plates)
            DataRow(cells: [
              DataCell(Text(p.mark)),
              DataCell(Text(p.description)),
              DataCell(Text('${p.w.toStringAsFixed(0)} x ${p.h.toStringAsFixed(0)} x ${p.t.toStringAsFixed(0)}')),
              DataCell(Text('${p.qty}')),
              DataCell(Text(_n(p.totalKg, 0))),
              DataCell(Text(p.notes, style: const TextStyle(fontSize: 12))),
            ]),
        ]),
      ),
      section(
        'Tornillería y anclajes',
        table(['Elemento', 'Especificación', 'Ud.', 'Uso'], [
          for (final b in d.bolts)
            DataRow(cells: [
              DataCell(Text(b.description)),
              DataCell(Text(b.spec, style: const TextStyle(fontSize: 12))),
              DataCell(Text('${b.qty}')),
              DataCell(Text(b.use)),
            ]),
        ]),
      ),
      section(
        'Pedido de barras comerciales',
        table(['Perfil', 'Barra', 'Nº barras', 'kg', 'Merma'], [
          for (final st in d.stock)
            DataRow(cells: [
              DataCell(Text(st.profile.name)),
              DataCell(Text('${_n(st.barLength / 1000, 0)} m')),
              DataCell(Text('${st.bars}')),
              DataCell(Text(_n(st.bars * st.barLength / 1000 * st.profile.kgm, 0))),
              DataCell(Text('${_n(st.wastePct)} %')),
            ]),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------

class _WeldTab extends StatelessWidget {
  final Design d;
  const _WeldTab({required this.d});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Wrap(spacing: 10, runSpacing: 10, children: [
        _Kpi('Cordón total', '${_n(d.weldMeters)} m', Icons.straighten),
        _Kpi('Metal depositado', '${_n(d.welds.fold<double>(0, (s, w) => s + w.depositedKg), 2)} kg', Icons.scale),
        _Kpi('Consumible (≈65 %)', '${_n(d.consumableKg, 1)} kg', Icons.inventory_2_outlined),
      ]),
      const SizedBox(height: 8),
      for (final w in d.welds)
        Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: cs.primaryContainer,
              child: Text('a${w.throat.toStringAsFixed(0)}',
                  style: TextStyle(fontWeight: FontWeight.w700, color: cs.onPrimaryContainer, fontSize: 13)),
            ),
            title: Text(w.joint, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
                '${w.type}\n${w.count} uniones x ${w.lengthPerJoint.toStringAsFixed(0)} mm = ${_n(w.totalMeters)} m · consumible ${_n(w.consumableKg, 2)} kg\n${w.process} · ${w.position}${w.notes.isEmpty ? '' : '\n${w.notes}'}'),
            isThreeLine: true,
          ),
        ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Especificación general de soldadura', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            ...[
              'Garganta "a" de cordones en ángulo para resistencia completa: a ≥ 0,46·t (S235), 0,48·t (S275), 0,55·t (S355), con mínimos constructivos (3/4/5 mm) y a ≤ 0,7·t mín.',
              'Procesos: 135 MAG (hilo macizo ER70S-6 / G3Si1, Ø1,0–1,2 mm, gas Ar+18 % CO₂) en taller; 111 electrodo básico E7018 en obra.',
              'Precalentamiento: no necesario para t ≤ 25 mm en S275; para S355 y t > 25 mm, 75–100 °C (EN 1011-2).',
              'Preparación: limpieza de cascarilla, óxido, pintura y humedad en 20 mm a cada lado del cordón.',
              'Cualificación: soldadores EN ISO 9606-1, procedimientos EN ISO 15614-1 (WPS/WPQR).',
              'Inspección: visual 100 % (EN ISO 17637); END complementarios según EN 1090-2 EXC2 (p. ej. 10 % partículas magnéticas en uniones de nudo).',
              'Calidad: nivel C según EN ISO 5817. Tras soldar, cepillado y retoque de imprimación (zinc en galvanizados).',
            ].map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('•  '),
                    Expanded(child: Text(t, style: const TextStyle(fontSize: 13))),
                  ]),
                )),
          ]),
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------

class _IsoTab extends StatefulWidget {
  final Design d;
  final int? highlight;
  final VoidCallback onClear;
  const _IsoTab({required this.d, this.highlight, required this.onClear});
  @override
  State<_IsoTab> createState() => _IsoTabState();
}

class _IsoTabState extends State<_IsoTab> {
  double yaw = -40;
  bool labels = true;
  final _key = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
        child: Container(
          color: Colors.white,
          child: InteractiveViewer(
            maxScale: 8,
            child: RepaintBoundary(
              key: _key,
              child: CustomPaint(
                painter: IsoPainter(widget.d, yawDeg: yaw, highlight: widget.highlight, labels: labels),
                size: Size.infinite,
              ),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          const Icon(Icons.threesixty, size: 20),
          Expanded(
            child: Slider(value: yaw, min: -180, max: 180, onChanged: (v) => setState(() => yaw = v)),
          ),
          IconButton(
            tooltip: 'Marcas',
            icon: Icon(labels ? Icons.label : Icons.label_off_outlined),
            onPressed: () => setState(() => labels = !labels),
          ),
          if (widget.highlight != null)
            IconButton(tooltip: 'Quitar resaltado', icon: const Icon(Icons.highlight_off), onPressed: widget.onClear),
          IconButton(
            tooltip: 'Guardar imagen',
            icon: const Icon(Icons.download),
            onPressed: () => _saveBoundary(context, _key, widget.d, 'isometrica'),
          ),
        ]),
      ),
    ]);
  }
}

Future<void> _saveBoundary(BuildContext context, GlobalKey key, Design d, String suffix) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final ro = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await ro.toImage(pixelRatio: 2.5);
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    final path = await exportPng(bd!.buffer.asUint8List(), d, suffix);
    messenger.showSnackBar(SnackBar(content: Text('Imagen guardada en $path')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
  }
}

// ---------------------------------------------------------------------------

class _SheetsTab extends StatefulWidget {
  final Design d;
  const _SheetsTab({required this.d});
  @override
  State<_SheetsTab> createState() => _SheetsTabState();
}

class _SheetsTabState extends State<_SheetsTab> {
  late List<CadSheet> sheets = buildSheets(widget.d);
  int sel = 0;
  bool mono = false;
  final _key = GlobalKey();

  @override
  void didUpdateWidget(covariant _SheetsTab old) {
    super.didUpdateWidget(old);
    if (old.d != widget.d) {
      sheets = buildSheets(widget.d);
      sel = sel.clamp(0, sheets.length - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sh = sheets[sel];
    return Column(children: [
      SizedBox(
        height: 52,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          itemCount: sheets.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (_, i) => ChoiceChip(
            label: Text('${sheets[i].number} ${sheets[i].title}'),
            selected: i == sel,
            onSelected: (_) => setState(() => sel = i),
          ),
        ),
      ),
      Expanded(
        child: Container(
          color: const Color(0xFF90A4AE),
          child: InteractiveViewer(
            maxScale: 16,
            child: Center(
              child: AspectRatio(
                aspectRatio: sh.width / sh.height,
                child: RepaintBoundary(
                  key: _key,
                  child: CustomPaint(painter: CadPainter(sh, monochrome: mono), size: Size.infinite),
                ),
              ),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(6),
        child: Wrap(alignment: WrapAlignment.center, spacing: 4, children: [
          TextButton.icon(
            icon: Icon(mono ? Icons.palette_outlined : Icons.contrast),
            label: Text(mono ? 'Color' : 'Blanco y negro'),
            onPressed: () => setState(() => mono = !mono),
          ),
          TextButton.icon(
            icon: const Icon(Icons.download),
            label: Text('Guardar ${sh.number} como imagen'),
            onPressed: () => _saveBoundary(context, _key, widget.d, sh.number),
          ),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------

class _AssemblyTab extends StatelessWidget {
  final Design d;
  const _AssemblyTab({required this.d});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(12), children: [
      SizedBox(
        height: 260,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: Container(color: Colors.white, child: CustomPaint(painter: IsoPainter(d, labels: true))),
        ),
      ),
      Text('Secuencia de montaje', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      for (final e in d.assembly.asMap().entries)
        Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              child: Text('${e.key + 1}'),
            ),
            title: Text(e.value, style: const TextStyle(fontSize: 14)),
          ),
        ),
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Tolerancias de montaje (EN 1090-2)', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            const Text(
              '• Desplome de pilares ≤ h/300 (individual) y ≤ h/500 medio por fila.\n'
              '• Posición de pernos de anclaje ±6 mm; cota de placas ±5 mm.\n'
              '• Distancia entre ejes de pórticos ±5 mm por vano.\n'
              '• Flecha inicial de vigas ≤ L/1000.',
              style: TextStyle(fontSize: 13),
            ),
          ]),
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------

class _RenderTab extends StatefulWidget {
  final Design d;
  final Finish finish;
  final ValueChanged<Finish> onFinish;
  final bool hasAiPhoto;
  final ValueChanged<Uint8List> onAiPhoto;
  const _RenderTab(
      {required this.d,
      required this.finish,
      required this.onFinish,
      required this.hasAiPhoto,
      required this.onAiPhoto});
  @override
  State<_RenderTab> createState() => _RenderTabState();
}

class _RenderTabState extends State<_RenderTab> {
  final cam = OrbitCamera();
  double sun = 0.9;
  bool roof = true;
  late SceneMesh mesh = SceneMesh.build(widget.d, widget.finish, roof: roof);
  final _key = GlobalKey();
  double _scaleStart = 1;
  int _v = 0;

  @override
  void didUpdateWidget(covariant _RenderTab old) {
    super.didUpdateWidget(old);
    if (old.d != widget.d || old.finish != widget.finish) {
      mesh = SceneMesh.build(widget.d, widget.finish, roof: roof);
    }
  }

  void _rebuild() => setState(() => mesh = SceneMesh.build(widget.d, widget.finish, roof: roof));

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
        child: Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) {
              setState(() {
                cam.distance = (cam.distance * (1 + e.scrollDelta.dy / 800)).clamp(0.8, 6.0);
                _v++;
              });
            }
          },
          child: GestureDetector(
            onScaleStart: (_) => _scaleStart = cam.distance,
            onScaleUpdate: (s) => setState(() {
              cam.yaw -= s.focalPointDelta.dx * 0.008;
              cam.pitch = (cam.pitch + s.focalPointDelta.dy * 0.006).clamp(0.03, 1.45);
              if (s.scale != 1) cam.distance = (_scaleStart / s.scale).clamp(0.8, 6.0);
              _v++;
            }),
            child: RepaintBoundary(
              key: _key,
              child: ZRenderView(mesh: mesh, cam: cam, sun: sun, version: _v),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: Wrap(spacing: 6, runSpacing: 4, children: [
          for (final f in Finish.values)
            ChoiceChip(
              label: Text(f.label),
              selected: widget.finish == f,
              onSelected: (_) => widget.onFinish(f),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          const Icon(Icons.wb_sunny_outlined, size: 20),
          Expanded(child: Slider(value: sun, min: -3.14, max: 3.14, onChanged: (v) => setState(() => sun = v))),
          FilterChip(
            label: const Text('Cubierta'),
            selected: roof,
            onSelected: (v) {
              roof = v;
              _rebuild();
            },
          ),
          IconButton(
            tooltip: 'Guardar imagen',
            icon: const Icon(Icons.download),
            onPressed: () => _saveBoundary(context, _key, widget.d, 'render'),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: Icon(widget.hasAiPhoto ? Icons.check_circle : Icons.auto_awesome),
            label: Text(widget.hasAiPhoto ? 'Foto IA lista para el PDF · generar otra' : 'Foto realista con IA local'),
            onPressed: () async {
              final png = await openAiPhoto(context,
                  d: widget.d, finish: widget.finish, cam: cam, sun: sun, roof: roof);
              if (png != null) widget.onAiPhoto(png);
            },
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text('Arrastra para girar · pellizca o rueda para acercar',
            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ),
    ]);
  }
}

