import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../ai/model_manager.dart';
import '../ai/sd_pipeline.dart';

/// Gestor de modelos de IA local: qué pasos usan IA, qué modelo conviene a
/// este equipo, descarga reanudable y ajustes de ejecución.
class ModelsScreen extends StatefulWidget {
  const ModelsScreen({super.key});
  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  final mgr = ModelManager.instance;
  String? _catalogError;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await mgr.load();
    await _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _refreshing = true;
      _catalogError = null;
    });
    try {
      await mgr.fetchManifest();
    } catch (e) {
      _catalogError = mgr.manifest == null
          ? 'Sin conexión con el catálogo de modelos. Conéctate a internet para descargar (después funciona sin conexión).'
          : null;
    }
    if (mounted) setState(() => _refreshing = false);
  }

  Future<void> _download(ModelVariant m) async {
    final dev = mgr.device;
    final need = mgr.sizeOf(m) > 0 ? mgr.sizeOf(m) : m.approxBytes;
    if (dev != null && dev.freeDiskGb > 0 && dev.freeDiskGb * 1e9 < need * 1.1) {
      _snack('No hay espacio suficiente: hacen falta ${fmtBytes(need)} y quedan '
          '${dev.freeDiskGb.toStringAsFixed(1).replaceAll('.', ',')} GB libres.');
      return;
    }
    if (dev != null && !dev.fits(m)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('No recomendado para este equipo'),
          content: Text('${dev.suitability(m)}. Puede ir muy lento o cerrarse por falta de memoria. '
              'Te recomendamos «${dev.recommended(m.task).name}». ¿Descargar igualmente?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Descargar')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await mgr.download(m);
    final st = mgr.status[m.id];
    if (st?.state == DlState.installed) {
      _snack('«${m.name}» listo. Ya puedes generar fotos sin conexión.');
    } else if (st?.state == DlState.error) {
      _snack(st!.error ?? 'Error en la descarga');
    }
  }

  Future<void> _remove(ModelVariant m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Eliminar «${m.name}»'),
        content: const Text('Se liberará el espacio. Los ficheros que use otro modelo instalado se conservan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok == true) await mgr.remove(m);
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modelos de IA local'),
        actions: [
          IconButton(
            tooltip: 'Actualizar catálogo',
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: mgr,
        builder: (context, _) {
          final dev = mgr.device;
          if (dev == null) return const Center(child: CircularProgressIndicator());
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _DeviceCard(dev: dev),
              if (_catalogError != null)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: ListTile(leading: const Icon(Icons.cloud_off), title: Text(_catalogError!)),
                ),
              const SizedBox(height: 8),
              const _StepsCard(),
              for (final task in ModelTask.values) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
                  child: Text(task.label, style: Theme.of(context).textTheme.titleMedium),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(task.description, style: Theme.of(context).textTheme.bodySmall),
                ),
                for (final m in catalog.where((m) => m.task == task))
                  _VariantCard(
                    m: m,
                    recommended: dev.recommended(task).id == m.id,
                    onDownload: () => _download(m),
                    onRemove: () => _remove(m),
                  ),
              ],
              const SizedBox(height: 8),
              _SettingsCard(dev: dev),
              const SizedBox(height: 12),
              Text(
                'Los modelos se ejecutan en tu dispositivo: las imágenes no salen de él. '
                'Basados en SD-Turbo (Stability AI; revisa su licencia antes de un uso comercial) y TAESD (MIT), '
                'convertidos a ONNX int8 para funcionar en CPU, NPU o GPU.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final DeviceProfile dev;
  const _DeviceCard({required this.dev});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rec = dev.recommended(ModelTask.photo);
    String gb(double v) => v <= 0 ? '—' : '${v.toStringAsFixed(1).replaceAll('.', ',')} GB';
    return Card(
      color: cs.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(dev.isMobile ? Icons.smartphone : Icons.computer, color: cs.onSecondaryContainer),
            const SizedBox(width: 10),
            Text('Tu ${dev.isMobile ? 'móvil' : 'equipo'} · ${dev.platform}',
                style: Theme.of(context).textTheme.titleMedium),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            Chip(avatar: const Icon(Icons.memory, size: 18), label: Text('RAM ${gb(dev.ramGb)}')),
            Chip(avatar: const Icon(Icons.developer_board, size: 18), label: Text('${dev.cores} núcleos')),
            Chip(avatar: const Icon(Icons.sd_storage, size: 18), label: Text('Libre ${gb(dev.freeDiskGb)}')),
            Chip(
                avatar: const Icon(Icons.bolt, size: 18),
                label: Text(Platform.isAndroid ? 'CPU + NPU/GPU (NNAPI)' : 'CPU (${dev.recommendedThreads} hilos)')),
          ]),
          const SizedBox(height: 10),
          Text.rich(TextSpan(children: [
            const TextSpan(text: 'Recomendado: ', style: TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: '${rec.name} a ${dev.recommendedSize} px. '),
            TextSpan(
                text: rec.tinyVae
                    ? 'Es el más equilibrado en memoria y velocidad para este dispositivo.'
                    : (rec.pcOnly
                        ? 'Tienes memoria de sobra: aprovecha la máxima calidad.'
                        : 'Buen equilibrio entre calidad y tiempo para tu memoria.')),
          ])),
        ]),
      ),
    );
  }
}

class _StepsCard extends StatelessWidget {
  const _StepsCard();
  @override
  Widget build(BuildContext context) {
    final rows = <(IconData, String, String)>[
      (Icons.text_fields, 'Interpretar la descripción', 'Motor propio por reglas · sin modelo'),
      (Icons.calculate_outlined, 'Cálculo, despiece y soldaduras', 'Motor propio CTE / EC3 · sin modelo'),
      (Icons.architecture, 'Isométrica, planos y render 3D', 'Dibujo propio · sin modelo'),
      (Icons.auto_awesome, 'Foto realista', 'IA local · requiere descargar un modelo'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(children: [
          const ListTile(
            dense: true,
            title: Text('Pasos de la app y modelos que usan', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          for (final r in rows)
            ListTile(
              dense: true,
              leading: Icon(r.$1),
              title: Text(r.$2),
              subtitle: Text(r.$3),
            ),
        ]),
      ),
    );
  }
}

class _VariantCard extends StatelessWidget {
  final ModelVariant m;
  final bool recommended;
  final VoidCallback onDownload;
  final VoidCallback onRemove;
  const _VariantCard(
      {required this.m, required this.recommended, required this.onDownload, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final mgr = ModelManager.instance;
    final dev = mgr.device!;
    final st = mgr.status[m.id] ?? ModelStatus(DlState.notInstalled);
    final cs = Theme.of(context).colorScheme;
    final size = mgr.sizeOf(m) > 0 ? fmtBytes(mgr.sizeOf(m)) : '≈ ${fmtBytes(m.approxBytes)}';
    final suit = dev.suitability(m);
    final active = mgr.activeId == m.id && st.state == DlState.installed;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: recommended ? cs.primary : cs.outlineVariant, width: recommended ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(m.name, style: Theme.of(context).textTheme.titleMedium)),
            if (recommended)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(20)),
                child: Text('Recomendado', style: TextStyle(color: cs.onPrimary, fontSize: 12)),
              ),
          ]),
          const SizedBox(height: 6),
          Text(m.summary),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: [
            _tag(context, Icons.download, size),
            _tag(context, Icons.memory, 'RAM ≥ ${m.minRamGb.toStringAsFixed(0)} GB'),
            _tag(context, Icons.high_quality, 'Calidad: ${m.quality}'),
            _tag(context, Icons.speed, 'Velocidad: ${m.speed}'),
          ]),
          const SizedBox(height: 6),
          Text(suit,
              style: TextStyle(
                  fontSize: 12,
                  color: dev.fits(m) ? (suit == 'Compatible' ? Colors.green.shade700 : Colors.orange.shade800) : cs.error)),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Qué incluye', style: TextStyle(fontSize: 13)),
            children: [
              for (final p in m.parts)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(p.$1),
                  subtitle: Text(p.$2),
                  trailing: Text(fmtBytes((mgr.manifest?['files']?[p.$2]?['size'] as int?) ?? 0)),
                ),
            ],
          ),
          if (st.state == DlState.downloading || st.state == DlState.verifying) ...[
            LinearProgressIndicator(value: st.state == DlState.verifying ? null : st.progress),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: Text(
                  st.state == DlState.verifying
                      ? 'Verificando integridad…'
                      : '${fmtBytes(st.bytesDone)} de ${fmtBytes(st.bytesTotal)} · ${(st.progress * 100).toStringAsFixed(0)} %',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              TextButton(onPressed: () => mgr.cancel(m.id), child: const Text('Pausar')),
            ]),
          ] else
            Row(children: [
              if (st.state == DlState.installed) ...[
                Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                const SizedBox(width: 6),
                Text(active ? 'Instalado · en uso' : 'Instalado'),
                const Spacer(),
                if (!active)
                  TextButton(
                    onPressed: () {
                      mgr.activeId = m.id;
                      mgr.savePrefs();
                    },
                    child: const Text('Usar'),
                  ),
                IconButton(tooltip: 'Eliminar', onPressed: onRemove, icon: const Icon(Icons.delete_outline)),
              ] else ...[
                if (st.state == DlState.error)
                  Expanded(
                      child: Text(st.error ?? 'Error', style: TextStyle(color: cs.error, fontSize: 12)))
                else
                  const Spacer(),
                FilledButton.icon(
                  onPressed: st.state == DlState.error && (st.error ?? '').contains('no publicada') ? null : onDownload,
                  icon: const Icon(Icons.download),
                  label: Text(st.bytesDone > 0 ? 'Reanudar' : 'Descargar'),
                ),
              ],
            ]),
        ]),
      ),
    );
  }

  Widget _tag(BuildContext context, IconData i, String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 14),
          const SizedBox(width: 4),
          Text(t, style: const TextStyle(fontSize: 12)),
        ]),
      );
}

class _SettingsCard extends StatelessWidget {
  final DeviceProfile dev;
  const _SettingsCard({required this.dev});
  @override
  Widget build(BuildContext context) {
    final mgr = ModelManager.instance;
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Ajustes de la foto IA', style: t.titleMedium),
          const SizedBox(height: 12),
          Text('Resolución', style: t.labelLarge),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 384, label: Text('384 px · rápida')),
              ButtonSegment(value: 512, label: Text('512 px · detalle')),
            ],
            selected: {mgr.size},
            onSelectionChanged: (v) {
              mgr.size = v.first;
              mgr.savePrefs();
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Recomendada para tu equipo: ${dev.recommendedSize} px', style: t.bodySmall),
          ),
          const SizedBox(height: 14),
          Text('Fidelidad al render', style: t.labelLarge),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            segments: [for (var i = 0; i < 3; i++) ButtonSegment(value: i, label: Text(fidelityLabels[i]))],
            selected: {mgr.fidelity},
            onSelectionChanged: (v) {
              mgr.fidelity = v.first;
              mgr.savePrefs();
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(fidelityHelp[mgr.fidelity], style: t.bodySmall),
          ),
          const SizedBox(height: 14),
          Text('Motor de cálculo', style: t.labelLarge),
          const SizedBox(height: 6),
          if (Platform.isAndroid) ...[
            SegmentedButton<AiEngine>(
              segments: [for (final e in AiEngine.values) ButtonSegment(value: e, label: Text(e.label))],
              selected: {mgr.engine},
              onSelectionChanged: (v) {
                mgr.engine = v.first;
                mgr.savePrefs();
              },
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(mgr.engine.help, style: t.bodySmall),
            ),
          ] else
            Text('En PC se usa la CPU con ${dev.recommendedThreads} hilos (optimizado AVX2 / int8).',
                style: t.bodyMedium),
        ]),
      ),
    );
  }
}
