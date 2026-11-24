import 'package:material_ui/material_ui.dart';

import '../engine/designer.dart';
import '../services/export.dart';
import '../services/price_store.dart';
import '../services/project_store.dart';
import 'budget_tab.dart' show eur;
import 'project_screen.dart';

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Abre un proyecto guardado (recalcula el diseño con el motor actual).
Future<void> openProject(BuildContext context, String id) async {
  final st = await projectStore();
  final r = st.load(id);
  if (r == null || !context.mounted) return;
  final d = designFromSpec(r.spec, r.prompt);
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProjectScreen(design: d, record: r)));
}

/// Gestor de proyectos: lista, búsqueda, estado, duplicar, borrar e historial.
class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});
  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  ProjectStore? _st;
  String _q = '';
  ProjectStatus? _status;

  @override
  void initState() {
    super.initState();
    projectStore().then((s) => mounted ? setState(() => _st = s) : null);
  }

  Future<void> _open(ProjectSummary p) async {
    await openProject(context, p.id);
    if (mounted) setState(() {});
  }

  Future<void> _menu(ProjectSummary p, String v) async {
    final st = _st!;
    switch (v) {
      case 'dup':
        final c = st.duplicate(p.id);
        if (c != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Creado «${c.name}»')));
        }
      case 'edit':
        final r = st.load(p.id);
        if (r != null && mounted && await editProjectInfo(context, r)) {
          r.log('Datos del proyecto editados');
          st.save(r);
        }
      case 'hist':
        final r = st.load(p.id);
        if (r != null && mounted) await _history(r);
      case 'del':
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('¿Borrar el proyecto?'),
            content: Text('Se borrará «${p.name}» con su historial y su foto. No se puede deshacer.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Borrar')),
            ],
          ),
        );
        if (ok == true) st.delete(p.id);
    }
    if (mounted) setState(() {});
  }

  Future<void> _history(ProjectRecord r) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (c) => ListView(padding: const EdgeInsets.all(12), children: [
          Text('Historial de «${r.name}»', style: Theme.of(c).textTheme.titleMedium),
          for (final h in r.history.reversed)
            ListTile(dense: true, leading: const Icon(Icons.history, size: 18), title: Text(h.text), subtitle: Text(_date(h.at))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final st = _st;
    final cs = Theme.of(context).colorScheme;
    final items = st == null ? const <ProjectSummary>[] : [for (final p in st.search(_q)) if (_status == null || p.status == _status) p];
    return Scaffold(
      appBar: AppBar(title: const Text('Proyectos')),
      body: st == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: ListView(padding: const EdgeInsets.all(12), children: [
                  TextField(
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por nombre, cliente o tipo', isDense: true),
                    onChanged: (v) => setState(() => _q = v),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(label: const Text('Todos'), selected: _status == null, onSelected: (_) => setState(() => _status = null)),
                      ),
                      for (final s in ProjectStatus.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(label: Text(s.label), selected: _status == s, onSelected: (_) => setState(() => _status = s)),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                          st.list().isEmpty
                              ? 'Todavía no hay proyectos guardados. Calcula una estructura y pulsa el disquete para guardarla.'
                              : 'Ningún proyecto coincide.',
                          textAlign: TextAlign.center),
                    ),
                  for (final p in items)
                    Card(
                      child: ListTile(
                        onTap: () => _open(p),
                        leading: CircleAvatar(backgroundColor: cs.primaryContainer, child: Icon(Icons.construction, color: cs.onPrimaryContainer)),
                        title: Text(p.name),
                        subtitle: Text([
                          if (p.client.isNotEmpty) p.client,
                          '${p.type}${p.dims.isEmpty ? '' : ' · ${p.dims}'}',
                          '${p.kg.toStringAsFixed(0)} kg${p.budget == null ? '' : ' · ${eur(p.budget!)} + IVA'}',
                          '${p.status.label} · ${_date(p.updated)}',
                        ].join('\n')),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) => _menu(p, v),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit), title: Text('Datos y estado'))),
                            PopupMenuItem(value: 'dup', child: ListTile(leading: Icon(Icons.copy), title: Text('Duplicar'))),
                            PopupMenuItem(value: 'hist', child: ListTile(leading: Icon(Icons.history), title: Text('Historial'))),
                            PopupMenuItem(value: 'del', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Borrar'))),
                          ],
                        ),
                      ),
                    ),
                ]),
              ),
            ),
    );
  }
}

/// Diálogo con nombre, cliente, obra, estado y notas. Devuelve si se aceptó.
Future<bool> editProjectInfo(BuildContext context, ProjectRecord r, {String title = 'Datos del proyecto'}) async {
  final name = TextEditingController(text: r.name);
  final client = TextEditingController(text: r.client);
  final site = TextEditingController(text: r.site);
  final notes = TextEditingController(text: r.notes);
  var status = r.status;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre del proyecto')),
            const SizedBox(height: 8),
            TextField(controller: client, decoration: const InputDecoration(labelText: 'Cliente')),
            const SizedBox(height: 8),
            TextField(controller: site, decoration: const InputDecoration(labelText: 'Obra (dirección o población)')),
            const SizedBox(height: 8),
            DropdownButtonFormField<ProjectStatus>(
              initialValue: status,
              decoration: const InputDecoration(labelText: 'Estado'),
              items: [for (final s in ProjectStatus.values) DropdownMenuItem(value: s, child: Text(s.label))],
              onChanged: (s) => set(() => status = s ?? status),
            ),
            const SizedBox(height: 8),
            TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Notas')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar')),
        ],
      ),
    ),
  );
  if (ok != true) return false;
  if (status != r.status) r.log('Estado: ${r.status.label} → ${status.label}');
  r
    ..name = name.text.trim().isEmpty ? r.name : name.text.trim()
    ..client = client.text.trim()
    ..site = site.text.trim()
    ..notes = notes.text.trim()
    ..status = status;
  return true;
}

/// Elegir apartados para imprimir: (apartados, un PDF por apartado, presupuesto con detalle de precios).
Future<(List<ProjectSection>, bool, bool)?> pickSections(BuildContext context, {bool hasBudget = false}) async {
  final sel = <ProjectSection>{
    for (final s in ProjectSection.values)
      if (s != ProjectSection.presupuesto) s
  };
  var separate = true;
  var detail = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('Apartados del proyecto'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final s in ProjectSection.values)
              CheckboxListTile(
                dense: true,
                value: sel.contains(s),
                onChanged: s == ProjectSection.presupuesto && !hasBudget
                    ? null
                    : (v) => set(() => v == true ? sel.add(s) : sel.remove(s)),
                title: Text(s.label),
                subtitle: Text(s == ProjectSection.presupuesto && !hasBudget ? 'Abre antes la pestaña Presupuesto' : 'Para: ${s.recipient}'),
              ),
            const Divider(),
            SwitchListTile(
              dense: true,
              value: separate,
              onChanged: (v) => set(() => separate = v),
              title: const Text('Un PDF por apartado'),
              subtitle: const Text('Para dar a cada uno solo su parte'),
            ),
            if (sel.contains(ProjectSection.presupuesto))
              SwitchListTile(
                dense: true,
                value: detail,
                onChanged: (v) => set(() => detail = v),
                title: const Text('Presupuesto con precios unitarios y su origen'),
                subtitle: const Text('Desactivado: versión para el cliente'),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: sel.isEmpty ? null : () => Navigator.pop(c, true), child: const Text('Exportar')),
        ],
      ),
    ),
  );
  if (ok != true) return null;
  return ([for (final s in ProjectSection.values) if (sel.contains(s)) s], separate, detail);
}
