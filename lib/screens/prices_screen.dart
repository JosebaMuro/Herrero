import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../engine/budget.dart';
import '../engine/invoice_parser.dart';
import '../engine/model.dart';
import '../engine/pricing.dart';
import '../services/geo.dart';
import '../services/price_store.dart';
import 'invoice_screen.dart';

String _n(double v, [int d = 2]) => v.toStringAsFixed(d).replaceAll('.', ',');
String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Base de precios del taller: facturas y precios, distribuidores cercanos,
/// ubicación y radio, y tarifas de mano de obra.
class PricesScreen extends StatefulWidget {
  final int initialTab;
  final Design? design; // para pedir precio con el pedido del proyecto
  final String projectName;
  final String site;
  const PricesScreen({super.key, this.initialTab = 0, this.design, this.projectName = '', this.site = ''});
  @override
  State<PricesScreen> createState() => _PricesScreenState();
}

class _PricesScreenState extends State<PricesScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 4, vsync: this, initialIndex: widget.initialTab.clamp(0, 3));
  PriceBook? _book;
  String _status = '';
  String _filter = '';

  @override
  void initState() {
    super.initState();
    PriceStore.instance.book().then((b) => mounted ? setState(() => _book = b) : null);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _import({bool camera = false}) async {
    try {
      await importInvoice(context, camera: camera, onStatus: (s) => mounted ? setState(() => _status = s) : null);
    } catch (e) {
      _toast('No se pudo leer: $e');
    }
    if (mounted) setState(() => _status = '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Precios y proveedores'),
        bottom: TabBar(controller: _tabs, isScrollable: true, tabAlignment: TabAlignment.start, tabs: const [
          Tab(icon: Icon(Icons.receipt_long), text: 'Precios'),
          Tab(icon: Icon(Icons.store_mall_directory_outlined), text: 'Distribuidores'),
          Tab(icon: Icon(Icons.place_outlined), text: 'Ubicación'),
          Tab(icon: Icon(Icons.engineering_outlined), text: 'Taller'),
        ]),
      ),
      body: _book == null
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              if (_status.isNotEmpty) LinearProgressIndicator(semanticsLabel: _status),
              if (_status.isNotEmpty) Padding(padding: const EdgeInsets.all(6), child: Text(_status)),
              Expanded(
                child: TabBarView(controller: _tabs, children: [
                  _pricesTab(),
                  _DistributorsTab(book: _book!, design: widget.design, projectName: widget.projectName, site: widget.site, onChanged: () => setState(() {})),
                  _GeoTab(onChanged: () => setState(() {})),
                  const _RatesTab(),
                ]),
              ),
            ]),
    );
  }

  // ------------------------------------------------------------------ Precios
  Widget _pricesTab() {
    final b = _book!;
    final f = _filter.toUpperCase();
    final entries = [
      for (final e in b.entries)
        if (f.isEmpty || e.ref.contains(f) || e.description.toUpperCase().contains(f) || (b.suppliers[e.supplierId]?.name.toUpperCase().contains(f) ?? false)) e
    ]..sort((a, c) => a.ref.compareTo(c.ref) != 0 ? a.ref.compareTo(c.ref) : c.date.compareTo(a.date));
    return ListView(padding: const EdgeInsets.all(12), children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(onPressed: () => _import(), icon: const Icon(Icons.upload_file), label: const Text('Importar factura o tarifa')),
        OutlinedButton.icon(onPressed: () => _import(camera: true), icon: const Icon(Icons.photo_camera), label: const Text('Foto de factura')),
        OutlinedButton.icon(onPressed: _manualPrice, icon: const Icon(Icons.add), label: const Text('Precio a mano')),
      ]),
      const SizedBox(height: 8),
      Text(
          'De cada factura se guardan proveedor, material y precio unitario neto. El presupuesto usa los proveedores '
          'dentro del radio elegido y los precios de los últimos ${PriceStore.instance.geo.maxAgeMonths} meses.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
      const SizedBox(height: 8),
      TextField(
        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar material o proveedor', isDense: true),
        onChanged: (v) => setState(() => _filter = v.trim()),
      ),
      const SizedBox(height: 6),
      if (entries.isEmpty)
        const Padding(padding: EdgeInsets.all(16), child: Text('Todavía no hay precios. Importa tu primera factura.')),
      for (final e in entries)
        Dismissible(
          key: ValueKey('${e.supplierId}|${e.ref}|${e.unit}|${e.date}'),
          direction: DismissDirection.endToStart,
          background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.all(16), child: const Icon(Icons.delete, color: Colors.white)),
          onDismissed: (_) async {
            b.entries.remove(e);
            await PriceStore.instance.saveBook();
            setState(() {});
          },
          child: ListTile(
            dense: true,
            title: Text('${e.ref} · ${_n(e.price, 3)} ${e.unit.label}'),
            subtitle: Text('${b.suppliers[e.supplierId]?.name ?? '?'} · ${e.source.label} ${_date(e.date)}'
                '${e.doc.isEmpty ? '' : ' · ${e.doc}'}\n${e.description}'),
            isThreeLine: true,
          ),
        ),
    ]);
  }

  Future<void> _manualPrice() async {
    final b = _book!;
    final sup = TextEditingController();
    final mat = TextEditingController();
    final price = TextEditingController();
    var unit = PriceUnit.kg;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Precio a mano'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Autocomplete<String>(
                optionsBuilder: (v) => [for (final s in b.suppliers.values) if (s.name.toLowerCase().contains(v.text.toLowerCase())) s.name],
                fieldViewBuilder: (c, ctrl, fn, _) {
                  ctrl.addListener(() => sup.text = ctrl.text);
                  return TextField(controller: ctrl, focusNode: fn, decoration: const InputDecoration(labelText: 'Proveedor'));
                },
                onSelected: (s) => sup.text = s,
              ),
              const SizedBox(height: 8),
              TextField(controller: mat, decoration: const InputDecoration(labelText: 'Material (IPE 200, tubo 80x80x3, chapa 8 mm…)')),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: price,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Precio sin IVA'))),
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
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final ref = parseMaterial(mat.text);
    final p = double.tryParse(price.text.replaceAll(',', '.'));
    if (ref == null || p == null || sup.text.trim().isEmpty) {
      _toast('Falta el proveedor, el precio o no se reconoce el material.');
      return;
    }
    final s = b.upsertSupplier(Supplier(id: PriceBook.newSupplierId(), name: sup.text.trim()));
    b.addPrices([
      PriceEntry(supplierId: s.id, ref: ref.key, description: mat.text.trim(), unit: unit, price: p, date: DateTime.now(), source: PriceSource.manual)
    ]);
    await PriceStore.instance.saveBook();
    setState(() {});
  }
}

// --------------------------------------------------------------- Distribuidores
class _DistributorsTab extends StatefulWidget {
  final PriceBook book;
  final Design? design;
  final String projectName, site;
  final VoidCallback onChanged;
  const _DistributorsTab({required this.book, this.design, this.projectName = '', this.site = '', required this.onChanged});
  @override
  State<_DistributorsTab> createState() => _DistributorsTabState();
}

class _DistributorsTabState extends State<_DistributorsTab> {
  List<Supplier>? _found;
  bool _busy = false;
  String _msg = '';

  Future<void> _search() async {
    final g = PriceStore.instance.geo;
    if (g.here == null) {
      setState(() => _msg = 'Primero fija tu ubicación en la pestaña «Ubicación».');
      return;
    }
    setState(() {
      _busy = true;
      _msg = 'Buscando en OpenStreetMap en ${_n(g.radiusKm, 0)} km…';
    });
    try {
      final r = await nearbyDistributors(g.here!, g.radiusKm);
      setState(() {
        _found = r;
        _msg = r.isEmpty
            ? 'El mapa no tiene distribuidores registrados en ese radio. Amplía el radio o añade los tuyos desde sus facturas.'
            : '${r.length} resultado(s). El mapa no da precios: pídeselos con el pedido del proyecto o guarda su tarifa.';
      });
    } catch (e) {
      setState(() => _msg = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add(Supplier s) async {
    widget.book.upsertSupplier(s);
    await PriceStore.instance.saveBook();
    widget.onChanged();
    setState(() {});
  }

  Future<void> _quote(Supplier s) async {
    final d = widget.design;
    final body = d == null ? 'Buenos días, ¿nos pueden enviar su tarifa de perfiles, tubos y chapa?' : quoteRequestText(d, project: widget.projectName, site: widget.site);
    final subject = d == null ? 'Petición de tarifa' : 'Petición de precio – ${widget.projectName.isEmpty ? d.spec.type.label : widget.projectName}';
    final uri = s.email.isNotEmpty
        ? Uri(scheme: 'mailto', path: s.email, queryParameters: {'subject': subject, 'body': body})
        : (s.phone.isNotEmpty ? Uri(scheme: 'sms', path: s.phone.replaceAll(' ', ''), queryParameters: {'body': body}) : null);
    if (uri == null || !await launchUrl(uri)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Este distribuidor no tiene correo ni teléfono en el mapa.')));
    }
  }

  Future<void> _readWeb(Supplier s) async {
    final ctrl = TextEditingController(text: s.priceUrl.isNotEmpty ? s.priceUrl : s.web);
    final url = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Tarifa web de ${s.name}'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Dirección de la página de precios (o PDF de tarifa)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Leer precios')),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    setState(() => _busy = true);
    try {
      final (text, isPdf) = await fetchPriceText(url.startsWith('http') ? url : 'https://$url');
      if (!mounted) return;
      final inv = isPdf ? null : parseInvoiceText(text);
      if (inv == null || inv.lines.isEmpty) {
        setState(() => _msg = isPdf
            ? 'Es un PDF: descárgalo e impórtalo como tarifa desde «Precios».'
            : 'La página no tiene precios legibles (líneas con «€/kg», «€/m»…). Muchas webs de almacén no publican precios.');
        return;
      }
      inv
        ..supplierName = s.name
        ..isPriceList = true;
      s.priceUrl = url;
      widget.book.upsertSupplier(s);
      final saved = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => InvoiceReviewScreen(invoice: inv, docName: url, rawText: text)));
      if (saved == true) {
        // los precios leídos de la web se marcan como tales
        final b = widget.book;
        final sup = b.findSupplier(name: s.name);
        if (sup != null) {
          for (var i = 0; i < b.entries.length; i++) {
            final e = b.entries[i];
            if (e.supplierId == sup.id && e.doc == url) {
              b.entries[i] = PriceEntry(supplierId: e.supplierId, ref: e.ref, description: e.description, unit: e.unit, price: e.price, date: e.date, source: PriceSource.web, doc: url);
            }
          }
          await PriceStore.instance.saveBook();
        }
      }
    } catch (e) {
      setState(() => _msg = 'No se pudo leer la página: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _tile(Supplier s, double? dist, {bool saved = false}) {
    final n = widget.book.entries.where((e) => e.supplierId == s.id).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold))),
            if (dist != null) Text('${_n(dist, 0)} km'),
          ]),
          if (s.address.isNotEmpty) Text(s.address, style: const TextStyle(fontSize: 12)),
          Text([
            if (saved) '$n precio(s)',
            if (s.phone.isNotEmpty) s.phone,
            if (s.email.isNotEmpty) s.email,
            if (s.location == null) 'sin ubicación',
          ].join(' · '), style: const TextStyle(fontSize: 12)),
          Wrap(spacing: 0, children: [
            if (!saved) TextButton.icon(onPressed: () => _add(s), icon: const Icon(Icons.bookmark_add_outlined), label: const Text('Guardar')),
            TextButton.icon(onPressed: () => _quote(s), icon: const Icon(Icons.request_quote_outlined), label: const Text('Pedir precio')),
            if (s.phone.isNotEmpty)
              IconButton(tooltip: 'Llamar', onPressed: () => launchUrl(Uri(scheme: 'tel', path: s.phone.replaceAll(' ', ''))), icon: const Icon(Icons.call)),
            if (s.web.isNotEmpty)
              IconButton(
                  tooltip: 'Web',
                  onPressed: () => launchUrl(Uri.parse(s.web.startsWith('http') ? s.web : 'https://${s.web}'), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.public)),
            IconButton(tooltip: 'Leer precios de su web', onPressed: _busy ? null : () => _readWeb(s), icon: const Icon(Icons.travel_explore)),
            if (saved)
              IconButton(
                tooltip: 'Quitar proveedor y sus precios',
                onPressed: () async {
                  widget.book.removeSupplier(s.id);
                  await PriceStore.instance.saveBook();
                  widget.onChanged();
                  setState(() {});
                },
                icon: const Icon(Icons.delete_outline),
              ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = PriceStore.instance.geo;
    final mine = widget.book.suppliersNear(g.here, g.radiusKm);
    final savedIds = widget.book.suppliers.keys.toSet();
    return ListView(padding: const EdgeInsets.all(12), children: [
      FilledButton.icon(
        onPressed: _busy ? null : _search,
        icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.map_outlined),
        label: Text('Buscar distribuidores a ${_n(g.radiusKm, 0)} km${g.placeName.isEmpty ? '' : ' de ${g.placeName}'}'),
      ),
      if (_msg.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(_msg)),
      if (mine.isNotEmpty) ...[
        Padding(padding: const EdgeInsets.only(top: 8), child: Text('Mis proveedores en el radio', style: Theme.of(context).textTheme.titleMedium)),
        for (final (s, d) in mine) _tile(s, d, saved: true),
      ],
      if (_found != null && _found!.isNotEmpty) ...[
        Padding(padding: const EdgeInsets.only(top: 8), child: Text('En el mapa', style: Theme.of(context).textTheme.titleMedium)),
        for (final s in _found!)
          if (!savedIds.contains(s.id)) _tile(s, g.here?.distanceTo(s.location!)),
      ],
      const SizedBox(height: 8),
      Text('Datos de distribuidores: © colaboradores de OpenStreetMap (ODbL).', style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

// ------------------------------------------------------------------ Ubicación
class _GeoTab extends StatefulWidget {
  final VoidCallback onChanged;
  const _GeoTab({required this.onChanged});
  @override
  State<_GeoTab> createState() => _GeoTabState();
}

class _GeoTabState extends State<_GeoTab> {
  final _place = TextEditingController();
  String _msg = '';
  bool _busy = false;
  GeoSettings get g => PriceStore.instance.geo;

  Future<void> _save() async {
    await PriceStore.instance.saveSettings();
    widget.onChanged();
    setState(() {});
  }

  Future<void> _gps() async {
    setState(() {
      _busy = true;
      _msg = 'Buscando la posición…';
    });
    try {
      final p = await currentPosition();
      final name = await placeName(p);
      g
        ..here = p
        ..placeName = name == null ? 'Mi posición' : '$name (GPS)';
      _msg = 'Ubicación fijada: ${g.placeName}';
      await _save();
    } catch (e) {
      setState(() => _msg = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _byName() async {
    final t = _place.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _busy = true;
      _msg = 'Buscando «$t»…';
    });
    try {
      final r = await geocode(t);
      if (r == null) {
        setState(() => _msg = 'No se encontró «$t».');
      } else {
        g
          ..here = r.$1
          ..placeName = r.$2;
        _msg = 'Ubicación fijada: ${r.$2}';
        await _save();
      }
    } catch (e) {
      setState(() => _msg = 'Sin conexión con el mapa: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(
        child: ListTile(
          leading: const Icon(Icons.my_location),
          title: Text(g.here == null ? 'Sin ubicación' : g.placeName),
          subtitle: Text(g.here == null
              ? 'Sin ubicación se usan todos los precios de la base, sin filtrar por distancia.'
              : '${g.here!.lat.toStringAsFixed(4)}, ${g.here!.lon.toStringAsFixed(4)}'),
          trailing: g.here == null
              ? null
              : IconButton(
                  tooltip: 'Quitar ubicación',
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    g
                      ..here = null
                      ..placeName = '';
                    _save();
                  }),
        ),
      ),
      FilledButton.icon(
        onPressed: _busy ? null : _gps,
        icon: const Icon(Icons.gps_fixed),
        label: const Text('Usar mi ubicación actual'),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: TextField(controller: _place, decoration: const InputDecoration(labelText: 'O escribe la población (p. ej. Vitoria-Gasteiz)'), onSubmitted: (_) => _byName())),
        IconButton(onPressed: _busy ? null : _byName, icon: const Icon(Icons.search)),
      ]),
      if (_msg.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(_msg)),
      const SizedBox(height: 12),
      Text('Radio de alcance: ${_n(g.radiusKm, 0)} km', style: Theme.of(context).textTheme.titleMedium),
      Slider(
        value: g.radiusKm.clamp(5, 300),
        min: 5,
        max: 300,
        divisions: 59,
        label: '${_n(g.radiusKm, 0)} km',
        onChanged: (v) => setState(() => g.radiusKm = v),
        onChangeEnd: (_) => _save(),
      ),
      SwitchListTile(
        title: const Text('Usar también proveedores sin ubicación'),
        subtitle: const Text('Facturas cuya dirección no se ha podido situar en el mapa'),
        value: g.includeUnlocated,
        onChanged: (v) {
          g.includeUnlocated = v;
          _save();
        },
      ),
      ListTile(
        title: const Text('Antigüedad máxima de los precios'),
        trailing: DropdownButton<int>(
          value: const [3, 6, 12, 24].contains(g.maxAgeMonths) ? g.maxAgeMonths : 12,
          items: [for (final m in const [3, 6, 12, 24]) DropdownMenuItem(value: m, child: Text('$m meses'))],
          onChanged: (m) {
            g.maxAgeMonths = m ?? 12;
            _save();
          },
        ),
      ),
      ListTile(
        title: const Text('Si hay varios proveedores'),
        trailing: DropdownButton<PricePolicy>(
          value: g.policy,
          items: [for (final p in PricePolicy.values) DropdownMenuItem(value: p, child: Text(p.label))],
          onChanged: (p) {
            g.policy = p ?? g.policy;
            _save();
          },
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------- Taller
class _RatesTab extends StatefulWidget {
  const _RatesTab();
  @override
  State<_RatesTab> createState() => _RatesTabState();
}

class _RatesTabState extends State<_RatesTab> {
  WorkshopRates get r => PriceStore.instance.rates;

  Widget _num(String label, double? value, String suffix, void Function(double?) set, {String? help}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        initialValue: value == null ? '' : _n(value, value < 1 ? 3 : 2),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, suffixText: suffix, helperText: help),
        onChanged: (t) {
          set(double.tryParse(t.replaceAll(',', '.')));
          PriceStore.instance.saveSettings();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(12), children: [
      Text('Precios de tu taller', style: Theme.of(context).textTheme.titleMedium),
      _num('Hora de taller', r.hourly, '€/h', (v) => r.hourly = v, help: 'Sin este dato la mano de obra queda sin precio'),
      _num('Hora de montaje en obra', r.siteHourly, '€/h', (v) => r.siteHourly = v, help: 'Vacío = la de taller'),
      _num('Gastos generales y beneficio', r.marginPct, '%', (v) => r.marginPct = v ?? 0),
      _num('IVA', r.vatPct, '%', (v) => r.vatPct = v ?? 21),
      const SizedBox(height: 12),
      Text('Rendimientos', style: Theme.of(context).textTheme.titleMedium),
      Text('Valores de partida orientativos: ajústalos con los tiempos reales de tu taller.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
      _num('Fabricación (corte, taladro, armado)', r.fabHoursPerKg, 'h/kg', (v) => r.fabHoursPerKg = v ?? r.fabHoursPerKg),
      _num('Soldadura', r.weldHoursPerM, 'h/m de cordón', (v) => r.weldHoursPerM = v ?? r.weldHoursPerM),
      _num('Montaje', r.siteHoursPerKg, 'h/kg', (v) => r.siteHoursPerKg = v ?? r.siteHoursPerKg),
      _num('Manos de pintura', r.paintCoats.toDouble(), 'manos', (v) => r.paintCoats = (v ?? 2).round().clamp(1, 5)),
      _num('Rendimiento de la pintura', r.paintM2PerL, 'm²/l por mano', (v) => r.paintM2PerL = v ?? r.paintM2PerL),
    ]);
  }
}
