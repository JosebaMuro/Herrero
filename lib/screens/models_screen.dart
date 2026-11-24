import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../ai/accel.dart';
import '../ai/engine_plan.dart';
import '../ai/model_import.dart';
import '../ai/model_gate.dart';
import '../ai/model_manager.dart';
import '../ai/onnx_inspect.dart';

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
      _catalogError = mgr.manifests.isEmpty
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
      _snack(switch (m.task) {
        ModelTask.understand || ModelTask.reason =>
          '«${m.name}» listo. La app entenderá mejor tus peticiones, sin conexión.',
        ModelTask.photo => '«${m.name}» listo. Ya puedes generar fotos sin conexión.',
        ModelTask.plans => '«${m.name}» listo. Ya puedes importar planos escaneados y fotos sin conexión.',
        ModelTask.sketch => '«${m.name}» listo. Ya puedes interpretar croquis sin conexión.',
      });
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

  bool _importing = false;

  /// Importa ficheros de modelo descargados por el usuario. [only]: para una variante.
  Future<void> _import({ModelVariant? only}) async {
    if (_importing) return;
    final picked = await FilePicker.pickFiles(
      dialogTitle: only == null ? 'Elige los ficheros del modelo (.onnx, .json, .txt)' : 'Ficheros de «${only.name}»',
    );
    if (picked.isEmpty || !mounted) return;
    setState(() => _importing = true);
    final results = <(String, String, bool)>[]; // (fichero, mensaje, correcto)
    final staged = <File>[];
    final progress = ValueNotifier<String>('Preparando…');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        content: Row(children: [
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(width: 16),
          Expanded(child: ValueListenableBuilder(valueListenable: progress, builder: (_, v, _) => Text(v))),
        ]),
      ),
    );
    try {
      for (final f in picked) {
        // ruta directa (PC) o copia temporal (Android, que entrega content://)
        var path = f.path;
        var move = false;
        if (path == null || !File(path).existsSync()) {
          progress.value = 'Copiando ${f.name}…';
          final tmp = File('${(await mgr.importStaging()).path}${Platform.pathSeparator}${f.name}');
          final sink = tmp.openWrite();
          await sink.addStream(f.xFile.openRead());
          await sink.close();
          staged.add(tmp);
          path = tmp.path;
          move = true;
        }
        progress.value = 'Reconociendo ${f.name}…';
        final info = sniff(path);
        var cands = candidatesFor(f.name, info, only: only);
        if (cands.isEmpty) {
          final why = ortCompatibilityProblems(info);
          results.add((
            f.name,
            info.format != ModelFormat.onnx && why.isNotEmpty && !f.name.toLowerCase().endsWith('.json') &&
                    !f.name.toLowerCase().endsWith('.txt')
                ? why.first
                : 'No corresponde a ningún fichero de ${only == null ? 'los modelos de Herrero' : '«${only.name}»'}.',
            false
          ));
          continue;
        }
        ImportTarget? target = cands.length == 1 ? cands.first : null;
        if (target == null) {
          if (mounted) Navigator.of(context).pop();
          target = await _chooseTarget(f.name, cands);
          if (mounted) {
            showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (c) => AlertDialog(
                content: Row(children: [
                  const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
                  const SizedBox(width: 16),
                  Expanded(child: ValueListenableBuilder(valueListenable: progress, builder: (_, v, _) => Text(v))),
                ]),
              ),
            );
          }
          if (target == null) {
            results.add((f.name, 'Sin importar (cancelado).', false));
            continue;
          }
        }
        progress.value = 'Comprobando ${f.name} (integridad y compatibilidad)…';
        final (sha, size) = mgr.officialOf(target);
        final check = await checkImport(path, target, officialSha: sha, officialSize: size);
        if (!check.ok) {
          results.add((f.name, check.errors.join(' '), false));
          continue;
        }
        if (check.warnings.isNotEmpty && sha != null && check.sha256 != sha) {
          if (mounted) Navigator.of(context).pop();
          final go = await _confirmUnofficial(f.name, target, check);
          if (mounted) {
            showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (c) => AlertDialog(
                content: Row(children: [
                  const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
                  const SizedBox(width: 16),
                  Expanded(child: ValueListenableBuilder(valueListenable: progress, builder: (_, v, _) => Text(v))),
                ]),
              ),
            );
          }
          if (go != true) {
            results.add((f.name, 'Sin importar (no es el oficial).', false));
            continue;
          }
        }
        progress.value = 'Instalando ${f.name}…';
        await mgr.installImported(target, check, f.name, move: move);
        final official = sha != null && check.sha256 == sha;
        results.add((
          f.name,
          '→ ${target.label}. ${official ? 'Idéntico al oficial (SHA-256 comprobado).' : check.warnings.join(' ')}'
              '${check.info.format == ModelFormat.onnx ? ' ONNX IR ${check.info.irVersion}, opset ${check.info.onnxOpset}.' : ''}',
          true
        ));
      }
    } catch (e) {
      results.add(('', ModelManager.friendlyDownloadError(e), false));
    } finally {
      for (final t in staged) {
        try {
          if (t.existsSync()) t.deleteSync();
        } catch (_) {}
      }
      if (mounted) Navigator.of(context).pop();
      progress.dispose();
      if (mounted) setState(() => _importing = false);
    }
    if (!mounted) return;
    // qué falta para completar cada modelo tocado
    final touched = {
      for (final m in catalog)
        if (results.any((r) => r.$3 && r.$2.contains(m.name))) m,
    };
    final pending = <String>[];
    for (final m in touched) {
      final miss = await mgr.missingFiles(m);
      pending.add(miss.isEmpty ? '«${m.name}» está completo y listo.' : '«${m.name}»: faltan ${miss.join(', ')}.');
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Importar modelo'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final r in results)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(r.$3 ? Icons.check_circle : Icons.error_outline,
                    color: r.$3 ? Colors.green.shade700 : Theme.of(c).colorScheme.error),
                title: Text(r.$1.isEmpty ? 'Error' : r.$1),
                subtitle: Text(r.$2),
              ),
            if (pending.isNotEmpty) ...[
              const Divider(),
              for (final p in pending) Padding(padding: const EdgeInsets.only(top: 4), child: Text(p)),
            ],
          ]),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Aceptar'))],
      ),
    );
  }

  Future<ImportTarget?> _chooseTarget(String name, List<ImportTarget> cands) => showDialog<ImportTarget>(
        context: context,
        builder: (c) => SimpleDialog(
          title: Text('¿A qué modelo pertenece «$name»?'),
          children: [
            for (final t in cands)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(c, t),
                child: Text(t.label),
              ),
            SimpleDialogOption(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          ],
        ),
      );

  Future<bool?> _confirmUnofficial(String name, ImportTarget t, ImportCheck c) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('No es el fichero oficial'),
          content: Text('«$name» es un modelo ONNX válido y la app puede abrirlo como «${t.label}», pero no es '
              'idéntico al que publica Herrero (${fmtBytes(c.size)}). Puede ser otra versión o una conversión '
              'distinta: funcionará, aunque los resultados pueden cambiar.\n\n¿Importarlo igualmente?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Importar')),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modelos de IA local'),
        actions: [
          IconButton(
            tooltip: 'Importar un modelo descargado',
            onPressed: _importing ? null : () => _import(),
            icon: const Icon(Icons.file_open_outlined),
          ),
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
              Card(
                child: ListTile(
                  leading: const Icon(Icons.memory),
                  title: const Text('Carga de modelos'),
                  subtitle: Text(ModelGate.instance.saving
                      ? 'Por turnos: un modelo cada vez, según el paso (ficha, planos, foto, facturas)'
                      : 'Varios modelos a la vez'),
                  trailing: DropdownButton<MemoryMode>(
                    value: ModelGate.instance.mode,
                    items: [for (final m in MemoryMode.values) DropdownMenuItem(value: m, child: Text(m.label))],
                    onChanged: (m) async {
                      if (m == null) return;
                      await ModelGate.instance.setMode(m);
                      setState(() {});
                    },
                  ),
                ),
              ),
              if (_catalogError != null)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: ListTile(leading: const Icon(Icons.cloud_off), title: Text(_catalogError!)),
                ),
              const SizedBox(height: 8),
              _InstalledCard(onRemove: _remove, onImport: () => _import()),
              const SizedBox(height: 8),
              const _TaskEngineCard(),
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
                    onImport: () => _import(only: m),
                  ),
              ],
              const SizedBox(height: 8),
              const _AccelCard(),
              const SizedBox(height: 8),
              _SettingsCard(dev: dev),
              const SizedBox(height: 12),
              Text(
                'Los modelos se ejecutan en tu dispositivo: las imágenes no salen de él. '
                'Basados en SD-Turbo (Stability AI; revisa su licencia antes de un uso comercial), TAESD (MIT) '
                'PP-OCRv4 de PaddleOCR (Apache-2.0), SmolVLM de Hugging Face (Apache-2.0), multilingual-e5-small '
                '(MIT) y Qwen3 (Apache-2.0), en formato ONNX '
                'para funcionar en CPU, NPU o GPU.',
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
                label: Text(Platform.isAndroid
                    ? 'CPU + NPU/GPU (NNAPI)'
                    : (GpuPacks.instance.gpus.isEmpty
                        ? 'CPU (${dev.recommendedThreads} hilos)'
                        : GpuPacks.instance.gpus.join(' · ')))),
          ]),
          if (ModelManager.instance.hardware != null) ...[
            const SizedBox(height: 8),
            Text('Detectado: ${ModelManager.instance.hardware!.summary}', style: Theme.of(context).textTheme.bodySmall),
          ],
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
      (Icons.document_scanner_outlined, 'Importar plano (PDF de CAD)', 'Lectura directa del PDF · sin modelo'),
      (Icons.image_search, 'Importar plano (foto o escaneo)', 'Lector OCR local · requiere descargar 16 MB'),
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
  final VoidCallback onImport;
  const _VariantCard(
      {required this.m,
      required this.recommended,
      required this.onDownload,
      required this.onRemove,
      required this.onImport});

  @override
  Widget build(BuildContext context) {
    final mgr = ModelManager.instance;
    final dev = mgr.device!;
    final st = mgr.status[m.id] ?? ModelStatus(DlState.notInstalled);
    final cs = Theme.of(context).colorScheme;
    final size = mgr.sizeOf(m) > 0 ? fmtBytes(mgr.sizeOf(m)) : '≈ ${fmtBytes(m.approxBytes)}';
    final suit = dev.suitability(m);
    final active = st.state == DlState.installed && mgr.activeFor(m.task)?.id == m.id;
    final imported = mgr.importedFiles(m);
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
                  trailing: Text(fmtBytes(mgr.fileSize(m, p.$2))),
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
                Flexible(
                  child: Text([
                    active ? 'Instalado · en uso' : 'Instalado',
                    if (imported.isNotEmpty) imported.values.every((o) => o) ? 'importado' : 'importado (no oficial)',
                  ].join(' · ')),
                ),
                const Spacer(),
                if (!active)
                  TextButton(
                    onPressed: () => mgr.activate(m),
                    child: const Text('Usar'),
                  ),
                IconButton(tooltip: 'Eliminar', onPressed: onRemove, icon: const Icon(Icons.delete_outline)),
              ] else ...[
                if (st.state == DlState.error)
                  Expanded(
                      child: Text(st.error ?? 'Error', style: TextStyle(color: cs.error, fontSize: 12)))
                else
                  const Spacer(),
                TextButton(onPressed: onImport, child: const Text('Importar')),
                FilledButton.icon(
                  onPressed: st.state == DlState.error && (st.error ?? '').contains('no publicada') ? null : onDownload,
                  icon: const Icon(Icons.download),
                  label: Text(st.bytesDone > 0 || (mgr.partialBytes[m.id] ?? 0) > 0 ? 'Reanudar' : 'Descargar'),
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
        ]),
      ),
    );
  }
}

/// Aceleración de toda la IA local: motor (CPU, GPU, NPU) y paquetes opcionales.
class _AccelCard extends StatefulWidget {
  const _AccelCard();
  @override
  State<_AccelCard> createState() => _AccelCardState();
}

class _AccelCardState extends State<_AccelCard> {
  final mgr = ModelManager.instance;
  final packs = GpuPacks.instance;

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _install(GpuPack p) async {
    final size = packs.sizeOf(p);
    final dev = mgr.device;
    if (dev != null && dev.freeDiskGb > 0 && dev.freeDiskGb * 1e9 < size * 2.2) {
      _snack('No hay espacio suficiente: la descarga ocupa ${fmtBytes(size)} y se necesita otro tanto al '
          'descomprimir.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Descargar «${p.name}»'),
        content: Text('${p.summary}\n\nDescarga: ${fmtBytes(size)}. Se guarda aparte del programa y se puede '
            'borrar cuando quieras.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Descargar')),
        ],
      ),
    );
    if (ok != true) return;
    await packs.install(p);
    final st = packs.status[p.id];
    if (st?.state == DlState.installed) {
      if (mgr.engine != AiEngine.auto) mgr.engine = p.engine;
      await mgr.savePrefs();
      _snack('«${p.name}» instalado. Reinicia Herrero para usarlo.');
    } else if (st?.state == DlState.error) {
      _snack(st!.error ?? 'Error en la descarga');
    }
  }

  Future<void> _remove(GpuPack p) async {
    final err = await packs.remove(p);
    if (err != null) {
      _snack(err);
    } else {
      await mgr.savePrefs();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: packs,
      builder: (context, _) {
        final restart = Platform.isWindows && packs.needsRestart(mgr.engine);
        final missing = switch (mgr.engine) {
          AiEngine.cuda => !packs.installed('cuda'),
          AiEngine.openvino => !packs.installed('openvino'),
          _ => false,
        };
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Aceleración de la IA (CPU, GPU o NPU)', style: t.titleMedium),
              const SizedBox(height: 4),
              Text('Se aplica a todos los modelos. Si la aceleración no admite un modelo o falla, '
                  'ese paso se hace en la CPU automáticamente.', style: t.bodySmall),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final e in enginesForPlatform())
                  ChoiceChip(
                    label: Text(e.label),
                    selected: mgr.engine == e,
                    onSelected: (_) async {
                      mgr.engine = e;
                      await mgr.savePrefs();
                      if (mounted) setState(() {});
                    },
                  ),
              ]),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(mgr.engine.help, style: t.bodySmall),
              ),
              if (missing)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Descarga su paquete aquí abajo; mientras tanto se usa DirectML o la CPU.',
                      style: t.bodySmall?.copyWith(color: cs.error)),
                ),
              if (restart)
                Card(
                  color: cs.tertiaryContainer,
                  margin: const EdgeInsets.only(top: 10),
                  child: const ListTile(
                    leading: Icon(Icons.restart_alt),
                    title: Text('Reinicia Herrero para cambiar de motor'),
                    subtitle: Text('La IA ya se ha usado en esta sesión con otro motor.'),
                  ),
                ),
              if (Platform.isWindows) ...[
                const SizedBox(height: 14),
                Text('Paquetes opcionales', style: t.labelLarge),
                const SizedBox(height: 4),
                for (final p in gpuPacks) _packTile(p),
                const SizedBox(height: 8),
                Text(
                  'AMD: ROCm y MIGraphX solo existen para Linux en ONNX Runtime, así que en Windows las gráficas '
                  'AMD (Radeon) usan DirectML. Vulkan no es un motor de ONNX Runtime; DirectML cumple ese papel '
                  'en Windows con cualquier gráfica.',
                  style: t.bodySmall,
                ),
              ],
              if (Platform.isAndroid) ...[
                const SizedBox(height: 8),
                Text(
                  'En Android la GPU y la NPU se usan a través de NNAPI (lo que ofrece el fabricante del móvil). '
                  'ONNX Runtime no tiene motor Vulkan; XNNPACK acelera la CPU.',
                  style: t.bodySmall,
                ),
              ],
            ]),
          ),
        );
      },
    );
  }

  Widget _packTile(GpuPack p) {
    final st = packs.status[p.id] ?? ModelStatus(DlState.notInstalled);
    final size = packs.sizeOf(p);
    final fit = switch (p.id) {
      'cuda' => hasNvidia(packs.gpus),
      'openvino' => hasIntelGpu(packs.gpus),
      _ => true,
    };
    Widget trailing;
    switch (st.state) {
      case DlState.downloading:
      case DlState.verifying:
        trailing = IconButton(
            tooltip: 'Cancelar', onPressed: () => packs.cancel(p.id), icon: const Icon(Icons.close));
      case DlState.installed:
        trailing = IconButton(
            tooltip: 'Borrar', onPressed: () => _remove(p), icon: const Icon(Icons.delete_outline));
      default:
        trailing = IconButton(
            tooltip: 'Descargar', onPressed: () => _install(p), icon: const Icon(Icons.download));
    }
    final sub = switch (st.state) {
      DlState.installed => 'Instalado',
      DlState.downloading =>
        'Descargando ${(st.progress * 100).toStringAsFixed(0)} % de ${fmtBytes(st.bytesTotal)}',
      DlState.verifying => 'Comprobando y descomprimiendo…',
      DlState.error => st.error ?? 'Error',
      DlState.notInstalled => '${fmtBytes(size)} · ${fit ? 'compatible con tu gráfica' : 'no se ha detectado esa gráfica'}',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.memory, color: fit ? null : Theme.of(context).disabledColor),
        title: Text(p.name),
        subtitle: Text(sub),
        trailing: trailing,
      ),
      if (st.state == DlState.downloading) LinearProgressIndicator(value: st.progress),
    ]);
  }
}


/// Modelos instalados en el dispositivo: espacio, cuál se usa, con qué motor, y borrar.
class _InstalledCard extends StatelessWidget {
  final Future<void> Function(ModelVariant) onRemove;
  final VoidCallback onImport;
  const _InstalledCard({required this.onRemove, required this.onImport});

  @override
  Widget build(BuildContext context) {
    final mgr = ModelManager.instance;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final installed = catalog.where((m) => mgr.status[m.id]?.state == DlState.installed).toList();
    final partial = catalog
        .where((m) => mgr.status[m.id]?.state != DlState.installed && (mgr.partialBytes[m.id] ?? 0) > 0)
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Instalados en este ${mgr.device?.isMobile == true ? 'móvil' : 'equipo'}', style: t.titleMedium)),
            Text(fmtBytes(mgr.totalDiskBytes), style: t.labelLarge),
          ]),
          const SizedBox(height: 4),
          if (installed.isEmpty)
            Text('Todavía no hay modelos. Descárgalos más abajo o importa los que ya tengas descargados.',
                style: t.bodySmall),
          for (final m in installed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                mgr.activeFor(m.task)?.id == m.id ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: mgr.activeFor(m.task)?.id == m.id ? cs.primary : null,
              ),
              title: Text(m.name),
              subtitle: Text([
                fmtBytes(mgr.diskBytes[m.id] ?? 0),
                mgr.activeFor(m.task)?.id == m.id ? 'en uso' : 'sin usar',
                mgr.decision(m.task).runsOn,
                if (mgr.importedFiles(m).isNotEmpty)
                  mgr.importedFiles(m).values.every((o) => o) ? 'importado' : 'importado, no oficial',
              ].join(' · ')),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (ModelManager.hasChoice(m.task) && mgr.activeFor(m.task)?.id != m.id)
                  TextButton(onPressed: () => mgr.activate(m), child: const Text('Usar')),
                IconButton(
                    tooltip: 'Eliminar', onPressed: () => onRemove(m), icon: const Icon(Icons.delete_outline)),
              ]),
            ),
          for (final m in partial)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.downloading),
              title: Text(m.name),
              subtitle: Text('Descarga a medias: ${fmtBytes(mgr.partialBytes[m.id] ?? 0)} de '
                  '${fmtBytes(mgr.sizeOf(m) > 0 ? mgr.sizeOf(m) : m.approxBytes)}. Pulsa «Reanudar» en su ficha.'),
              trailing: IconButton(
                  tooltip: 'Borrar lo descargado', onPressed: () => onRemove(m), icon: const Icon(Icons.delete_outline)),
            ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Importar un modelo descargado'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Si has bajado los ficheros por tu cuenta (desde el ordenador, la web de GitHub o un pendrive), '
              'elígelos aquí: la app reconoce a qué modelo pertenecen, comprueba que son ONNX compatibles con su '
              'motor y si son idénticos a los oficiales, y los instala sin descargar nada.',
              style: t.bodySmall,
            ),
          ),
        ]),
      ),
    );
  }
}

/// Motor de cada tarea: el elegido automáticamente según el hardware, o uno fijado a mano.
class _TaskEngineCard extends StatelessWidget {
  const _TaskEngineCard();

  @override
  Widget build(BuildContext context) {
    final mgr = ModelManager.instance;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final tips = {for (final task in ModelTask.values) mgr.decision(task).tip}..remove('');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Motor de cada tarea', style: t.titleMedium),
          const SizedBox(height: 4),
          Text('Herrero elige el motor según tu hardware. Puedes fijarlo a mano para una tarea si en tu '
              '${mgr.device?.isMobile == true ? 'móvil' : 'equipo'} va mejor otro.', style: t.bodySmall),
          for (final task in ModelTask.values) _row(context, mgr, task),
          for (final tip in tips)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.tips_and_updates_outlined, size: 18, color: cs.tertiary),
                const SizedBox(width: 6),
                Expanded(child: Text(tip, style: t.bodySmall)),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _row(BuildContext context, ModelManager mgr, ModelTask task) {
    final d = mgr.decision(task);
    final override = mgr.taskEngine[task];
    final short = task.label.split(' (').first;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(short, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('${d.runsOn} · ${d.reason}', style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
        const SizedBox(width: 8),
        DropdownButton<AiEngine?>(
          value: override,
          isDense: true,
          underline: const SizedBox.shrink(),
          items: [
            DropdownMenuItem<AiEngine?>(
                value: null, child: Text(mgr.engine == AiEngine.auto ? 'Automático' : 'Como el general')),
            for (final e in taskEngineChoices()) DropdownMenuItem<AiEngine?>(value: e, child: Text(e.label)),
          ],
          onChanged: (e) => mgr.setTaskEngine(task, e),
        ),
      ]),
    );
  }
}
