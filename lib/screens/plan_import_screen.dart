import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:printing/printing.dart';

import '../ai/model_manager.dart';
import '../ai/vlm.dart';
import '../engine/designer.dart';
import '../plans/ocr_engine.dart';
import '../plans/pdf_text.dart';
import '../plans/plan_analyzer.dart';
import '../plans/plan_token.dart';
import 'models_screen.dart';
import 'project_screen.dart';

/// Importa un plano (PDF de CAD, PDF escaneado o foto) y lo convierte en un
/// prompt que el usuario revisa antes de calcular.
class PlanImportScreen extends StatefulWidget {
  const PlanImportScreen({super.key});
  @override
  State<PlanImportScreen> createState() => _PlanImportScreenState();
}

class _PlanImportScreenState extends State<PlanImportScreen> {
  final _prompt = TextEditingController();
  final mgr = ModelManager.instance;
  bool _busy = false;
  String _status = '';
  String? _file;
  String _source = '';
  Uint8List? _preview;
  PlanAnalysis? _a;
  PlanReading? _reading;
  (Uint8List, int, int)? _raster; // imagen para la visión IA
  String? _vision; // descripción del VLM (inglés)
  String _seeing = ''; // texto parcial mientras genera
  VlmJob? _job;

  @override
  void initState() {
    super.initState();
    mgr.load();
  }

  @override
  void dispose() {
    _job?.cancel();
    _prompt.dispose();
    super.dispose();
  }

  /// Mira el dibujo con el VLM local y completa la descripción.
  Future<void> _see() async {
    final r = _raster;
    if (r == null || _job != null) return;
    await mgr.load();
    if (!mgr.vlmReady) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Falta el modelo de visión'),
          content: const Text('Para interpretar croquis a mano hace falta descargar una vez el modelo de visión local '
              '(260 MB el ligero, 515 MB el de calidad). Funciona sin conexión y la imagen no sale del dispositivo.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ir a Modelos')),
          ],
        ),
      );
      if (go != true || !mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ModelsScreen()));
      if (!mgr.vlmReady) return;
    }
    final dir = (await mgr.dir(mgr.vlm.subdir)).path;
    final threads = (Platform.numberOfProcessors - 1).clamp(1, 6);
    setState(() => _seeing = 'Mirando el dibujo…');
    final job = startVlm(
        VlmRequest(modelDir: dir, prefix: mgr.vlmPrefix, rgba: r.$1, width: r.$2, height: r.$3, threads: threads),
        (partial) => mounted ? setState(() => _seeing = partial) : null);
    _job = job;
    try {
      final res = await job.future;
      if (!mounted) return;
      final reading = _reading ?? PlanReading(const [], 'imagen-ocr');
      final a = analyzePlan(reading, vision: res.text);
      setState(() {
        _vision = res.text;
        _a = a;
        _prompt.text = a.prompt;
        _source = '$_source + visión IA (${(res.time.inMilliseconds / 1000).toStringAsFixed(0)} s)';
      });
    } catch (e) {
      if (mounted && '$e' != 'Exception: Cancelado') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('La visión IA no pudo leer el dibujo: $e')));
      }
    } finally {
      _job = null;
      if (mounted) setState(() => _seeing = '');
    }
  }

  void _say(String s) {
    if (mounted) setState(() => _status = s);
  }

  Future<void> _pick() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Elige un plano (PDF o imagen)',
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'webp', 'bmp'],
    );
    if (files.isEmpty) return;
    final f = files.first;
    final bytes = await f.readAsBytes();
    await _process(bytes, f.name);
  }

  Future<void> _camera() async {
    final x = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 2600, maxHeight: 2600, imageQuality: 92);
    if (x == null) return;
    await _process(await x.readAsBytes(), 'Foto del plano');
  }

  Future<bool> _ensureOcr() async {
    await mgr.load();
    if (mgr.ocrReady) return true;
    if (!mounted) return false;
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Falta el lector de texto (OCR)'),
        content: const Text('Para leer planos escaneados o fotos hace falta descargar una vez el modelo OCR local '
            '(unos 16 MB). Funciona sin conexión y la imagen no sale del dispositivo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ir a Modelos')),
        ],
      ),
    );
    if (go != true || !mounted) return false;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ModelsScreen()));
    return mgr.ocrReady;
  }

  Future<PlanReading?> _ocr(Uint8List rgba, int w, int h, String source) async {
    if (!await _ensureOcr()) return null;
    _say('Leyendo textos y cotas (OCR local)…');
    final dir = (await mgr.dir(mgr.ocr.subdir)).path;
    final threads = (Platform.numberOfProcessors - 1).clamp(1, 6);
    final toks = await runOcr(OcrRequest(modelDir: dir, rgba: rgba, width: w, height: h, threads: threads));
    return PlanReading(toks, source, pageWidth: w.toDouble(), pageHeight: h.toDouble());
  }

  Future<void> _process(Uint8List bytes, String name) async {
    setState(() {
      _busy = true;
      _file = name;
      _a = null;
      _preview = null;
      _reading = null;
      _raster = null;
      _vision = null;
      _status = 'Abriendo el plano…';
    });
    try {
      final isPdf = bytes.length > 4 && String.fromCharCodes(bytes.sublist(0, 4)) == '%PDF';
      PlanReading? reading;
      if (isPdf) {
        _say('Leyendo el texto del PDF…');
        try {
          reading = await Isolate.run(() => PdfTextReader.read(bytes));
        } catch (_) {
          reading = null;
        }
        // Vista previa y, si no hay texto (escaneado), OCR sobre la primera página
        PdfRaster? page;
        try {
          await for (final p in Printing.raster(bytes, pages: const [0], dpi: 150)) {
            page = p;
            break;
          }
        } catch (_) {}
        if (page != null) _preview = await page.toPng();
        if (reading == null || reading.tokens.length < 6) {
          if (page == null) throw 'No se pudo abrir el PDF.';
          // re-rasterizado a más resolución para el OCR
          PdfRaster hi = page;
          try {
            await for (final p in Printing.raster(bytes, pages: const [0], dpi: 220)) {
              hi = p;
              break;
            }
          } catch (_) {}
          _raster = (hi.pixels, hi.width, hi.height);
          reading = await _ocr(hi.pixels, hi.width, hi.height, 'pdf-ocr');
        }
      } else {
        _preview = bytes;
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final img = frame.image;
        final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) throw 'No se pudo leer la imagen.';
        _raster = (data.buffer.asUint8List(), img.width, img.height);
        reading = await _ocr(data.buffer.asUint8List(), img.width, img.height, 'imagen-ocr');
        img.dispose();
      }
      if (reading == null) {
        _say('');
        return;
      }
      _say('Interpretando el plano…');
      final a = analyzePlan(reading);
      _reading = reading;
      setState(() {
        _a = a;
        _source = switch (reading!.source) {
          'pdf-texto' => 'PDF de CAD (texto leído directamente)',
          'pdf-ocr' => 'PDF escaneado (OCR local)',
          _ => 'Imagen (OCR local)',
        };
        _prompt.text = a.prompt;
        _status = '';
      });
      // Croquis con poco texto: si el modelo de visión ya está, se usa solo.
      if (_raster != null && reading.tokens.length < 12 && mgr.vlmReady) unawaited(_see());
    } catch (e) {
      _say('');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo leer el plano: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _calc() async {
    final p = _prompt.text.trim();
    if (p.isEmpty) return;
    try {
      final d = designFromPrompt(p);
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProjectScreen(design: d)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo calcular: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final a = _a;
    return Scaffold(
      appBar: AppBar(title: const Text('Importar plano')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Text('Convierte un plano en una descripción', style: tt.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Los PDF de CAD se leen directamente. Los PDF escaneados y las fotos se leen con OCR local, '
                'sin conexión. Revisa el texto propuesto antes de calcular.',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 10, children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _pick,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Elegir PDF o imagen'),
                ),
                if (Platform.isAndroid || Platform.isIOS)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _camera,
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Hacer foto al plano'),
                  ),
              ]),
              if (_busy) ...[
                const SizedBox(height: 16),
                Row(children: [
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_status)),
                ]),
              ],
              if (_file != null && !_busy && a == null) ...[
                const SizedBox(height: 16),
                Text('No se ha obtenido texto de «$_file».', style: TextStyle(color: cs.error)),
              ],
              if (_preview != null) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: Image.memory(_preview!, fit: BoxFit.contain),
                  ),
                ),
              ],
              if (a != null) ...[
                const SizedBox(height: 16),
                Text('$_file · $_source', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Datos encontrados', style: tt.titleMedium),
                      const SizedBox(height: 6),
                      if (a.findings.isEmpty) const Text('No se han reconocido datos: escribe la descripción abajo.'),
                      for (final f in a.findings)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            SizedBox(width: 140, child: Text(f.label, style: TextStyle(color: cs.onSurfaceVariant))),
                            Expanded(child: Text(f.value, style: const TextStyle(fontWeight: FontWeight.w600))),
                            if (f.guessed)
                              Tooltip(
                                message: 'Deducido del dibujo: revísalo',
                                child: Icon(Icons.help_outline, size: 18, color: cs.tertiary),
                              ),
                          ]),
                        ),
                    ]),
                  ),
                ),
                for (final w in a.warnings)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.warning_amber, size: 18, color: cs.error),
                      const SizedBox(width: 8),
                      Expanded(child: Text(w, style: const TextStyle(fontSize: 13))),
                    ]),
                  ),
                if (_raster != null) ...[
                  const SizedBox(height: 12),
                  if (_job != null)
                    Card(
                      color: cs.secondaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 10),
                          Expanded(child: Text(_seeing, style: const TextStyle(fontSize: 13))),
                          TextButton(onPressed: () => _job?.cancel(), child: const Text('Parar')),
                        ]),
                      ),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _see,
                      icon: const Icon(Icons.visibility_outlined),
                      label: Text(_vision == null ? 'Interpretar el dibujo con visión IA (croquis a mano)' : 'Volver a mirar el dibujo'),
                    ),
                ],
                const SizedBox(height: 16),
                Text('Descripción para calcular (puedes corregirla)', style: tt.titleMedium),
                const SizedBox(height: 6),
                TextField(controller: _prompt, minLines: 3, maxLines: 8),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _calc,
                  icon: const Icon(Icons.calculate),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Calcular estructura', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 12),
                ExpansionTile(
                  title: const Text('Texto leído del plano'),
                  childrenPadding: const EdgeInsets.all(12),
                  children: [SelectableText(a.rawText.isEmpty ? '(vacío)' : a.rawText, style: const TextStyle(fontSize: 12))],
                ),
                if (_vision != null)
                  ExpansionTile(
                    title: const Text('Lo que ve la visión IA (en inglés)'),
                    childrenPadding: const EdgeInsets.all(12),
                    children: [SelectableText(_vision!, style: const TextStyle(fontSize: 12))],
                  ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
