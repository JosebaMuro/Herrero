import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../ai/model_manager.dart';
import '../ai/photo_prompt.dart';
import '../ai/sd_pipeline.dart';
import '../engine/model.dart';
import '../services/export.dart';
import '../views/render_view.dart';
import 'models_screen.dart';

/// Abre la foto IA. Devuelve el PNG elegido para la portada del PDF (o null).
Future<Uint8List?> openAiPhoto(BuildContext context,
    {required Design d,
    required Finish finish,
    required OrbitCamera cam,
    required double sun,
    required bool roof}) async {
  final mgr = ModelManager.instance;
  await mgr.load();
  if (!context.mounted) return null;
  if (!mgr.ready) {
    final rec = mgr.device?.recommended(ModelTask.photo);
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.auto_awesome),
        title: const Text('Descarga un modelo de IA'),
        content: Text('La foto realista se genera en tu dispositivo, sin internet. '
            'Antes hay que descargar un modelo una sola vez'
            '${rec != null ? ' (recomendado para ti: «${rec.name}», ≈ ${fmtBytes(rec.approxBytes)})' : ''}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Ahora no')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Abrir gestor de modelos')),
        ],
      ),
    );
    if (go != true || !context.mounted) return null;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ModelsScreen()));
    if (!mgr.ready || !context.mounted) return null;
  }
  return Navigator.of(context).push<Uint8List>(MaterialPageRoute(
      builder: (_) => AiPhotoScreen(d: d, finish: finish, cam: cam, sun: sun, roof: roof)));
}

class AiPhotoScreen extends StatefulWidget {
  final Design d;
  final Finish finish;
  final OrbitCamera cam;
  final double sun;
  final bool roof;
  const AiPhotoScreen(
      {super.key, required this.d, required this.finish, required this.cam, required this.sun, required this.roof});
  @override
  State<AiPhotoScreen> createState() => _AiPhotoScreenState();
}

class _AiPhotoScreenState extends State<AiPhotoScreen> {
  final mgr = ModelManager.instance;
  PhotoScene scene = PhotoScene.sunny;
  Uint8List? _renderPng;
  Uint8List? _renderRgba;
  Uint8List? _photoPng;
  SdJob? _job;
  SdProgress? _progress;
  String? _error;
  String? _info;
  int _seed = 0;
  double _split = 0.5;
  final _clock = Stopwatch();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _seed = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
    _prepare();
  }

  @override
  void dispose() {
    _job?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _prepare() async {
    final size = mgr.size;
    // Encuadre más cerrado que en el visor: cuanto más grande sale la estructura,
    // mejor conserva la IA los perfiles finos (a 384 px cada barrote son 1–2 píxeles).
    final c = widget.cam;
    final cam = OrbitCamera(yaw: c.yaw, pitch: c.pitch, distance: math.min(c.distance, 2.0));
    final (rgba, img) = await renderHq(widget.d, widget.finish, cam,
        width: size, height: size, ss: 2, sun: widget.sun, roof: widget.roof);
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    if (!mounted) return;
    setState(() {
      _renderRgba = rgba;
      _renderPng = bd!.buffer.asUint8List();
    });
  }

  Future<void> _generate() async {
    if (_renderRgba == null) return;
    setState(() {
      _error = null;
      _photoPng = null;
      _progress = const SdProgress(0, 'Preparando…');
    });
    _clock
      ..reset()
      ..start();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    try {
      final req = await mgr.buildRequest(
        prompt: photoPrompt(widget.d, widget.finish, scene, roof: widget.roof),
        initRgba: _renderRgba!,
        seed: _seed,
      );
      final job = startGeneration(req, (p) {
        if (mounted) setState(() => _progress = p);
      });
      _job = job;
      final res = await job.future;
      final png = await _rgbaToPng(res.rgba, res.size);
      if (!mounted) return;
      setState(() {
        _photoPng = png;
        _info = '${res.size} px · ${(res.elapsed.inMilliseconds / 1000).toStringAsFixed(0)} s · ${res.engineUsed}'
            ' · ${mgr.active?.name ?? ''}'
            '${res.breakdown.isEmpty ? '' : '\n${res.breakdown}'}';
      });
    } on SdCancelled {
      // cancelado por el usuario
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      _tick?.cancel();
      _clock.stop();
      _job = null;
      if (mounted) setState(() => _progress = null);
    }
  }

  Future<Uint8List> _rgbaToPng(Uint8List rgba, int size) async {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, size, size, ui.PixelFormat.rgba8888, c.complete);
    final img = await c.future;
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    return bd!.buffer.asUint8List();
  }

  Future<void> _save() async {
    if (_photoPng == null) return;
    try {
      final path = await exportPng(_photoPng!, widget.d, 'foto_ia');
      _snack('Foto guardada en $path');
    } catch (e) {
      _snack('No se pudo guardar: $e');
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final busy = _progress != null;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Foto realista (IA local)'),
        actions: [
          IconButton(
            tooltip: 'Modelos y ajustes',
            icon: const Icon(Icons.tune),
            onPressed: busy
                ? null
                : () async {
                    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ModelsScreen()));
                    _prepare();
                  },
          ),
        ],
      ),
      body: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth > 820;
        final viewer = _viewer(context);
        final controls = _controls(context, busy, cs);
        if (wide) {
          return Row(children: [
            Expanded(flex: 3, child: Padding(padding: const EdgeInsets.all(12), child: viewer)),
            SizedBox(width: 360, child: SingleChildScrollView(padding: const EdgeInsets.all(12), child: controls)),
          ]);
        }
        return ListView(padding: const EdgeInsets.all(12), children: [viewer, const SizedBox(height: 12), controls]);
      }),
    );
  }

  Widget _viewer(BuildContext context) {
    final before = _renderPng;
    final after = _photoPng;
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: Colors.black12,
          child: before == null
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(builder: (context, b) {
                  final w = b.maxWidth;
                  return GestureDetector(
                    onHorizontalDragUpdate:
                        after == null ? null : (e) => setState(() => _split = (e.localPosition.dx / w).clamp(0.0, 1.0)),
                    onTapDown: after == null ? null : (e) => setState(() => _split = (e.localPosition.dx / w).clamp(0.0, 1.0)),
                    child: Stack(fit: StackFit.expand, children: [
                      Image.memory(before, fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.medium),
                      if (after != null)
                        ClipRect(
                          clipper: _SplitClipper(_split),
                          child: Image.memory(after, fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.medium),
                        ),
                      if (after != null)
                        Positioned(
                          left: w * _split - 1,
                          top: 0,
                          bottom: 0,
                          child: Container(width: 2, color: Colors.white),
                        ),
                      if (after != null) ...[
                        _badge('Foto IA', Alignment.topLeft),
                        _badge('Render 3D', Alignment.topRight),
                      ],
                      if (_progress != null) _progressOverlay(),
                    ]),
                  );
                }),
        ),
      ),
    );
  }

  Widget _badge(String t, Alignment a) => Align(
        alignment: a,
        child: Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
          child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ),
      );

  Widget _progressOverlay() {
    final p = _progress!;
    final secs = _clock.elapsed.inSeconds;
    return Container(
      color: Colors.black45,
      alignment: Alignment.center,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 72,
          height: 72,
          child: CircularProgressIndicator(value: math.max(0.02, p.fraction), strokeWidth: 6, color: Colors.white),
        ),
        const SizedBox(height: 14),
        Text(p.message, style: const TextStyle(color: Colors.white, fontSize: 15)),
        const SizedBox(height: 4),
        Text('${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}',
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ]),
    );
  }

  Widget _controls(BuildContext context, bool busy, ColorScheme cs) {
    final t = Theme.of(context).textTheme;
    final m = mgr.active;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Ambiente', style: t.labelLarge),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 4, children: [
        for (final s in PhotoScene.values)
          ChoiceChip(
            label: Text(s.label),
            selected: scene == s,
            onSelected: busy ? null : (_) => setState(() => scene = s),
          ),
      ]),
      const SizedBox(height: 12),
      Text('Fidelidad al render', style: t.labelLarge),
      const SizedBox(height: 6),
      SegmentedButton<int>(
        segments: [for (var i = 0; i < 3; i++) ButtonSegment(value: i, label: Text(fidelityLabels[i]))],
        selected: {mgr.fidelity},
        onSelectionChanged: busy
            ? null
            : (v) {
                mgr.fidelity = v.first;
                mgr.savePrefs();
                setState(() {});
              },
      ),
      const SizedBox(height: 4),
      Text(fidelityHelp[mgr.fidelity], style: t.bodySmall),
      const SizedBox(height: 16),
      if (busy)
        OutlinedButton.icon(
          onPressed: () => _job?.cancel(),
          icon: const Icon(Icons.stop),
          label: const Text('Cancelar'),
        )
      else
        FilledButton.icon(
          onPressed: _renderRgba == null ? null : _generate,
          icon: const Icon(Icons.auto_awesome),
          label: Text(_photoPng == null ? 'Generar foto' : 'Generar de nuevo'),
        ),
      if (_photoPng != null && !busy) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () {
            setState(() => _seed = (_seed * 1103515245 + 12345) & 0x7fffffff);
            _generate();
          },
          icon: const Icon(Icons.casino_outlined),
          label: const Text('Otra variante'),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(onPressed: _save, icon: const Icon(Icons.download), label: const Text('Guardar')),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).pop(_photoPng),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Usar en el PDF'),
            ),
          ),
        ]),
      ],
      if (_error != null) ...[
        const SizedBox(height: 12),
        Card(
          color: cs.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_error!, style: TextStyle(color: cs.onErrorContainer)),
          ),
        ),
      ],
      const SizedBox(height: 12),
      if (_info != null) Text(_info!, style: t.bodySmall),
      Text(
        'Modelo: ${m?.name ?? '—'} · ${mgr.size} px · ${mgr.engine.label}. '
        'La imagen se genera en este dispositivo a partir del render 3D; es ilustrativa y puede '
        'inventar detalles: las medidas y perfiles válidos son los de los planos.',
        style: t.bodySmall,
      ),
    ]);
  }
}

class _SplitClipper extends CustomClipper<Rect> {
  final double f;
  _SplitClipper(this.f);
  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * f, size.height);
  @override
  bool shouldReclip(covariant _SplitClipper old) => old.f != f;
}
