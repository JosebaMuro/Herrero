import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/designer.dart';
import 'project_screen.dart';

const examples = [
  'Nave a dos aguas de 30 x 15 m, 6 m de altura al alero, pórticos cada 6 m, panel sándwich, en Vitoria',
  'Marquesina para 2 coches de 5,5 x 5 m y 2,4 m de alto, chapa grecada, galvanizada',
  'Altillo de 8 x 4 m a 3 m de altura para almacén, suelo de tramex',
  'Pérgola de 4 x 3 m sin cubierta, lacada en negro',
  'Taller de 20 x 12 m, 5 m al alero, pendiente 15 %, en León',
  'Entreplanta de oficinas de 12 x 9 m a 3,2 m, chapa colaborante',
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

  @override
  void initState() {
    super.initState();
    _loadHistory();
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
      final d = designFromPrompt(p);
      await _saveHistory(p);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProjectScreen(design: d)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo calcular: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
          Text('Herrero · Oficina técnica'),
        ]),
        actions: [
          IconButton(
            tooltip: 'Acerca de',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'Herrero',
              applicationVersion: '1.0',
              children: const [
                Text('Predimensionado de estructuras metálicas según CTE DB-SE-A y Eurocódigo 3, '
                    'con despiece, soldaduras, planos de montaje y render.\n\n'
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
                Text('Indica tipo, medidas (largo x ancho), altura, cubierta/uso y ubicación.',
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
