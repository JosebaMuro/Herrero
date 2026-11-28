import 'package:material_ui/material_ui.dart';

import '../ai/remote_settings.dart';
import '../ai/comprehension.dart';
import '../ai/learned_examples.dart';
import '../ai/local_text.dart';
import '../ai/model_gate.dart';
import '../ai/model_manager.dart';
import '../engine/comprehension_aids.dart' show fichaJson;
import '../engine/designer.dart';
import '../engine/model.dart';
import '../engine/parser.dart' show stairForms, railForms;
import '../engine/understanding.dart';
import 'models_screen.dart';
import 'project_screen.dart';

/// Ficha de interpretación: lo que la app ha entendido de la petición, con el
/// origen de cada dato, antes de calcular. Sale al instante con las reglas y
/// la IA local (si está instalada) la afina en segundo plano.
class UnderstandScreen extends StatefulWidget {
  final String prompt;
  const UnderstandScreen({super.key, required this.prompt});

  @override
  State<UnderstandScreen> createState() => _UnderstandScreenState();
}

class _UnderstandScreenState extends State<UnderstandScreen> {
  late Understanding u;
  List<(StructureType, double)> _ranking = const [];
  Map<String, dynamic>? _llm;
  StructureType? _forced;
  final Map<String, Object> _overrides = {};
  bool _embedBusy = false, _llmBusy = false, _noModels = false;
  String _partial = '';
  String _thought = ''; // razonamiento del LLM (modelos con modo razonamiento)
  String? _aiError;
  LlmJob? _job;

  @override
  void initState() {
    super.initState();
    ModelGate.instance.enter(WorkflowStep.comprension);
    u = understand(widget.prompt);
    _startAi();
  }

  @override
  void dispose() {
    _job?.cancel();
    super.dispose();
  }

  void _recompute() {
    if (!mounted) return;
    setState(() {
      u = understand(widget.prompt, ranking: _ranking, llm: _llm, forceType: _forced, overrides: _overrides);
    });
  }

  Future<void> _startAi() async {
    final mgr = ModelManager.instance;
    try {
      await mgr.load();
    } catch (_) {
      // sin catálogo local aún puede razonar el endpoint de Ajustes
      if (!(await RemoteLlmStore.instance.load()).usable) {
        if (mounted) setState(() => _noModels = true);
        return;
      }
    }
    if (!mounted) return;
    final canReason = await Comprehension.instance.canReason();
    if (!mounted) return;
    setState(() => _noModels = !mgr.embedReady && !canReason);
    if (mgr.embedReady) {
      setState(() => _embedBusy = true);
      try {
        _ranking = await Comprehension.instance.rank(widget.prompt);
      } catch (e) {
        _aiError = 'Comprensión: $e';
      }
      if (!mounted) return;
      _embedBusy = false;
      _recompute();
    }
    if (canReason) {
      final type = u.type;
      setState(() => _llmBusy = true);
      try {
        _job = await Comprehension.instance.read(widget.prompt, type, (p) {
          if (mounted) setState(() => _partial = p);
        });
        final job = _job;
        if (job == null) throw Exception('sin modelo de razonamiento');
        final r = await job.future;
        // el endpoint devuelve la ficha entera; el local sigue tras la semilla
        final t = r.text.trimLeft();
        _llm = t.startsWith('{') ? parseLlmJson(t) : parseLlmJson(r.text, llmSeed(type));
        _thought = r.thought;
      } catch (e) {
        if (!'$e'.contains('Cancelado')) _aiError = 'Razonamiento: $e';
      }
      _job = null;
      if (!mounted) return;
      _llmBusy = false;
      _recompute();
    }
  }

  void _skipLlm() {
    _job?.cancel();
    setState(() => _llmBusy = false);
  }

  void _calc() {
    _learn();
    try {
      final d = designFromSpec(u.spec, widget.prompt);
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProjectScreen(design: d)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo calcular: $e')));
    }
  }

  /// Si el usuario ha corregido la ficha, la guarda como ejemplo para el LLM
  /// (con lo que dice el texto y lo cambiado; no los valores de serie).
  void _learn() {
    if (_overrides.isEmpty) return;
    final s = u.spec;
    final all = <String, Object>{
      'length': s.length,
      'width': s.width,
      'height': s.height,
      'roofing': s.roofing,
      'finish': s.finish,
      if (_overrides['city'] case final Object c) 'city': c,
      'use': s.use,
      'liveLoad': (s.liveLoad * 100).roundToDouble(),
      'levels': s.levels,
    };
    final keep = <String, Object>{
      for (final e in all.entries)
        if (u.sources[e.key] == DataSource.user || u.sources[e.key] == DataSource.text) e.key: e.value
    };
    LearnedExamples.instance.add(widget.prompt, fichaJson(u.type, keep)).ignore();
  }

  // --- edición de la ficha ----------------------------------------------------

  void _set(String field, Object value) {
    _overrides[field] = value;
    _recompute();
  }

  Future<void> _editNumber(String field, String label, double current, {String unit = 'm'}) async {
    final c = TextEditingController(text: _fmt(current));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(suffixText: unit),
          onSubmitted: (t) => Navigator.pop(ctx, double.tryParse(t.replaceAll(',', '.'))),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, double.tryParse(c.text.replaceAll(',', '.'))),
              child: const Text('Aceptar')),
        ],
      ),
    );
    if (v != null && v > 0) _set(field, v);
  }

  Future<void> _editText(String field, String label, String hint) async {
    final c = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (t) => Navigator.pop(ctx, t),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Aceptar')),
        ],
      ),
    );
    if (v != null && v.trim().isNotEmpty) _set(field, v.trim());
  }

  Future<void> _choose(String field, String label, List<String> options, {Map<String, String> labels = const {}}) async {
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(label),
        children: [
          for (final o in options) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, o), child: Text(labels[o] ?? o)),
        ],
      ),
    );
    if (v != null) _set(field, v);
  }

  /// Formas o rellenos que se pueden elegir en la ficha: (título, opciones).
  static (String, List<String>)? _forms(StructureType t) => switch (t) {
        StructureType.escalera => ('Forma', stairForms),
        StructureType.barandilla => ('Relleno', railForms),
        StructureType.valla => ('Tipo', const ['barrotes', 'chapa', 'malla', 'reja']),
        _ => null,
      };

  static const _formLabels = {
    'recta': 'Recta',
    'en l': 'En L (meseta de giro a 90°)',
    'en u': 'En U (ida y vuelta)',
    'zanca central': 'Zanca central',
    'caracol': 'De caracol',
    'escala de gato': 'Escala de gato (vertical)',
    'barrotes': 'Barrotes',
    'vidrio': 'Vidrio',
    'cables': 'Cables de acero',
    'chapa perforada': 'Chapa perforada',
    'lamas': 'Lamas',
    'barras horizontales': 'Barras horizontales',
    'pasamanos a pared': 'Solo pasamanos a pared',
    'chapa': 'Chapa ciega',
    'malla': 'Malla',
    'reja': 'Reja de ventana',
  };

  /// Forma actual (sin los añadidos «· exterior», «· rodapié»…).
  static String _formOf(String variant) => variant.split(' · ').first.trim();

  // --- presentación -----------------------------------------------------------

  static String _fmt(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 2).replaceAll('.', ',');

  /// Medidas que tienen sentido en cada tipología: (campo, etiqueta).
  static List<(String, String)> _dims(StructureType t, [String variant = '']) {
    final f = _formOf(variant);
    if (t == StructureType.escalera && f == 'caracol') return [('height', 'Desnivel a salvar'), ('width', 'Diámetro')];
    if (t == StructureType.escalera && f == 'escala de gato') return [('height', 'Altura de subida'), ('width', 'Ancho entre largueros')];
    if (t == StructureType.valla && f == 'reja') return [('length', 'Ancho del hueco'), ('height', 'Alto del hueco')];
    return _dimsOf(t);
  }

  static List<(String, String)> _dimsOf(StructureType t) => switch (t) {
        StructureType.nave => [('length', 'Largo'), ('width', 'Luz (ancho)'), ('height', 'Altura al alero')],
        StructureType.marquesina => [('length', 'Largo'), ('width', 'Fondo'), ('height', 'Altura libre')],
        StructureType.entreplanta => [('length', 'Largo'), ('width', 'Ancho'), ('height', 'Altura bajo forjado')],
        StructureType.escalera => [('height', 'Desnivel a salvar'), ('width', 'Ancho de paso')],
        StructureType.pasarela => [('length', 'Longitud'), ('width', 'Ancho útil'), ('height', 'Altura')],
        StructureType.barandilla => [('length', 'Longitud'), ('height', 'Altura')],
        StructureType.cercha => [('length', 'Longitud de cubierta'), ('width', 'Luz'), ('height', 'Altura de apoyo')],
        StructureType.torre => [('length', 'Lado de la base'), ('height', 'Altura')],
        StructureType.estanteria => [('length', 'Largo'), ('width', 'Fondo'), ('height', 'Altura')],
        StructureType.cancela => [('length', 'Hueco libre'), ('height', 'Altura')],
        StructureType.valla => [('length', 'Longitud'), ('height', 'Altura')],
        StructureType.portico => [('width', 'Luz entre patas'), ('height', 'Altura bajo viga')],
        StructureType.poste => [('length', 'Ancho del cartel'), ('width', 'Alto del cartel'), ('height', 'Altura libre')],
      };

  double _dimValue(String f) => switch (f) {
        'length' => u.spec.length,
        'width' => u.spec.width,
        _ => u.spec.height,
      };

  Widget _source(DataSource? s) {
    final cs = Theme.of(context).colorScheme;
    final (bg, fg) = switch (s ?? DataSource.assumed) {
      DataSource.text => (Colors.green.shade100, Colors.green.shade900),
      DataSource.deduced => (Colors.blue.shade100, Colors.blue.shade900),
      DataSource.ai => (Colors.purple.shade100, Colors.purple.shade900),
      DataSource.user => (Colors.orange.shade100, Colors.orange.shade900),
      DataSource.assumed => (cs.surfaceContainerHighest, cs.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text((s ?? DataSource.assumed).label, style: TextStyle(fontSize: 11, color: fg)),
    );
  }

  Widget _row(String label, String value, DataSource? src, VoidCallback onTap) => ListTile(
        dense: true,
        title: Text(label),
        subtitle: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [_source(src), const Icon(Icons.edit, size: 18)]),
        onTap: onTap,
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = u.spec;
    final t = u.type;
    final floor = t == StructureType.entreplanta || t == StructureType.pasarela || t == StructureType.escalera;
    final roof = t == StructureType.nave || t == StructureType.marquesina || t == StructureType.cercha;
    final alternatives = _ranking.where((e) => e.$1 != t).take(2).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Lo que he entendido')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text('«${widget.prompt.trim()}»', style: TextStyle(fontStyle: FontStyle.italic, color: cs.onSurfaceVariant)),
                const SizedBox(height: 8),
                if (_embedBusy || _llmBusy)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_embedBusy
                                ? 'Comprendiendo tu petición con IA local…'
                                : 'Leyendo tu petición con razonamiento local… Puedes calcular ya si la ficha está bien.'),
                          ),
                          if (_llmBusy) TextButton(onPressed: _skipLlm, child: const Text('Saltar')),
                        ]),
                        if (_llmBusy && _partial.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(_partial, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                          ),
                      ]),
                    ),
                  ),
                if (!_llmBusy && _thought.isNotEmpty)
                  Card(
                    child: ExpansionTile(
                      leading: const Icon(Icons.psychology_alt_outlined),
                      title: const Text('Cómo lo ha razonado la IA'),
                      subtitle: const Text('Solo se usan los datos que respalda tu texto'),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      children: [SelectableText(_thought, style: const TextStyle(fontSize: 12))],
                    ),
                  ),
                if (_noModels)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.psychology_outlined),
                      title: const Text('Comprensión con IA no instalada'),
                      subtitle: const Text('La ficha sale de las reglas del oficio. Descarga «Comprensión» y '
                          '«Razonamiento», o activa un endpoint (FreeLLMAPI) en Ajustes, para que entienda peticiones con tus palabras.'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => const ModelsScreen()))
                          .then((_) => _startAi()),
                    ),
                  ),
                if (_aiError != null)
                  Card(
                    color: cs.errorContainer,
                    child: ListTile(dense: true, leading: const Icon(Icons.error_outline), title: Text(_aiError!)),
                  ),
                Card(
                  child: Column(children: [
                    ListTile(
                      title: const Text('Tipología'),
                      subtitle: DropdownButton<StructureType>(
                        value: t,
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        items: [
                          for (final x in StructureType.values) DropdownMenuItem(value: x, child: Text(x.label)),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          _forced = v;
                          _overrides.remove('variant');
                          _recompute();
                        },
                      ),
                      trailing: _source(u.typeSource),
                    ),
                    if (alternatives.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Wrap(spacing: 8, children: [
                          for (final (a, _) in alternatives)
                            ActionChip(
                              avatar: const Icon(Icons.swap_horiz, size: 16),
                              label: Text('¿O es ${a.label.split('/').first.trim().toLowerCase()}?'),
                              onPressed: () {
                                _forced = a;
                                _overrides.remove('variant');
                                _recompute();
                              },
                            ),
                        ]),
                      ),
                    const Divider(height: 1),
                    if (_forms(t) case (final title, final options))
                      _row(title, _formLabels[_formOf(s.variant)] ?? _formOf(s.variant), u.sources['variant'],
                          () => _choose('variant', title, options, labels: _formLabels)),
                    for (final (f, label) in _dims(t, s.variant))
                      _row(label, '${_fmt(_dimValue(f))} m', u.sources[f], () => _editNumber(f, label, _dimValue(f))),
                    if (t == StructureType.estanteria || t == StructureType.torre)
                      _row('Niveles', s.levels > 0 ? '${s.levels}' : 'según altura', u.sources['levels'],
                          () => _editNumber('levels', 'Niveles', s.levels.toDouble(), unit: '')),
                    if (roof || floor)
                      _row(
                        roof ? 'Cubierta' : 'Suelo',
                        s.roofing.isEmpty ? '—' : s.roofing,
                        u.sources['roofing'],
                        () => _choose(
                          'roofing',
                          roof ? 'Cubierta' : 'Suelo',
                          roof
                              ? const [
                                  'panel sándwich', 'chapa grecada', 'policarbonato', 'teja sobre panel',
                                  'vidrio laminado', 'paneles fotovoltaicos', 'sin cubierta (pérgola abierta)'
                                ]
                              : const ['rejilla tramex', 'chapa lagrimada'],
                        ),
                      ),
                    if (floor || t == StructureType.estanteria)
                      _row('Sobrecarga de uso', '${_fmt(s.liveLoad * 100)} kg/m²', u.sources['liveLoad'],
                          () => _editNumber('liveLoad', 'Sobrecarga de uso', s.liveLoad * 100, unit: 'kg/m²')),
                    _row('Acero', s.grade.name, u.sources['grade'],
                        () => _choose('grade', 'Acero', const ['S235JR', 'S275JR', 'S355J2', 'corten', 'inoxidable 304', 'inoxidable 316', 'aluminio 6060', 'aluminio 6082'])),
                    _row('Acabado', s.finish, u.sources['finish'],
                        () => _choose('finish', 'Acabado', const ['galvanizado en caliente', 'pintado', 'galvanizado y lacado', 'lacado', 'acero corten'])),
                    _row('Ubicación (nieve y viento)',
                        'nieve ${_fmt(s.snow)} kN/m² · viento qb ${_fmt(s.wind)} kN/m²', u.sources['city'],
                        () => _editText('city', 'Ubicación', 'Ciudad o provincia')),
                    if (s.use.isNotEmpty || u.sources['use'] != DataSource.assumed)
                      _row('Uso', s.use.isEmpty ? '—' : s.use, u.sources['use'],
                          () => _editText('use', 'Uso', 'Para qué es')),
                  ]),
                ),
                if (u.warnings.isNotEmpty)
                  Card(
                    color: cs.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(Icons.warning_amber, color: cs.onErrorContainer, size: 20),
                          const SizedBox(width: 6),
                          Text('Revisa estos datos',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: cs.onErrorContainer)),
                        ]),
                        const SizedBox(height: 6),
                        for (final w in u.warnings)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text('•  $w', style: TextStyle(fontSize: 13, color: cs.onErrorContainer)),
                          ),
                      ]),
                    ),
                  ),
                if (u.questions.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Para afinar', style: Theme.of(context).textTheme.titleSmall),
                        for (final q in u.questions) ...[
                          const SizedBox(height: 8),
                          Text(q.text, style: const TextStyle(fontSize: 13)),
                          const SizedBox(height: 4),
                          Wrap(spacing: 6, runSpacing: 4, children: [
                            for (final (label, value) in q.options)
                              ActionChip(label: Text(label), onPressed: () => _set(q.field, value)),
                          ]),
                        ],
                      ]),
                    ),
                  ),
                if (u.notes.isNotEmpty || s.notes.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Razonamiento', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 6),
                        for (final n in [...u.notes, ...s.notes])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('•  '),
                              Expanded(child: Text(n, style: const TextStyle(fontSize: 13))),
                            ]),
                          ),
                      ]),
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _calc,
                  icon: const Icon(Icons.calculate),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Calcular estructura', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 8),
                Text('Toca un dato para cambiarlo. Verde: de tu texto · azul: deducido por oficio · morado: leído por '
                    'la IA · gris: valor habitual · naranja: cambiado por ti.',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
