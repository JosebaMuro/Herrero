import 'dart:math' as math;

import 'model.dart';
import 'pricing.dart';
import 'profiles.dart';

/// Presupuesto del proyecto a partir del despiece y de la base de precios.
///
/// Los precios de material salen de [PriceBook] (facturas, tarifas, webs de
/// distribuidores o precios metidos a mano), filtrados por radio alrededor de
/// la ubicación. Las horas salen de rendimientos del taller que el usuario
/// ajusta. Una línea sin precio no se inventa: queda marcada para completar.

/// Partes del presupuesto. Coinciden con las secciones que se imprimen por
/// separado (compras, taller, soldadura, montaje…).
enum BudgetSection { materiales, fabricacion, soldadura, acabados, montaje, otros }

extension BudgetSectionLabel on BudgetSection {
  String get label => switch (this) {
        BudgetSection.materiales => 'Materiales',
        BudgetSection.fabricacion => 'Fabricación en taller',
        BudgetSection.soldadura => 'Soldadura',
        BudgetSection.acabados => 'Acabados',
        BudgetSection.montaje => 'Montaje en obra',
        BudgetSection.otros => 'Otros',
      };
}

/// Tarifas y rendimientos del taller (ajustes de la app, comunes a todos los
/// proyectos). Los € los pone el usuario; los rendimientos traen un valor de
/// partida orientativo que conviene ajustar con los datos del propio taller.
class WorkshopRates {
  double? hourly; // €/h taller
  double? siteHourly; // €/h montaje (si es null, se usa la de taller)
  double fabHoursPerKg; // corte, taladro, armado y repaso
  double weldHoursPerM; // por metro de cordón (a ≈ 4–5 mm)
  double siteHoursPerKg; // montaje
  int paintCoats;
  double paintM2PerL; // rendimiento de la pintura por mano
  double marginPct; // gastos generales y beneficio
  double vatPct;

  WorkshopRates({
    this.hourly,
    this.siteHourly,
    this.fabHoursPerKg = 0.02,
    this.weldHoursPerM = 0.25,
    this.siteHoursPerKg = 0.012,
    this.paintCoats = 2,
    this.paintM2PerL = 8,
    this.marginPct = 0,
    this.vatPct = 21,
  });

  Map<String, Object?> toJson() => {
        if (hourly != null) 'hourly': hourly,
        if (siteHourly != null) 'siteHourly': siteHourly,
        'fabHoursPerKg': fabHoursPerKg,
        'weldHoursPerM': weldHoursPerM,
        'siteHoursPerKg': siteHoursPerKg,
        'paintCoats': paintCoats,
        'paintM2PerL': paintM2PerL,
        'marginPct': marginPct,
        'vatPct': vatPct,
      };

  static WorkshopRates fromJson(Map<String, Object?> j) {
    double? d(String k) => (j[k] as num?)?.toDouble();
    final def = WorkshopRates();
    return WorkshopRates(
      hourly: d('hourly'),
      siteHourly: d('siteHourly'),
      fabHoursPerKg: d('fabHoursPerKg') ?? def.fabHoursPerKg,
      weldHoursPerM: d('weldHoursPerM') ?? def.weldHoursPerM,
      siteHoursPerKg: d('siteHoursPerKg') ?? def.siteHoursPerKg,
      paintCoats: (j['paintCoats'] as num?)?.toInt() ?? def.paintCoats,
      paintM2PerL: d('paintM2PerL') ?? def.paintM2PerL,
      marginPct: d('marginPct') ?? def.marginPct,
      vatPct: d('vatPct') ?? def.vatPct,
    );
  }
}

class BudgetLine {
  final String key; // estable, para fijar a mano el precio de la línea
  final BudgetSection section;
  final String concept;
  final double qty;
  final PriceUnit unit;
  final MaterialRef? ref;
  final double? unitPrice;
  final PriceQuote? quote;
  final bool manual;
  final String note; // de dónde sale la cantidad o el precio

  const BudgetLine({
    required this.key,
    required this.section,
    required this.concept,
    required this.qty,
    required this.unit,
    this.ref,
    this.unitPrice,
    this.quote,
    this.manual = false,
    this.note = '',
  });

  double? get total => unitPrice == null ? null : unitPrice! * qty;
  bool get missing => unitPrice == null;

  String get origin {
    if (manual) return 'precio fijado en este proyecto';
    if (quote != null) return quote!.sourceText;
    return note;
  }
}

class Budget {
  final List<BudgetLine> lines;
  final WorkshopRates rates;
  final double extras; // transporte, grúa, medios auxiliares… (€)
  const Budget(this.lines, this.rates, {this.extras = 0});

  Iterable<BudgetLine> of(BudgetSection s) => lines.where((l) => l.section == s);
  double subtotalOf(BudgetSection s) => of(s).fold(0.0, (a, l) => a + (l.total ?? 0));
  double get direct => lines.fold(0.0, (a, l) => a + (l.total ?? 0)) + extras;
  double get margin => direct * rates.marginPct / 100;
  double get base => direct + margin;
  double get vat => base * rates.vatPct / 100;
  double get total => base + vat;
  List<BudgetLine> get missing => [for (final l in lines) if (l.missing) l];
  bool get complete => missing.isEmpty;
}

/// Ajustes del presupuesto guardados en el proyecto (`ProjectRecord.budget`).
class ProjectBudgetSettings {
  final Map<String, double> manualPrices; // clave de línea → precio unitario
  final double extras;
  final String extrasLabel;
  final double? marginPct; // si el proyecto usa otro margen que el general
  const ProjectBudgetSettings({this.manualPrices = const {}, this.extras = 0, this.extrasLabel = '', this.marginPct});

  Map<String, Object?> toJson() => {
        'prices': manualPrices,
        'extras': extras,
        if (extrasLabel.isNotEmpty) 'extrasLabel': extrasLabel,
        if (marginPct != null) 'margin': marginPct,
      };

  static ProjectBudgetSettings fromJson(Map<String, Object?> j) => ProjectBudgetSettings(
        manualPrices: {
          for (final e in ((j['prices'] as Map?) ?? const {}).entries)
            if (e.value is num) '${e.key}': (e.value as num).toDouble()
        },
        extras: (j['extras'] as num?)?.toDouble() ?? 0,
        extrasLabel: j['extrasLabel'] as String? ?? '',
        marginPct: (j['margin'] as num?)?.toDouble(),
      );
}

String _alloy(SteelGrade g) => switch (g.kind) {
      MaterialKind.stainless => 'INOX',
      MaterialKind.aluminium => 'ALU',
      _ => '',
    };

double _quadArea(Surface s) {
  // dos triángulos
  double tri(Vec3 a, Vec3 b, Vec3 c) {
    final ux = b.x - a.x, uy = b.y - a.y, uz = b.z - a.z;
    final vx = c.x - a.x, vy = c.y - a.y, vz = c.z - a.z;
    final cx = uy * vz - uz * vy, cy = uz * vx - ux * vz, cz = ux * vy - uy * vx;
    return 0.5 * math.sqrt(cx * cx + cy * cy + cz * cz);
  }

  return tri(s.a, s.b, s.c) + tri(s.a, s.c, s.d);
}

/// Calcula el presupuesto.
Budget buildBudget(
  Design d,
  PriceBook book,
  PriceQuery query,
  WorkshopRates rates, {
  ProjectBudgetSettings project = const ProjectBudgetSettings(),
}) {
  final lines = <BudgetLine>[];
  final alloy = _alloy(d.spec.grade);
  final densityF = d.spec.grade.density / 7850;

  void add({
    required String key,
    required BudgetSection section,
    required String concept,
    required double qty,
    required PriceUnit unit,
    MaterialRef? ref,
    double? kgPerUnit,
    double? fixedPrice,
    String note = '',
  }) {
    if (qty <= 0) return;
    final manual = project.manualPrices[key];
    PriceQuote? quote;
    double? price = manual ?? fixedPrice;
    if (manual == null && fixedPrice == null && ref != null) {
      quote = book.lookup(ref, unit, query, kgPerUnit: kgPerUnit);
      price = quote?.value;
    }
    lines.add(BudgetLine(
      key: key,
      section: section,
      concept: concept,
      qty: qty,
      unit: unit,
      ref: ref,
      unitPrice: price,
      quote: manual == null ? quote : null,
      manual: manual != null,
      note: price == null
          ? (fixedPrice == null && ref != null || note.isEmpty
              ? 'sin precio: añade una factura, una tarifa o fíjalo a mano${note.isEmpty ? '' : ' ($note)'}'
              : note)
          : note,
    ));
  }

  // --- Materiales: barras pedidas (con merma), chapas, tornillería ---------
  for (final st in d.stock) {
    final r = parseMaterial(st.profile.name);
    final ref = r == null ? null : MaterialRef(r.family, r.size, alloy);
    final kg = st.purchasedKg * densityF;
    add(
      key: 'perfil:${st.profile.name}',
      section: BudgetSection.materiales,
      concept: '${st.profile.name} · ${st.orderText}',
      qty: double.parse(kg.toStringAsFixed(1)),
      unit: PriceUnit.kg,
      ref: ref,
      kgPerUnit: st.profile.kgm * densityF, // kg por metro, para precios en €/m
      note: 'barras comerciales del plan de corte',
    );
  }
  final plateKg = <double, double>{};
  for (final p in d.plates) {
    plateKg[p.t] = (plateKg[p.t] ?? 0) + p.totalKg;
  }
  for (final e in (plateKg.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))) {
    final t = e.key.toStringAsFixed(e.key == e.key.roundToDouble() ? 0 : 1).replaceAll('.', ',');
    add(
      key: 'chapa:$t',
      section: BudgetSection.materiales,
      concept: 'Chapa $t mm (placas, cartelas y rigidizadores)',
      qty: double.parse((e.value * 1.15).toStringAsFixed(1)), // +15 % de recortes de oxicorte/plasma
      unit: PriceUnit.kg,
      ref: MaterialRef('CHAPA', t, alloy),
      note: 'incluye un 15 % de recortes',
    );
  }
  for (final b in d.bolts) {
    final ref = parseMaterial('${b.description} ${b.spec}');
    final r = ref == null ? null : MaterialRef(ref.family, ref.size, alloy.isEmpty ? '' : 'INOX');
    add(
      key: 'torn:${b.description}|${b.spec}',
      section: BudgetSection.materiales,
      concept: '${b.description}: ${b.spec}',
      qty: b.qty.toDouble(),
      unit: PriceUnit.ud,
      ref: r,
    );
  }
  // Cerramientos y suelos que no son chapa del despiece
  final areas = <SurfaceKind, double>{};
  for (final s in d.surfaces) {
    areas[s.kind] = (areas[s.kind] ?? 0) + _quadArea(s);
  }
  String? surfaceText(SurfaceKind k) => switch (k) {
        SurfaceKind.roof => 'Cubierta: ${d.spec.roofing}',
        SurfaceKind.wall => 'Cerramiento: ${d.spec.cladding.isEmpty ? d.spec.roofing : d.spec.cladding}',
        SurfaceKind.grating => 'Tramex / rejilla',
        SurfaceKind.mesh => 'Malla',
        SurfaceKind.glass => 'Vidrio laminado',
        SurfaceKind.panel => 'Paneles de relleno',
        _ => null,
      };
  for (final e in areas.entries) {
    final txt = surfaceText(e.key);
    if (txt == null || e.value < 0.05) continue;
    final ref = parseMaterial(txt);
    add(
      key: 'sup:${e.key.name}',
      section: BudgetSection.materiales,
      concept: txt,
      qty: double.parse((e.value * 1.05).toStringAsFixed(2)), // +5 % solapes y cortes
      unit: PriceUnit.m2,
      ref: ref,
      note: 'superficie del modelo + 5 %',
    );
  }

  // --- Fabricación ----------------------------------------------------------
  final kg = d.steelKg;
  add(
    key: 'mo:taller',
    section: BudgetSection.fabricacion,
    concept: 'Corte, taladro, armado y repaso (${(kg * rates.fabHoursPerKg).toStringAsFixed(1)} h)',
    qty: double.parse((kg * rates.fabHoursPerKg).toStringAsFixed(1)),
    unit: PriceUnit.servicio,
    fixedPrice: rates.hourly,
    note: rates.hourly == null ? 'falta el precio de la hora de taller (Ajustes del presupuesto)' : '${rates.fabHoursPerKg} h/kg',
  );

  // --- Soldadura --------------------------------------------------------
  final wm = d.weldMeters;
  add(
    key: 'mo:soldadura',
    section: BudgetSection.soldadura,
    concept: 'Soldadura ${wm.toStringAsFixed(1)} m de cordón (${(wm * rates.weldHoursPerM).toStringAsFixed(1)} h)',
    qty: double.parse((wm * rates.weldHoursPerM).toStringAsFixed(1)),
    unit: PriceUnit.servicio,
    fixedPrice: rates.hourly,
    note: rates.hourly == null ? 'falta el precio de la hora de taller' : '${rates.weldHoursPerM} h/m',
  );
  final electrode = d.welds.isNotEmpty && d.welds.every((w) => w.process.startsWith('111'));
  add(
    key: 'cons:hilo',
    section: BudgetSection.soldadura,
    concept: electrode ? 'Electrodos' : 'Hilo de soldadura${alloy == 'INOX' ? ' inoxidable' : (alloy == 'ALU' ? ' de aluminio' : '')}',
    qty: double.parse(d.consumableKg.toStringAsFixed(2)),
    unit: PriceUnit.kg,
    ref: MaterialRef(electrode ? 'ELECTRODO' : 'HILO', '', alloy),
  );

  // --- Acabados -------------------------------------------------------------
  final fin = d.spec.finish.toLowerCase();
  if (fin.contains('galvan')) {
    add(
      key: 'acab:galvanizado',
      section: BudgetSection.acabados,
      concept: 'Galvanizado en caliente (EN ISO 1461)',
      qty: double.parse(kg.toStringAsFixed(0)),
      unit: PriceUnit.kg,
      ref: const MaterialRef('GALVANIZADO'),
    );
  }
  if (fin.contains('pint') || fin.contains('lac') || fin.contains('esmalte') || fin.contains('imprim')) {
    final m2 = d.paintM2;
    final litres = m2 * rates.paintCoats / math.max(rates.paintM2PerL, 0.1);
    // con precio por m² (pintor) o por litro (pintura comprada)
    final perM2 = book.lookup(const MaterialRef('PINTURA'), PriceUnit.m2, query);
    if (perM2 != null || project.manualPrices.containsKey('acab:pintura_m2')) {
      add(
        key: 'acab:pintura_m2',
        section: BudgetSection.acabados,
        concept: 'Pintura (${rates.paintCoats} manos)',
        qty: double.parse(m2.toStringAsFixed(1)),
        unit: PriceUnit.m2,
        ref: const MaterialRef('PINTURA'),
      );
    } else {
      add(
        key: 'acab:pintura_l',
        section: BudgetSection.acabados,
        concept: 'Pintura: ${m2.toStringAsFixed(0)} m² × ${rates.paintCoats} manos ÷ ${rates.paintM2PerL} m²/l',
        qty: double.parse(litres.toStringAsFixed(1)),
        unit: PriceUnit.l,
        ref: const MaterialRef('PINTURA'),
      );
    }
  }

  // --- Montaje ---------------------------------------------------------------
  final siteRate = rates.siteHourly ?? rates.hourly;
  add(
    key: 'mo:montaje',
    section: BudgetSection.montaje,
    concept: 'Montaje en obra (${(kg * rates.siteHoursPerKg).toStringAsFixed(1)} h)',
    qty: double.parse((kg * rates.siteHoursPerKg).toStringAsFixed(1)),
    unit: PriceUnit.servicio,
    fixedPrice: siteRate,
    note: siteRate == null ? 'falta el precio de la hora de montaje' : '${rates.siteHoursPerKg} h/kg',
  );

  final effRates = project.marginPct == null
      ? rates
      : (WorkshopRates.fromJson(rates.toJson())..marginPct = project.marginPct!);
  return Budget(lines, effRates, extras: project.extras);
}

/// Texto para pedir precio a los distribuidores (correo o WhatsApp) con el
/// pedido de material del proyecto. Así el presupuesto se puede cerrar con
/// precios reales aunque no haya ninguna factura todavía.
String quoteRequestText(Design d, {String project = '', String site = ''}) {
  final sb = StringBuffer()
    ..writeln('Buenos días:')
    ..writeln()
    ..writeln('Les pedimos precio y plazo para el siguiente material'
        '${project.isEmpty ? '' : ' (obra: $project${site.isEmpty ? '' : ', $site'})'}:')
    ..writeln();
  final alloy = d.spec.grade.name;
  for (final st in d.stock) {
    sb.writeln('- ${st.profile.name} $alloy: ${st.orderText}');
  }
  final plateKg = <double, double>{};
  for (final p in d.plates) {
    plateKg[p.t] = (plateKg[p.t] ?? 0) + p.totalKg;
  }
  for (final e in plateKg.entries) {
    sb.writeln('- Chapa ${e.key.toStringAsFixed(0)} mm $alloy: ${(e.value * 1.15).toStringAsFixed(0)} kg aprox.');
  }
  for (final b in d.bolts) {
    sb.writeln('- ${b.spec}: ${b.qty} ud');
  }
  sb
    ..writeln()
    ..writeln('Indiquen por favor precio unitario (€/kg o €/m), portes y plazo de entrega.')
    ..writeln()
    ..writeln('Un saludo.');
  return sb.toString();
}
