import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../engine/budget.dart';
import '../engine/model.dart';
import '../engine/pricing.dart';
import '../services/price_store.dart';
import 'prices_screen.dart';

String eur(double v) {
  final s = v.toStringAsFixed(2);
  final p = s.split('.');
  final ent = p[0].replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.');
  return '$ent,${p[1]} €';
}

String _n(double v, [int d = 1]) => v.toStringAsFixed(d).replaceAll('.', ',');

/// Pestaña «Presupuesto» del proyecto.
class BudgetTab extends StatefulWidget {
  final Design d;
  final ProjectBudgetSettings settings;
  final ValueChanged<ProjectBudgetSettings> onSettings;
  final ValueChanged<Budget> onBudget;
  final VoidCallback onPrint;
  final String projectName;
  final String site;
  const BudgetTab({
    super.key,
    required this.d,
    required this.settings,
    required this.onSettings,
    required this.onBudget,
    required this.onPrint,
    this.projectName = '',
    this.site = '',
  });

  @override
  State<BudgetTab> createState() => _BudgetTabState();
}

class _BudgetTabState extends State<BudgetTab> {
  Budget? _b;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  @override
  void didUpdateWidget(BudgetTab old) {
    super.didUpdateWidget(old);
    if (old.d != widget.d || old.settings != widget.settings) _compute();
  }

  Future<void> _compute() async {
    final ps = PriceStore.instance;
    final book = await ps.book();
    final b = buildBudget(widget.d, book, ps.geo.query, ps.rates, project: widget.settings);
    if (!mounted) return;
    setState(() {
      _b = b;
      _loading = false;
    });
    widget.onBudget(b);
  }

  Future<void> _setPrice(BudgetLine l) async {
    final ctrl = TextEditingController(text: l.unitPrice == null ? '' : _n(l.unitPrice!, 3));
    final unit = l.unit == PriceUnit.servicio ? '€/h' : l.unit.label;
    final res = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.concept, maxLines: 3, overflow: TextOverflow.ellipsis),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Origen actual: ${l.origin}', style: Theme.of(c).textTheme.bodySmall),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Precio para este proyecto', suffixText: unit),
          ),
        ]),
        actions: [
          if (l.manual) TextButton(onPressed: () => Navigator.pop(c, ''), child: const Text('Quitar precio fijado')),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Fijar')),
        ],
      ),
    );
    if (res == null) return;
    final prices = Map<String, double>.from(widget.settings.manualPrices);
    final v = double.tryParse(res.replaceAll(',', '.'));
    if (res.isEmpty || v == null) {
      prices.remove(l.key);
    } else {
      prices[l.key] = v;
    }
    widget.onSettings(ProjectBudgetSettings(
        manualPrices: prices, extras: widget.settings.extras, extrasLabel: widget.settings.extrasLabel, marginPct: widget.settings.marginPct));
  }

  Future<void> _editExtras() async {
    final ctrl = TextEditingController(text: widget.settings.extras == 0 ? '' : _n(widget.settings.extras, 2));
    final margin = TextEditingController(text: widget.settings.marginPct == null ? '' : _n(widget.settings.marginPct!, 1));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Transporte, medios y margen'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Transporte, grúa y medios auxiliares', suffixText: '€'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: margin,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: 'Margen de este proyecto (vacío = el general)',
                suffixText: '%',
                helperText: 'General: ${_n(PriceStore.instance.rates.marginPct, 1)} %'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    widget.onSettings(ProjectBudgetSettings(
      manualPrices: widget.settings.manualPrices,
      extras: double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0,
      extrasLabel: widget.settings.extrasLabel,
      marginPct: double.tryParse(margin.text.replaceAll(',', '.')),
    ));
  }

  Future<void> _openPrices({int tab = 0}) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PricesScreen(initialTab: tab, design: widget.d, projectName: widget.projectName, site: widget.site)));
    await _compute();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final b = _b;
    if (_loading || b == null) return const Center(child: CircularProgressIndicator());
    final geo = PriceStore.instance.geo;
    final where = geo.here == null
        ? 'Sin ubicación: se usan todos los precios de la base'
        : '${geo.placeName.isEmpty ? 'Ubicación fijada' : geo.placeName} · radio ${_n(geo.radiusKm, 0)} km';
    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(
        child: ListTile(
          leading: const Icon(Icons.place_outlined),
          title: Text(where),
          subtitle: Text('${geo.policy.label} · precios de los últimos ${geo.maxAgeMonths} meses'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openPrices(tab: 2),
        ),
      ),
      if (!b.complete)
        Card(
          color: cs.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${b.missing.length} línea(s) sin precio (no suman en el total)',
                  style: TextStyle(color: cs.onErrorContainer, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                  'Herrero no se inventa precios. Importa una factura o tarifa de tu proveedor, pide precio a los '
                  'distribuidores de la zona con el pedido del proyecto, o toca la línea para fijarlo a mano.',
                  style: TextStyle(color: cs.onErrorContainer, fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.tonalIcon(
                    onPressed: () => _openPrices(tab: 0), icon: const Icon(Icons.receipt_long), label: const Text('Importar factura')),
                FilledButton.tonalIcon(
                    onPressed: () => _openPrices(tab: 1), icon: const Icon(Icons.store_mall_directory_outlined), label: const Text('Distribuidores cercanos')),
                FilledButton.tonalIcon(
                    onPressed: () => _openPrices(tab: 3), icon: const Icon(Icons.engineering_outlined), label: const Text('Tarifas del taller')),
              ]),
            ]),
          ),
        ),
      for (final s in BudgetSection.values)
        if (b.of(s).isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
            child: Row(children: [
              Expanded(child: Text(s.label, style: Theme.of(context).textTheme.titleMedium)),
              Text(eur(b.subtotalOf(s)), style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
          ),
          for (final l in b.of(s))
            Card(
              margin: const EdgeInsets.symmetric(vertical: 3),
              child: ListTile(
                dense: true,
                onTap: () => _setPrice(l),
                title: Text(l.concept),
                subtitle: Text(
                  '${_n(l.qty, l.qty < 10 ? 2 : 1)} ${l.unit == PriceUnit.servicio ? 'h' : l.unit.short}'
                  '${l.unitPrice == null ? '' : ' × ${_n(l.unitPrice!, 3)} €'}\n${l.origin}',
                  style: TextStyle(color: l.missing ? cs.error : null),
                ),
                isThreeLine: true,
                trailing: l.missing
                    ? Icon(Icons.edit_note, color: cs.error)
                    : Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(eur(l.total!), style: const TextStyle(fontWeight: FontWeight.bold)),
                        if (l.manual) Icon(Icons.push_pin, size: 14, color: cs.primary),
                      ]),
              ),
            ),
        ],
      const SizedBox(height: 10),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            _row('Coste directo', eur(b.direct - b.extras)),
            InkWell(onTap: _editExtras, child: _row('Transporte y medios auxiliares ✎', eur(b.extras))),
            InkWell(onTap: _editExtras, child: _row('Gastos generales y beneficio (${_n(b.rates.marginPct, 1)} %) ✎', eur(b.margin))),
            _row('Base imponible', eur(b.base), bold: true),
            _row('IVA (${_n(b.rates.vatPct, 0)} %)', eur(b.vat)),
            const Divider(),
            _row('TOTAL', eur(b.total), bold: true, big: true),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(onPressed: widget.onPrint, icon: const Icon(Icons.picture_as_pdf), label: const Text('Presupuesto en PDF')),
        OutlinedButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: quoteRequestText(widget.d, project: widget.projectName, site: widget.site)));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Pedido copiado: pégalo en un correo o WhatsApp al distribuidor.')));
            }
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copiar petición de precio'),
        ),
      ]),
      const SizedBox(height: 24),
    ]);
  }

  Widget _row(String k, String v, {bool bold = false, bool big = false}) {
    final st = TextStyle(fontWeight: bold ? FontWeight.bold : null, fontSize: big ? 18 : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [Expanded(child: Text(k, style: st)), Text(v, style: st)]),
    );
  }
}
