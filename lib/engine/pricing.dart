import 'dart:math';

/// Base de precios del taller: proveedores y precios unitarios sacados de
/// facturas, tarifas, páginas web de distribuidores o metidos a mano.
///
/// Herrero no se inventa precios. Cada precio del presupuesto dice de dónde
/// sale (factura de tal proveedor, fecha y distancia). Si no hay ninguno, la
/// línea queda «sin precio» para que se complete.

// ---------------------------------------------------------------------------
// Normalización de materiales
// ---------------------------------------------------------------------------

/// Familia de material para casar una línea de factura con una pieza del
/// despiece. [category] agrupa familias que tienen un precio por kg parecido.
class MaterialFamily {
  final String key;
  final String label;
  final String category;
  const MaterialFamily(this.key, this.label, this.category);
}

const _laminado = 'laminado';
const _tubo = 'tubo';
const _chapa = 'chapa';
const _torn = 'tornillería';
const _cons = 'consumibles';
const _cerr = 'cerramientos';
const _acab = 'acabados';

const materialFamilies = <MaterialFamily>[
  MaterialFamily('IPE', 'Viga IPE', _laminado),
  MaterialFamily('IPN', 'Viga IPN', _laminado),
  MaterialFamily('HEA', 'Viga HEA', _laminado),
  MaterialFamily('HEB', 'Viga HEB', _laminado),
  MaterialFamily('HEM', 'Viga HEM', _laminado),
  MaterialFamily('UPN', 'Perfil UPN', _laminado),
  MaterialFamily('UPE', 'Perfil UPE', _laminado),
  MaterialFamily('L', 'Angular L', _laminado),
  MaterialFamily('T', 'Perfil T', _laminado),
  MaterialFamily('PLETINA', 'Pletina', _laminado),
  MaterialFamily('REDONDO', 'Redondo macizo', _laminado),
  MaterialFamily('CUADRADILLO', 'Cuadrado macizo', _laminado),
  MaterialFamily('SHS', 'Tubo cuadrado', _tubo),
  MaterialFamily('RHS', 'Tubo rectangular', _tubo),
  MaterialFamily('CHS', 'Tubo redondo', _tubo),
  MaterialFamily('CHAPA', 'Chapa lisa', _chapa),
  MaterialFamily('LAGRIMADA', 'Chapa lagrimada', _chapa),
  MaterialFamily('PERFORADA', 'Chapa perforada', _chapa),
  MaterialFamily('TRAMEX', 'Tramex / rejilla', _chapa),
  MaterialFamily('TORNILLO', 'Tornillo', _torn),
  MaterialFamily('ANCLAJE', 'Anclaje / perno', _torn),
  MaterialFamily('VARILLA', 'Varilla roscada', _torn),
  MaterialFamily('HILO', 'Hilo de soldar', _cons),
  MaterialFamily('ELECTRODO', 'Electrodo', _cons),
  MaterialFamily('GAS', 'Gas de protección', _cons),
  MaterialFamily('DISCO', 'Disco de corte / desbaste', _cons),
  MaterialFamily('SANDWICH', 'Panel sándwich', _cerr),
  MaterialFamily('GRECADA', 'Chapa grecada', _cerr),
  MaterialFamily('POLICARBONATO', 'Policarbonato', _cerr),
  MaterialFamily('VIDRIO', 'Vidrio', _cerr),
  MaterialFamily('MALLA', 'Malla', _cerr),
  MaterialFamily('GALVANIZADO', 'Galvanizado en caliente', _acab),
  MaterialFamily('PINTURA', 'Pintura / esmalte', _acab),
  MaterialFamily('IMPRIMACION', 'Imprimación', _acab),
  MaterialFamily('TRANSPORTE', 'Transporte / portes', 'servicios'),
];

MaterialFamily? familyOf(String key) => materialFamilies.where((f) => f.key == key).firstOrNull;

/// Material normalizado: aleación + familia + medida («INOX CHS 42,4x2»).
class MaterialRef {
  final String family;
  final String size; // '200', '80x3', '100x50x3', '10' (chapa), 'M16'…
  final String alloy; // '' acero al carbono, 'INOX', 'ALU'
  const MaterialRef(this.family, [this.size = '', this.alloy = '']);

  String get familyKey => alloy.isEmpty ? family : '$alloy $family';
  String get key => size.isEmpty ? familyKey : '$familyKey $size';
  String get category {
    final c = familyOf(family)?.category ?? 'otros';
    return alloy.isEmpty ? c : '$alloy $c';
  }

  @override
  String toString() => key;
  @override
  bool operator ==(Object other) => other is MaterialRef && other.key == key;
  @override
  int get hashCode => key.hashCode;
}

String _fold(String s) {
  const from = 'ÁÉÍÓÚÜÀÈÌÒÙÑÇáéíóúüàèìòùñçºª';
  const to = 'AEIOUUAEIOUNCaeiouuaeiouncoa';
  final sb = StringBuffer();
  for (final ch in s.split('')) {
    final i = from.indexOf(ch);
    sb.write(i >= 0 ? to[i] : ch);
  }
  return sb.toString().toUpperCase();
}

String _num(String s) {
  final v = double.tryParse(s.replaceAll(',', '.'));
  if (v == null) return s;
  final r = v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);
  return r.replaceAll('.', ',');
}

/// Reconoce el material de un texto de factura, tarifa o del despiece:
/// «VIGA IPE-200 S275JR», «TUBO EST. 80X80X3», «Tubo 80.40.2», «CHAPA LAM 10MM
/// 3000X1500», «ANGULO 50X50X5», «SHS 80x3», «R16», «Pletina 50x8»…
MaterialRef? parseMaterial(String text) {
  var t = _fold(text);
  // separadores de medidas: 80.80.3 / 80*80*3 / 80 X 80 X 3 → 80x80x3
  t = t.replaceAllMapped(RegExp(r'(\d)\s*[X\*×]\s*(?=\d)'), (m) => '${m[1]}x');
  t = t.replaceAllMapped(RegExp(r'(?<![\d,])(\d{2,3})\.(\d{2,3})\.(\d{1,2}(?:,\d)?)(?![\d.])'), (m) => '${m[1]}x${m[2]}x${m[3]}');
  t = t.replaceAllMapped(RegExp(r'([A-Z])-(\d)'), (m) => '${m[1]} ${m[2]}');
  t = t.replaceAll(RegExp(r'\s+'), ' ');

  final alloy = RegExp(r'\bINOX|\bAISI\b|\b30[4L]|\b316|\bA[24]-?70\b').hasMatch(t)
      ? 'INOX'
      : (RegExp(r'\bALUMINIO\b|\bALU\b|\b60[68]\d\b').hasMatch(t) ? 'ALU' : '');

  String? m1(String re) => RegExp(re).firstMatch(t)?.group(1);
  final dims3 = RegExp(r'(\d+(?:,\d+)?)x(\d+(?:,\d+)?)x(\d+(?:,\d+)?)').firstMatch(t);
  final dims2 = RegExp(r'(\d+(?:,\d+)?)x(\d+(?:,\d+)?)').firstMatch(t);

  // Servicios y acabados (antes que los perfiles: «galvanizado de IPE 200»)
  if (RegExp(r'\bGALVANIZ').hasMatch(t) && !RegExp(r'\b(TUBO|CHAPA|VIGA|IPE|HEB|PANEL|TORNILL)').hasMatch(t)) {
    return const MaterialRef('GALVANIZADO');
  }
  if (RegExp(r'\bPORTES?\b|\bTRANSPORTE\b').hasMatch(t)) return const MaterialRef('TRANSPORTE');

  // Vigas laminadas
  for (final f in ['IPE', 'IPN', 'HEA', 'HEB', 'HEM', 'UPN', 'UPE']) {
    final s = m1('\\b$f ?(\\d{2,4})\\b');
    if (s != null) return MaterialRef(f, s, alloy);
  }
  // Tubos (SHS / RHS / CHS)
  final shs = m1(r'\bSHS ?(\d+(?:x\d+(?:,\d+)?)+)');
  if (shs != null) {
    final p = shs.split('x');
    return p.length == 3 ? MaterialRef('SHS', '${_num(p[0])}x${_num(p[2])}', alloy) : MaterialRef('SHS', shs, alloy);
  }
  final rhs = m1(r'\bRHS ?(\d+x\d+x\d+(?:,\d+)?)');
  if (rhs != null) return MaterialRef('RHS', rhs, alloy);
  final chs = m1(r'\bCHS ?(\d+(?:,\d+)?x\d+(?:,\d+)?)');
  if (chs != null) return MaterialRef('CHS', chs, alloy);
  if (RegExp(r'\bTUBO|\bTUB\b|\bTUBULAR').hasMatch(t)) {
    final round = RegExp(r'\bREDOND|\bCIRC|Ø|\bDIAM|\bCHS\b').hasMatch(t);
    if (dims3 != null && !round) {
      final a = _num(dims3[1]!), b = _num(dims3[2]!), e = _num(dims3[3]!);
      return a == b ? MaterialRef('SHS', '${a}x$e', alloy) : MaterialRef('RHS', '${a}x${b}x$e', alloy);
    }
    if (dims2 != null) {
      return round
          ? MaterialRef('CHS', '${_num(dims2[1]!)}x${_num(dims2[2]!)}', alloy)
          : MaterialRef('SHS', '${_num(dims2[1]!)}x${_num(dims2[2]!)}', alloy);
    }
    return MaterialRef(round ? 'CHS' : 'SHS', '', alloy);
  }
  // Angulares
  if (RegExp(r'\bANGULO|\bANG\.|\bL ?\d').hasMatch(t) && dims2 != null) {
    if (dims3 != null) return MaterialRef('L', '${_num(dims3[1]!)}x${_num(dims3[3]!)}', alloy);
    return MaterialRef('L', '${_num(dims2[1]!)}x${_num(dims2[2]!)}', alloy);
  }
  if (RegExp(r'\bPLETINA|\bLLANTA|\bPLET\.').hasMatch(t)) {
    return MaterialRef('PLETINA', dims2 == null ? '' : '${_num(dims2[1]!)}x${_num(dims2[2]!)}', alloy);
  }
  if (RegExp(r'\bTRAMEX|\bREJILLA|\bTRAMEJ').hasMatch(t)) return MaterialRef('TRAMEX', '', alloy);
  if (RegExp(r'\bLAGRIMAD').hasMatch(t)) return MaterialRef('LAGRIMADA', m1(r'(\d+(?:,\d+)?) ?MM') ?? '', alloy);
  if (RegExp(r'\bPERFORAD').hasMatch(t)) return MaterialRef('PERFORADA', m1(r'(\d+(?:,\d+)?) ?MM') ?? '', alloy);
  if (RegExp(r'\bSANDWICH|\bPANEL').hasMatch(t)) return const MaterialRef('SANDWICH');
  if (RegExp(r'\bGRECAD|\bTRAPEZ').hasMatch(t)) return const MaterialRef('GRECADA');
  if (RegExp(r'\bPOLICARBON').hasMatch(t)) return const MaterialRef('POLICARBONATO');
  if (RegExp(r'\bVIDRIO|\bLAMINAR|\bCRISTAL').hasMatch(t)) return const MaterialRef('VIDRIO');
  if (RegExp(r'\bMALLA|\bMALLAZO').hasMatch(t)) return MaterialRef('MALLA', '', alloy);
  if (RegExp(r'\bCHAPA|\bPLANCHA|\bFLEJE').hasMatch(t)) {
    // espesor: «10MM», «E=10», «ESP. 10» o la medida menor de 3000x1500x10
    var e = m1(r'(?:\bE ?=|\bESP\.? ?|\bESPESOR ?)(\d+(?:,\d+)?)') ?? m1(r'(\d+(?:,\d+)?) ?MM\b');
    if (e == null && dims3 != null) {
      final vs = [dims3[1]!, dims3[2]!, dims3[3]!]..sort((a, b) =>
          double.parse(a.replaceAll(',', '.')).compareTo(double.parse(b.replaceAll(',', '.'))));
      e = vs.first;
    }
    return MaterialRef('CHAPA', e == null ? '' : _num(e), alloy);
  }
  final red = m1(r'\bREDONDO (?:MACIZO |LISO |CORRUGADO )?(?:DE |Ø ?)?(\d{1,3})\b') ?? m1(r'\bR ?(\d{1,2})\b(?!x)');
  if (red != null && !RegExp(r'\bTUBO').hasMatch(t)) return MaterialRef('REDONDO', red, alloy);
  if (RegExp(r'\bCUADRADILLO|\bCUADRADO MACIZO').hasMatch(t)) {
    return MaterialRef('CUADRADILLO', m1(r'(\d{1,3})') ?? '', alloy);
  }
  if (RegExp(r'\bHILO|\bBOBINA').hasMatch(t) && RegExp(r'SOLD|MAG|MIG|ER70|G3SI|SG2|TUBULAR|\bHILO\b').hasMatch(t)) {
    return MaterialRef('HILO', m1(r'(\d,\d) ?(?:MM)?') ?? '', alloy);
  }
  if (RegExp(r'\bELECTRODO|E ?7018|E ?6013').hasMatch(t)) return MaterialRef('ELECTRODO', m1(r'(\d,\d{1,2})') ?? '', alloy);
  if (RegExp(r'\bARGON|\bCO2\b|\bMEZCLA|\bBOTELLA').hasMatch(t)) return const MaterialRef('GAS');
  if (RegExp(r'\bDISCO').hasMatch(t)) return const MaterialRef('DISCO');
  final metric = m1(r'\bM ?(\d{1,2})(?!\d)');
  if (RegExp(r'\bVARILLA').hasMatch(t)) return MaterialRef('VARILLA', metric == null ? '' : 'M$metric', alloy);
  if (RegExp(r'\bANCLAJE|\bTACO QUIM|\bPERNO|\bESPARRAGO').hasMatch(t)) {
    return MaterialRef('ANCLAJE', metric == null ? '' : 'M$metric', alloy);
  }
  if (RegExp(r'\bTORNILL|\bTUERCA|\bARANDELA|\bDIN 93[13]|\bISO 401[47]').hasMatch(t) ||
      (metric != null && RegExp(r'\b8[.,]8\b|\b10[.,]9\b').hasMatch(t))) {
    return MaterialRef('TORNILLO', metric == null ? '' : 'M$metric', alloy);
  }
  if (RegExp(r'\bIMPRIMACION|\bMINIO').hasMatch(t)) return const MaterialRef('IMPRIMACION');
  if (RegExp(r'\bPINTURA|\bESMALTE|\bLACADO|\bOXIRON').hasMatch(t)) return const MaterialRef('PINTURA');
  if (RegExp(r'\bGALVANIZ').hasMatch(t)) return const MaterialRef('GALVANIZADO');
  return null;
}

// ---------------------------------------------------------------------------
// Proveedores y precios
// ---------------------------------------------------------------------------

enum PriceUnit { kg, m, ud, m2, l, servicio }

extension PriceUnitLabel on PriceUnit {
  String get label => switch (this) {
        PriceUnit.kg => '€/kg',
        PriceUnit.m => '€/m',
        PriceUnit.ud => '€/ud',
        PriceUnit.m2 => '€/m²',
        PriceUnit.l => '€/l',
        PriceUnit.servicio => '€',
      };
  String get short => switch (this) {
        PriceUnit.kg => 'kg',
        PriceUnit.m => 'm',
        PriceUnit.ud => 'ud',
        PriceUnit.m2 => 'm²',
        PriceUnit.l => 'l',
        PriceUnit.servicio => 'ud',
      };
}

PriceUnit parseUnit(String s) {
  final t = _fold(s).trim();
  if (RegExp(r'^(KG|KGS|KILO|KILOS|K)$').hasMatch(t)) return PriceUnit.kg;
  if (RegExp(r'^(M2|MT2|M²)$').hasMatch(t)) return PriceUnit.m2;
  if (RegExp(r'^(M|ML|MTS?|METROS?)$').hasMatch(t)) return PriceUnit.m;
  if (RegExp(r'^(L|LT|LTS|LITROS?)$').hasMatch(t)) return PriceUnit.l;
  return PriceUnit.ud;
}

class GeoPoint {
  final double lat, lon;
  const GeoPoint(this.lat, this.lon);

  /// Distancia en km (haversine).
  double distanceTo(GeoPoint o) {
    const r = 6371.0;
    double rad(double d) => d * pi / 180;
    final dLat = rad(o.lat - lat), dLon = rad(o.lon - lon);
    final a = sin(dLat / 2) * sin(dLat / 2) + cos(rad(lat)) * cos(rad(o.lat)) * sin(dLon / 2) * sin(dLon / 2);
    return 2 * r * asin(min(1, sqrt(a)));
  }

  Map<String, Object?> toJson() => {'lat': lat, 'lon': lon};
  static GeoPoint? fromJson(Object? j) {
    if (j is! Map) return null;
    final la = j['lat'], lo = j['lon'];
    return la is num && lo is num ? GeoPoint(la.toDouble(), lo.toDouble()) : null;
  }
}

enum SupplierSource { factura, mapa, manual }

class Supplier {
  final String id;
  String name;
  String cif;
  String address;
  GeoPoint? location;
  String phone;
  String email;
  String web;

  /// Página de tarifas del distribuidor (opcional) para leer sus precios.
  String priceUrl;
  SupplierSource source;

  Supplier({
    required this.id,
    required this.name,
    this.cif = '',
    this.address = '',
    this.location,
    this.phone = '',
    this.email = '',
    this.web = '',
    this.priceUrl = '',
    this.source = SupplierSource.manual,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        if (cif.isNotEmpty) 'cif': cif,
        if (address.isNotEmpty) 'addr': address,
        if (location != null) 'loc': location!.toJson(),
        if (phone.isNotEmpty) 'tel': phone,
        if (email.isNotEmpty) 'mail': email,
        if (web.isNotEmpty) 'web': web,
        if (priceUrl.isNotEmpty) 'purl': priceUrl,
        'src': source.name,
      };

  static Supplier fromJson(Map<String, Object?> j) => Supplier(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        cif: j['cif'] as String? ?? '',
        address: j['addr'] as String? ?? '',
        location: GeoPoint.fromJson(j['loc']),
        phone: j['tel'] as String? ?? '',
        email: j['mail'] as String? ?? '',
        web: j['web'] as String? ?? '',
        priceUrl: j['purl'] as String? ?? '',
        source: SupplierSource.values.firstWhere((s) => s.name == j['src'], orElse: () => SupplierSource.manual),
      );
}

enum PriceSource { factura, tarifa, web, manual }

extension PriceSourceLabel on PriceSource {
  String get label => switch (this) {
        PriceSource.factura => 'factura',
        PriceSource.tarifa => 'tarifa',
        PriceSource.web => 'web del distribuidor',
        PriceSource.manual => 'precio manual',
      };
}

class PriceEntry {
  final String supplierId;
  final String ref; // MaterialRef.key
  final String description;
  final PriceUnit unit;
  final double price; // € sin IVA por unidad, con el descuento aplicado
  final DateTime date;
  final PriceSource source;
  final String doc; // nº de factura, nombre del archivo o URL

  const PriceEntry({
    required this.supplierId,
    required this.ref,
    required this.description,
    required this.unit,
    required this.price,
    required this.date,
    required this.source,
    this.doc = '',
  });

  Map<String, Object?> toJson() => {
        's': supplierId,
        'r': ref,
        'd': description,
        'u': unit.name,
        'p': price,
        't': date.toIso8601String().substring(0, 10),
        'o': source.name,
        if (doc.isNotEmpty) 'doc': doc,
      };

  static PriceEntry fromJson(Map<String, Object?> j) => PriceEntry(
        supplierId: j['s'] as String,
        ref: j['r'] as String,
        description: j['d'] as String? ?? '',
        unit: PriceUnit.values.firstWhere((u) => u.name == j['u'], orElse: () => PriceUnit.ud),
        price: (j['p'] as num).toDouble(),
        date: DateTime.tryParse(j['t'] as String? ?? '') ?? DateTime(2000),
        source: PriceSource.values.firstWhere((s) => s.name == j['o'], orElse: () => PriceSource.manual),
        doc: j['doc'] as String? ?? '',
      );
}

/// Cómo elegir entre varios proveedores con precio para el mismo material.
enum PricePolicy { mediana, masBarato, masReciente }

extension PricePolicyLabel on PricePolicy {
  String get label => switch (this) {
        PricePolicy.mediana => 'Mediana de los proveedores',
        PricePolicy.masBarato => 'El más barato',
        PricePolicy.masReciente => 'El más reciente',
      };
}

/// Grado de coincidencia del precio encontrado con el material pedido.
enum MatchLevel { exacto, familia, categoria }

extension MatchLevelLabel on MatchLevel {
  String get label => switch (this) {
        MatchLevel.exacto => 'misma medida',
        MatchLevel.familia => 'otra medida de la misma familia (€/kg)',
        MatchLevel.categoria => 'material parecido (€/kg)',
      };
}

/// Filtro geográfico y de antigüedad para buscar precios.
class PriceQuery {
  final GeoPoint? here;
  final double radiusKm;

  /// Si se usan precios de proveedores sin ubicación conocida (p. ej. una
  /// factura sin dirección legible). Por defecto sí: son del propio taller.
  final bool includeUnlocated;
  final int maxAgeMonths;
  final PricePolicy policy;
  final DateTime? now;
  const PriceQuery({
    this.here,
    this.radiusKm = 50,
    this.includeUnlocated = true,
    this.maxAgeMonths = 12,
    this.policy = PricePolicy.mediana,
    this.now,
  });
}

/// Precio elegido para un material, con su procedencia.
class PriceQuote {
  final double value;
  final PriceUnit unit;
  final MatchLevel level;
  final PriceEntry entry;
  final Supplier? supplier;
  final double? distanceKm;
  final int candidates; // proveedores que tenían precio

  const PriceQuote({
    required this.value,
    required this.unit,
    required this.level,
    required this.entry,
    this.supplier,
    this.distanceKm,
    this.candidates = 1,
  });

  String get sourceText {
    final f = entry.date;
    final date = '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';
    final who = supplier?.name ?? 'proveedor';
    final dist = distanceKm == null ? '' : ', a ${distanceKm!.toStringAsFixed(0)} km';
    final lvl = level == MatchLevel.exacto ? '' : ' · ${level.label}';
    final n = candidates > 1 ? ' · $candidates proveedores' : '';
    return '${entry.source.label} $who $date$dist$lvl$n';
  }
}

class PriceBook {
  final Map<String, Supplier> suppliers;
  final List<PriceEntry> entries;
  PriceBook({Map<String, Supplier>? suppliers, List<PriceEntry>? entries})
      : suppliers = suppliers ?? {},
        entries = entries ?? [];

  Map<String, Object?> toJson() => {
        'v': 1,
        'suppliers': [for (final s in suppliers.values) s.toJson()],
        'prices': [for (final e in entries) e.toJson()],
      };

  static PriceBook fromJson(Map<String, Object?> j) => PriceBook(
        suppliers: {
          for (final s in (j['suppliers'] as List?) ?? const [])
            (s as Map)['id'] as String: Supplier.fromJson(s.cast<String, Object?>())
        },
        entries: [for (final e in (j['prices'] as List?) ?? const []) PriceEntry.fromJson((e as Map).cast<String, Object?>())],
      );

  static int _seq = 0;
  static String newSupplierId() =>
      's${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${(_seq++).toRadixString(36)}';

  /// Busca un proveedor por CIF o por nombre parecido (para no duplicar al
  /// importar varias facturas del mismo).
  Supplier? findSupplier({String cif = '', String name = ''}) {
    final c = cif.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    if (c.isNotEmpty) {
      for (final s in suppliers.values) {
        if (s.cif.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase() == c) return s;
      }
    }
    final n = _simpleName(name);
    if (n.length >= 4) {
      for (final s in suppliers.values) {
        if (_simpleName(s.name) == n) return s;
      }
    }
    return null;
  }

  static String _simpleName(String n) => _fold(n)
      .replaceAll(RegExp(r'\b(S\.?L\.?U?|S\.?A\.?U?|S\.?COOP|SOCIEDAD LIMITADA|SOCIEDAD ANONIMA)\b\.?'), '')
      .replaceAll(RegExp(r'[^A-Z0-9]'), '');

  Supplier upsertSupplier(Supplier s) {
    final ex = findSupplier(cif: s.cif, name: s.name) ?? suppliers[s.id];
    if (ex == null) {
      suppliers[s.id] = s;
      return s;
    }
    if (ex.cif.isEmpty) ex.cif = s.cif;
    if (ex.address.isEmpty) ex.address = s.address;
    ex.location ??= s.location;
    if (ex.phone.isEmpty) ex.phone = s.phone;
    if (ex.email.isEmpty) ex.email = s.email;
    if (ex.web.isEmpty) ex.web = s.web;
    return ex;
  }

  /// Añade precios. Si ya había uno del mismo proveedor, material, unidad y
  /// fecha se sustituye; además se guardan como mucho 6 precios por
  /// proveedor y material (los más recientes) para que la base no crezca
  /// sin límite.
  void addPrices(Iterable<PriceEntry> news) {
    for (final e in news) {
      entries.removeWhere((o) =>
          o.supplierId == e.supplierId && o.ref == e.ref && o.unit == e.unit && _sameDay(o.date, e.date));
      entries.add(e);
    }
    final groups = <String, List<PriceEntry>>{};
    for (final e in entries) {
      groups.putIfAbsent('${e.supplierId}|${e.ref}|${e.unit.name}', () => []).add(e);
    }
    entries
      ..clear()
      ..addAll([
        for (final g in groups.values) ...(g..sort((a, b) => b.date.compareTo(a.date))).take(6),
      ]);
  }

  void removeSupplier(String id) {
    suppliers.remove(id);
    entries.removeWhere((e) => e.supplierId == id);
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// Precio para [ref]. [kgPerUnit] convierte entre €/kg y €/m (kg/m del
  /// perfil) o €/ud; si es null solo valen precios en la misma unidad.
  /// [want] es la unidad en que se quiere el resultado.
  PriceQuote? lookup(MaterialRef ref, PriceUnit want, PriceQuery q, {double? kgPerUnit}) {
    final now = q.now ?? DateTime.now();
    final oldest = DateTime(now.year, now.month - q.maxAgeMonths, now.day);

    // proveedor → distancia (o null si no tiene ubicación); fuera del radio no cuenta
    double? dist(Supplier? s) => (s?.location == null || q.here == null) ? null : q.here!.distanceTo(s!.location!);
    bool inRange(Supplier? s) {
      if (s == null) return q.includeUnlocated;
      if (s.location == null || q.here == null) return q.includeUnlocated || q.here == null;
      return dist(s)! <= q.radiusKm;
    }

    // Convierte un precio a la unidad pedida (null si no se puede).
    double? convert(PriceEntry e) {
      if (e.unit == want) return e.price;
      if (kgPerUnit == null || kgPerUnit <= 0) return null;
      if (e.unit == PriceUnit.kg && want != PriceUnit.kg) return e.price * kgPerUnit;
      if (want == PriceUnit.kg && e.unit != PriceUnit.kg) return e.price / kgPerUnit;
      return null;
    }

    for (final level in MatchLevel.values) {
      final matches = <PriceEntry>[];
      for (final e in entries) {
        if (e.date.isBefore(oldest)) continue;
        if (!inRange(suppliers[e.supplierId])) continue;
        final r = parseRefKey(e.ref);
        final ok = switch (level) {
          MatchLevel.exacto => e.ref == ref.key,
          // otra medida: solo por kg (el €/kg de una familia es parecido)
          MatchLevel.familia => r.familyKey == ref.familyKey && e.unit == PriceUnit.kg && ref.size.isNotEmpty,
          MatchLevel.categoria =>
            r.category == ref.category && e.unit == PriceUnit.kg && _kgCategories.contains(familyOf(ref.family)?.category),
        };
        if (ok && convert(e) != null) matches.add(e);
      }
      if (matches.isEmpty) continue;
      // el más reciente de cada proveedor
      final bySupplier = <String, PriceEntry>{};
      for (final e in matches) {
        final o = bySupplier[e.supplierId];
        if (o == null || e.date.isAfter(o.date)) bySupplier[e.supplierId] = e;
      }
      final list = bySupplier.values.toList()..sort((a, b) => convert(a)!.compareTo(convert(b)!));
      final PriceEntry pick = switch (q.policy) {
        PricePolicy.masBarato => list.first,
        PricePolicy.masReciente => (list.toList()..sort((a, b) => b.date.compareTo(a.date))).first,
        PricePolicy.mediana => list[(list.length - 1) ~/ 2],
      };
      final s = suppliers[pick.supplierId];
      return PriceQuote(
        value: convert(pick)!,
        unit: want,
        level: level,
        entry: pick,
        supplier: s,
        distanceKm: dist(s),
        candidates: list.length,
      );
    }
    return null;
  }

  /// Proveedores dentro del radio (los que no tienen ubicación, al final).
  List<(Supplier, double?)> suppliersNear(GeoPoint? here, double radiusKm) {
    final out = <(Supplier, double?)>[];
    for (final s in suppliers.values) {
      final d = (s.location == null || here == null) ? null : here.distanceTo(s.location!);
      if (d == null || d <= radiusKm) out.add((s, d));
    }
    out.sort((a, b) => (a.$2 ?? 1e9).compareTo(b.$2 ?? 1e9));
    return out;
  }
}

const _kgCategories = {_laminado, _tubo, _chapa};

/// Vuelve a construir un [MaterialRef] desde su clave guardada.
MaterialRef parseRefKey(String key) {
  final p = key.split(' ');
  var i = 0;
  var alloy = '';
  if (p.isNotEmpty && (p[0] == 'INOX' || p[0] == 'ALU')) {
    alloy = p[0];
    i = 1;
  }
  final fam = i < p.length ? p[i] : '';
  final size = p.skip(i + 1).join(' ');
  return MaterialRef(fam, size, alloy);
}
