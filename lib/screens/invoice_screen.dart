import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:printing/printing.dart';

import '../ai/model_gate.dart';
import '../ai/model_manager.dart';
import '../engine/invoice_parser.dart';
import '../engine/pricing.dart';
import '../plans/ocr_engine.dart';
import '../plans/pdf_text.dart';
import '../services/geo.dart';
import '../services/price_store.dart';
import 'models_screen.dart';

String _n(double v, [int d = 2]) => v.toStringAsFixed(d).replaceAll('.', ',');

/// Lee el texto de una factura o tarifa (PDF con texto, PDF escaneado o
/// foto). Devuelve null si el usuario no quiere descargar el OCR.
Future<String?> readDocumentText(BuildContext context, Uint8List bytes, void Function(String) say) async {
  final isPdf = bytes.length > 4 && String.fromCharCodes(bytes.sublist(0, 4)) == '%PDF';
  if (isPdf) {
    say('Leyendo el texto del PDF…');
    try {
      final r = await Isolate.run(() => PdfTextReader.read(bytes, maxPages: 4));
      if (r.tokens.length >= 8) return tokensToText(r.tokens);
    } catch (_) {}
  }
  // escaneado o foto: OCR local
  final mgr = ModelManager.instance;
  await mgr.load();
  if (!mgr.ocrReady) {
    if (!context.mounted) return null;
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Falta el lector de texto (OCR)'),
        content: const Text('Para leer facturas escaneadas o fotos hace falta descargar una vez el modelo OCR local '
            '(unos 16 MB). Funciona sin conexión y la factura no sale del dispositivo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ir a Modelos')),
        ],
      ),
    );
    if (go != true || !context.mounted) return null;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ModelsScreen()));
    if (!mgr.ocrReady) return null;
  }
  Uint8List rgba;
  int w, h;
  if (isPdf) {
    say('Pasando la página a imagen…');
    PdfRaster? page;
    await for (final p in Printing.raster(bytes, pages: const [0], dpi: 220)) {
      page = p;
      break;
    }
    if (page == null) throw 'No se pudo abrir el PDF.';
    (rgba, w, h) = (page.pixels, page.width, page.height);
  } else {
    final codec = await ui.instantiateImageCodec(bytes);
    final img = (await codec.getNextFrame()).image;
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    (w, h) = (img.width, img.height);
    img.dispose();
    codec.dispose();
    if (data == null) throw 'No se pudo leer la imagen.';
    rgba = data.buffer.asUint8List();
  }
  say('Leyendo la factura (OCR local)…');
  final dir = (await mgr.dir(mgr.ocr.subdir)).path;
  final threads = (Platform.numberOfProcessors - 1).clamp(1, 6);
  final toks = await ModelGate.instance.run(ModelTask.plans,
      () => runOcr(OcrRequest(modelDir: dir, rgba: rgba, width: w, height: h, threads: threads, engine: mgr.engineFor(ModelTask.plans))));
  return tokensToText(toks);
}

/// Importar facturas o tarifas: elige el archivo (o haz una foto), lee el
/// texto y abre la revisión.
Future<bool> importInvoice(BuildContext context, {bool camera = false, void Function(String)? onStatus}) async {
  ModelGate.instance.enter(WorkflowStep.facturas);
  Uint8List? bytes;
  String name;
  if (camera) {
    final x = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 2600, maxHeight: 2600, imageQuality: 92);
    if (x == null) return false;
    bytes = await x.readAsBytes();
    name = 'Foto de factura';
  } else {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Elige una factura o tarifa (PDF o imagen)',
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'webp', 'bmp', 'txt', 'csv'],
    );
    if (files.isEmpty) return false;
    bytes = await files.first.readAsBytes();
    name = files.first.name;
  }
  if (!context.mounted) return false;
  String? text;
  final low = name.toLowerCase();
  if (low.endsWith('.txt') || low.endsWith('.csv')) {
    text = String.fromCharCodes(bytes).replaceAll(';', '  ');
  } else {
    text = await readDocumentText(context, bytes, onStatus ?? (_) {});
  }
  onStatus?.call('');
  if (text == null || !context.mounted) return false;
  final inv = parseInvoiceText(text);
  final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => InvoiceReviewScreen(invoice: inv, docName: name, rawText: text!)));
  return saved == true;
}

/// Revisión de lo leído antes de guardarlo en la base de precios.
class InvoiceReviewScreen extends StatefulWidget {
  final ParsedInvoice invoice;
  final String docName;
  final String rawText;
  const InvoiceReviewScreen({super.key, required this.invoice, required this.docName, this.rawText = ''});
  @override
  State<InvoiceReviewScreen> createState() => _InvoiceReviewScreenState();
}

class _InvoiceReviewScreenState extends State<InvoiceReviewScreen> {
  late final inv = widget.invoice;
  late final _name = TextEditingController(text: inv.supplierName);
  late final _cif = TextEditingController(text: inv.cif);
  late final _addr = TextEditingController(text: inv.address);
  late final _number = TextEditingController(text: inv.number);
  late DateTime _date = inv.date ?? DateTime.now();
  GeoPoint? _loc;
  String _locText = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // si el proveedor ya existe, se reutiliza su ubicación
    PriceStore.instance.book().then((b) {
      final s = b.findSupplier(cif: inv.cif, name: inv.supplierName);
      if (s?.location != null && mounted) {
        setState(() {
          _loc = s!.location;
          _locText = 'Ubicación ya guardada de ${s.name}';
        });
      }
    });
  }

  Future<void> _geocode() async {
    if (_addr.text.trim().isEmpty) return;
    setState(() => _locText = 'Buscando la dirección en el mapa…');
    try {
      final r = await geocode(_addr.text.trim());
      setState(() {
        _loc = r?.$1;
        _locText = r == null ? 'No se encontró la dirección; puedes guardar igualmente.' : 'Ubicación: ${r.$2}';
      });
    } catch (e) {
      setState(() => _locText = 'Sin conexión con el mapa: $e');
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Escribe el nombre del proveedor.')));
      return;
    }
    setState(() => _saving = true);
    final ps = PriceStore.instance;
    final book = await ps.book();
    final s = book.upsertSupplier(Supplier(
      id: PriceBook.newSupplierId(),
      name: _name.text.trim(),
      cif: _cif.text.trim(),
      address: _addr.text.trim(),
      location: _loc,
      phone: inv.phone,
      email: inv.email,
      source: SupplierSource.factura,
    ));
    if (s.location == null && _loc != null) s.location = _loc;
    inv
      ..date = _date
      ..number = _number.text.trim();
    final prices = inv.toPrices(s.id, doc: inv.number.isNotEmpty ? inv.number : widget.docName);
    book.addPrices(prices);
    await ps.saveBook();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${prices.length} precio(s) guardados de ${s.name}.')));
    Navigator.pop(context, true);
  }

  Future<void> _editLine(InvoiceLine l) async {
    final desc = TextEditingController(text: l.description);
    final key = TextEditingController(text: l.ref?.key ?? '');
    final price = TextEditingController(text: _n(l.unitPrice, 4));
    var unit = l.unit;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Línea de la factura'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: desc, decoration: const InputDecoration(labelText: 'Descripción'), maxLines: 2),
              const SizedBox(height: 10),
              TextField(
                controller: key,
                decoration: const InputDecoration(
                    labelText: 'Material (p. ej. IPE 200, SHS 80x3, CHAPA 10, TORNILLO M16)',
                    helperText: 'Así se casa con el despiece'),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Precio neto sin IVA'),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<PriceUnit>(
                  value: unit,
                  items: [for (final u in PriceUnit.values) DropdownMenuItem(value: u, child: Text(u.label))],
                  onChanged: (u) => set(() => unit = u ?? unit),
                ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Aceptar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() {
      l.description = desc.text.trim();
      final k = key.text.trim();
      l.ref = k.isEmpty ? null : (parseMaterial(k) ?? parseRefKey(k.toUpperCase()));
      l.unitPrice = double.tryParse(price.text.replaceAll(',', '.')) ?? l.unitPrice;
      l.unit = unit;
      l.selected = l.ref != null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sel = inv.lines.where((l) => l.selected && l.ref != null).length;
    return Scaffold(
      appBar: AppBar(title: Text(inv.isPriceList ? 'Revisar tarifa' : 'Revisar factura')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Text('Comprueba lo leído. Solo se guardan las líneas marcadas con un material reconocido.',
            style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 10),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Proveedor')),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: _cif, decoration: const InputDecoration(labelText: 'CIF'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _number, decoration: InputDecoration(labelText: inv.isPriceList ? 'Referencia' : 'Nº factura'))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: _addr, decoration: const InputDecoration(labelText: 'Dirección del proveedor'))),
          IconButton(tooltip: 'Situar en el mapa (para el radio)', onPressed: _geocode, icon: const Icon(Icons.travel_explore)),
        ]),
        if (_locText.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_locText, style: const TextStyle(fontSize: 12))),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event),
          title: Text('Fecha: ${_date.day}/${_date.month}/${_date.year}'),
          trailing: TextButton(
            onPressed: () async {
              final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2015), lastDate: DateTime(2100));
              if (d != null) setState(() => _date = d);
            },
            child: const Text('Cambiar'),
          ),
        ),
        const Divider(),
        Text('Líneas leídas (${inv.lines.length})', style: Theme.of(context).textTheme.titleMedium),
        if (inv.lines.isEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
                'No se ha encontrado ninguna línea en la que cantidad × precio cuadre con el importe. '
                'Puedes añadir los precios a mano desde la base de precios.',
                style: TextStyle(color: cs.error)),
          ),
        for (final l in inv.lines)
          Card(
            child: CheckboxListTile(
              value: l.selected && l.ref != null,
              onChanged: l.ref == null ? null : (v) => setState(() => l.selected = v ?? false),
              title: Text(l.description),
              subtitle: Text(
                '${l.ref?.key ?? 'material sin reconocer: toca ✎'} · ${_n(l.qty)} ${l.unit.short} × ${_n(l.unitPrice, 3)} €'
                '${l.discountPct > 0 ? ' (dto ${_n(l.discountPct, 1)} %)' : ''} = ${_n(l.amount)} €',
                style: TextStyle(color: l.ref == null ? cs.error : null),
              ),
              secondary: IconButton(icon: const Icon(Icons.edit), onPressed: () => _editLine(l)),
            ),
          ),
        if (widget.rawText.isNotEmpty)
          ExpansionTile(
            title: const Text('Texto leído'),
            children: [SelectableText(widget.rawText, style: const TextStyle(fontFamily: 'monospace', fontSize: 11))],
          ),
        const SizedBox(height: 80),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _save,
        icon: const Icon(Icons.save),
        label: Text('Guardar $sel precio(s)'),
      ),
    );
  }
}
