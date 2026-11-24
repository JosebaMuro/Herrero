import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/autocomplete.dart';
import '../ai/model_gate.dart';
import '../services/price_store.dart';
import '../services/project_store.dart';
import '../system/boot_mode.dart';
import 'catalog_screen.dart';
import 'models_screen.dart';
import 'plan_import_screen.dart';
import 'prices_screen.dart';
import 'projects_screen.dart';
import 'understand_screen.dart';

const examples = [
  'Nave a dos aguas de 30 x 15 m, 6 m de altura al alero, pórticos cada 6 m, panel sándwich, en Vitoria',
  'Marquesina para 2 coches de 5,5 x 5 m y 2,4 m de alto, panel sándwich, galvanizada',
  'Nave de 20 x 12 m, 6 m al alero, pilares HEB 220, correas de tubo, tirantes de redondo 16, en S355',
  'Escalera recta de 3 m de altura y 1 m de ancho con barandilla, peldaños de tramex, galvanizada',
  'Pasarela de 8 m de luz y 1,5 m de ancho, suelo de chapa lagrimada',
  'Pérgola de aluminio de 4 x 3 m con policarbonato celular de 16 mm',
  'Altillo de 8 x 4 m a 3 m de altura para almacén, suelo de tramex',
  'Cancela corredera de 5 m y 2 m de alto, lacada en negro',
  'Barandilla de inox 316 de 12 m para terraza',
  'Torre de 6 m para depósito de 5000 litros',
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _ctrl = TextEditingController();
  List<String> _history = [];
  bool _busy = false;

  List<Suggestion> _suggestions = const [];

  @override
  void initState() {
    super.initState();
    ModelGate.instance.enter(WorkflowStep.inicio);
    _loadHistory();
    _loadProjects();
    _ctrl.addListener(_onEdit);
  }

  List<ProjectSummary> _projects = const [];

  Future<void> _loadProjects() async {
    try {
      final st = await projectStore();
      if (mounted) setState(() => _projects = st.list().take(5).toList());
    } catch (_) {}
  }

  Future<void> _go(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    ModelGate.instance.enter(WorkflowStep.inicio);
    _loadProjects();
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onEdit);
    _ctrl.dispose();
    super.dispose();
  }

  /// Autocompletar: sugerencias con el vocabulario del oficio al escribir.
  void _onEdit() {
    final sel = _ctrl.selection;
    final cur = sel.isValid && sel.isCollapsed ? sel.baseOffset : _ctrl.text.length;
    final next = suggest(_ctrl.text, cursor: cur);
    final same = next.length == _suggestions.length &&
        [for (var i = 0; i < next.length; i++) next[i].label == _suggestions[i].label].every((e) => e);
    if (!same && mounted) setState(() => _suggestions = next);
  }

  void _accept(Suggestion s) {
    _ctrl.value = TextEditingValue(
      text: s.text,
      selection: TextSelection.collapsed(offset: s.cursor.clamp(0, s.text.length)),
    );
  }

  Future<void> _loadHistory() async {
    try {
      final sp = await SharedPreferences.getInstance();
      setState(() => _history = sp.getStringList('history') ?? []);
    } catch (_) {}
  }

  Future<void> _saveHistory(String p) async {
    _history.remove(p);
    _history.insert(0, p);
    if (_history.length > 15) _history = _history.sublist(0, 15);
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList('history', _history);
    } catch (_) {}
  }

  Future<void> _run([String? text]) async {
    final p = (text ?? _ctrl.text).trim();
    if (p.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Describe la estructura: tipo, medidas, altura, ubicación…')));
      return;
    }
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    try {
      await _saveHistory(p);
      if (!mounted) return;
      await _go(UnderstandScreen(prompt: p));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo calcular: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Linux: arranque en modo terminal (sin X11) con la TUI de Herrero, y reinicio.
  Future<void> _rebootToTui() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.terminal),
        title: const Text('Reiniciar en modo terminal'),
        content: const Text('El equipo se reiniciará sin escritorio (sin X11) y abrirá Herrero en la terminal, '
            'con toda la gráfica para la IA. Arrancará así a partir de ahora; desde la terminal se vuelve al '
            'escritorio con Ctrl+R.\n\nGuarda antes lo que tengas abierto.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Reiniciar')),
        ],
      ),
    );
    if (ok != true) return;
    final err = await rebootInto(BootMode.tui, graphical: true);
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), duration: const Duration(seconds: 10)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.construction),
          SizedBox(width: 10),
          Flexible(child: Text('Herrero · Oficina técnica', overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          IconButton(
            tooltip: 'Proyectos guardados',
            icon: const Icon(Icons.folder_open),
            onPressed: () => _go(const ProjectsScreen()),
          ),
          IconButton(
            tooltip: 'Precios, facturas y proveedores',
            icon: const Icon(Icons.euro),
            onPressed: () => _go(const PricesScreen()),
          ),
          IconButton(
            tooltip: 'Importar plano (PDF o imagen)',
            icon: const Icon(Icons.upload_file),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PlanImportScreen())),
          ),
          IconButton(
            tooltip: 'Estructuras, materiales y vocabulario',
            icon: const Icon(Icons.menu_book),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CatalogScreen())),
          ),
          IconButton(
            tooltip: 'Modelos de IA locales',
            icon: const Icon(Icons.download_for_offline_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ModelsScreen())),
          ),
          if (bootModeSupported && File('/usr/local/bin/herrero-tui').existsSync())
            IconButton(
              tooltip: 'Reiniciar en modo terminal (TUI)',
              icon: const Icon(Icons.terminal),
              onPressed: _rebootToTui,
            ),
          IconButton(
            tooltip: 'Acerca de',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'Herrero',
              applicationVersion: '4.3.0',
              children: const [
                Text('Predimensionado de estructuras metálicas según CTE DB-SE-A y Eurocódigo 3, '
                    'con despiece, soldaduras, planos tipo CAD (PDF y DXF), modelo 3D para SketchUp, '
                    'render, lectura de planos y croquis y comprensión de la petición con IA local, '
                    'gestor de proyectos y presupuesto con precios de tus facturas y distribuidores cercanos.\n\n'
                    'Datos de distribuidores: © colaboradores de OpenStreetMap (ODbL).\n\n'
                    'Los resultados son orientativos y deben ser validados por un técnico competente.'),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('¿Qué estructura necesitas?', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text('Indica tipo, medidas (largo x ancho), altura, cubierta/uso, material y ubicación. Puedes fijar perfiles por partes: «pilares HEB 220, correas de tubo».',
                    style: TextStyle(color: cs.onSurfaceVariant)),
                const SizedBox(height: 12),
                TextField(
                  controller: _ctrl,
                  minLines: 3,
                  maxLines: 6,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: 'Ej.: Nave a dos aguas de 20 x 12 m, 5 m al alero, pórticos cada 5 m, en Madrid',
                  ),
                ),
                if (_suggestions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SingleChildScrollView(
                      key: const ValueKey('autocompletar'),
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        Icon(Icons.auto_awesome, size: 18, color: cs.primary),
                        const SizedBox(width: 6),
                        for (final sg in _suggestions)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              visualDensity: VisualDensity.compact,
                              label: Text(sg.label),
                              onPressed: () => _accept(sg),
                            ),
                          ),
                      ]),
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _run(),
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.calculate),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Calcular estructura', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PlanImportScreen())),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Importar plano (PDF o imagen)'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _go(const ProjectsScreen()),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Proyectos guardados'),
                ),
                if (_projects.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Últimos proyectos', style: Theme.of(context).textTheme.titleMedium),
                  for (final p in _projects)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.construction),
                      title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text([if (p.client.isNotEmpty) p.client, p.status.label].join(' · ')),
                      onTap: () async {
                        await openProject(context, p.id);
                        ModelGate.instance.enter(WorkflowStep.inicio);
                        _loadProjects();
                      },
                    ),
                ],
                const SizedBox(height: 20),
                Text('Ejemplos', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in examples)
                      ActionChip(
                        label: Text(e, maxLines: 2, overflow: TextOverflow.ellipsis),
                        onPressed: () {
                          _ctrl.text = e;
                          _run(e);
                        },
                      ),
                  ],
                ),
                if (_history.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Recientes', style: Theme.of(context).textTheme.titleMedium),
                  for (final h in _history)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.history),
                      title: Text(h, maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () {
                        _ctrl.text = h;
                        _run(h);
                      },
                    ),
                ],
                const SizedBox(height: 20),
                Card(
                  color: cs.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Icon(Icons.warning_amber, color: cs.onErrorContainer),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Predimensionado orientativo según CTE DB-SE-A / EC3. No sustituye al proyecto: '
                          'debe revisarlo y firmarlo un técnico competente antes de fabricar o montar.',
                          style: TextStyle(color: cs.onErrorContainer, fontSize: 12),
                        ),
                      ),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
