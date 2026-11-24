import '../plans/plan_token.dart';
import 'pricing.dart';

/// Lectura de facturas y tarifas de proveedores a partir de su texto (el
/// texto de un PDF o el OCR de una foto). Se queda con lo que se puede
/// comprobar: una línea solo cuenta como línea de material si cantidad ×
/// precio (− descuento) cuadra con el importe, o si es una tarifa con
/// «€/kg», «€/m», etc. Todo lo leído se enseña para revisarlo antes de
/// guardarlo.

class InvoiceLine {
  String description;
  double qty;
  PriceUnit unit;
  double unitPrice; // € sin IVA por unidad, con el descuento aplicado
  double discountPct;
  double amount;
  MaterialRef? ref;
  bool selected;

  InvoiceLine({
    required this.description,
    required this.qty,
    required this.unit,
    required this.unitPrice,
    this.discountPct = 0,
    required this.amount,
    this.ref,
    this.selected = true,
  });
}

class ParsedInvoice {
  String supplierName;
  String cif;
  String address;
  String phone;
  String email;
  DateTime? date;
  String number;
  bool isPriceList; // tarifa en lugar de factura
  final List<InvoiceLine> lines;

  ParsedInvoice({
    this.supplierName = '',
    this.cif = '',
    this.address = '',
    this.phone = '',
    this.email = '',
    this.date,
    this.number = '',
    this.isPriceList = false,
    List<InvoiceLine>? lines,
  }) : lines = lines ?? [];

  /// Precios para la base de datos (solo líneas marcadas y con material).
  List<PriceEntry> toPrices(String supplierId, {String doc = '', DateTime? fallbackDate}) => [
        for (final l in lines)
          if (l.selected && l.ref != null && l.unitPrice > 0)
            PriceEntry(
              supplierId: supplierId,
              ref: l.ref!.key,
              description: l.description,
              unit: l.unit,
              price: double.parse(l.unitPrice.toStringAsFixed(4)),
              date: date ?? fallbackDate ?? DateTime.now(),
              source: isPriceList ? PriceSource.tarifa : PriceSource.factura,
              doc: doc.isNotEmpty ? doc : number,
            )
      ];
}

/// Número en formato español o inglés: «1.234,56», «12,5», «1234.56», «3».
double? parseNumber(String s) {
  var t = s.trim().replaceAll('€', '').replaceAll(' ', '');
  if (t.isEmpty) return null;
  final neg = t.startsWith('-');
  if (neg) t = t.substring(1);
  if (!RegExp(r'^\d[\d.,]*$').hasMatch(t)) return null;
  final lastComma = t.lastIndexOf(','), lastDot = t.lastIndexOf('.');
  if (lastComma >= 0 && lastDot >= 0) {
    // el último separador es el decimal
    t = lastComma > lastDot ? t.replaceAll('.', '').replaceAll(',', '.') : t.replaceAll(',', '');
  } else if (lastComma >= 0) {
    t = t.replaceAll(',', '.');
    if ('.'.allMatches(t).length > 1) return null;
  } else if (lastDot >= 0) {
    final dec = t.length - lastDot - 1;
    // «1.234» con varios puntos o 3 cifras tras el punto = miles
    if ('.'.allMatches(t).length > 1 || dec == 3) t = t.replaceAll('.', '');
  }
  final v = double.tryParse(t);
  return v == null ? null : (neg ? -v : v);
}

final _numTok = RegExp(r'(?<![\w,.])-?\d{1,3}(?:\.\d{3})*(?:,\d+)?(?![\w])|(?<![\w,.])-?\d+(?:[.,]\d+)?(?![\w])');
final _unitTok = RegExp(r'^(KG|KGS|KILOS?|M|ML|MTS?|METROS?|M2|UD|UDS|UN|UNID|PZA|PZAS|L|LT|LTS)\.?$', caseSensitive: false);

String _fold(String s) {
  const from = 'ÁÉÍÓÚÜÑáéíóúüñ';
  const to = 'AEIOUUNaeiouun';
  final sb = StringBuffer();
  for (final ch in s.split('')) {
    final i = from.indexOf(ch);
    sb.write(i >= 0 ? to[i] : ch);
  }
  return sb.toString().toUpperCase();
}

bool _close(double a, double b) => (a - b).abs() <= max(0.02, b.abs() * 0.015);
double max(double a, double b) => a > b ? a : b;

/// Intenta leer una línea de factura: «IPE 200 S275 12M  360,00 KG  1,15  414,00».
InvoiceLine? parseInvoiceLine(String raw) {
  final line = raw.replaceAll('€', ' ').replaceAll('\t', ' ').trim();
  if (line.length < 6) return null;
  final up = _fold(line);
  if (RegExp(r'^(TOTAL|SUBTOTAL|BASE|I\.?V\.?A|IMPORTE|SUMA|RECARGO|R\.?E\.?|RETENCION|IRPF|FORMA DE PAGO|VENCIMIENTO)').hasMatch(up)) {
    return null;
  }
  // tokens con su posición
  final toks = <(int, int, double)>[];
  for (final m in _numTok.allMatches(line)) {
    final v = parseNumber(m[0]!);
    if (v != null) toks.add((m.start, m.end, v));
  }
  if (toks.length < 3) return null;

  // Probamos los 2–4 últimos números como [cantidad, precio, (dto), importe]
  // de derecha a izquierda; el texto anterior al primero es la descripción.
  for (final withDto in [false, true]) {
    final need = withDto ? 4 : 3;
    if (toks.length < need) continue;
    final tail = toks.sublist(toks.length - need);
    final qty = tail[0].$3, price = tail[1].$3, amount = tail.last.$3;
    final dto = withDto ? tail[2].$3 : 0.0;
    if (qty <= 0 || price <= 0 || amount <= 0 || dto < 0 || dto >= 100) continue;
    if (!_close(qty * price * (1 - dto / 100), amount)) continue;
    final descEnd = tail[0].$1;
    var desc = line.substring(0, descEnd).trim();
    // unidad pegada a la cantidad («360,00 KG») o antes del precio
    var unit = PriceUnit.ud;
    final between = line.substring(tail[0].$2, tail[1].$1).trim();
    final unitWord = between.split(' ').where((w) => w.isNotEmpty).firstOrNull ?? '';
    if (_unitTok.hasMatch(unitWord)) {
      unit = parseUnit(unitWord.replaceAll('.', ''));
    } else {
      final lastWord = desc.split(' ').lastOrNull ?? '';
      if (_unitTok.hasMatch(lastWord) && desc.split(' ').length > 1) {
        unit = parseUnit(lastWord.replaceAll('.', ''));
        desc = desc.substring(0, desc.length - lastWord.length).trim();
      } else if (RegExp(r'\bKG\b|\bKILOS\b').hasMatch(_fold(desc))) {
        unit = PriceUnit.kg;
      }
    }
    // código de artículo al principio («0001234 VIGA IPE…»): se deja, ayuda a buscar
    if (desc.length < 3) continue;
    final ref = parseMaterial(desc);
    return InvoiceLine(
      description: desc,
      qty: qty,
      unit: unit,
      unitPrice: price * (1 - dto / 100),
      discountPct: dto,
      amount: amount,
      ref: ref,
      selected: ref != null,
    );
  }
  return null;
}

/// Línea de tarifa: «Tubo 80x80x3 ......... 1,32 €/kg», «IPE 200  24,50 €/m».
InvoiceLine? parsePriceListLine(String raw) {
  final m = RegExp(r'^(.*?)[\s.:]+(\d+(?:[.,]\d+)*)\s*(?:€|EUR|EUROS)\s*/\s*(KG|M2|ML|M|UD|UDS|UN|L)\b', caseSensitive: false)
      .firstMatch(raw.trim());
  if (m == null) return null;
  final price = parseNumber(m[2]!);
  final desc = m[1]!.trim();
  if (price == null || price <= 0 || desc.length < 3) return null;
  final ref = parseMaterial(desc);
  return InvoiceLine(
    description: desc,
    qty: 1,
    unit: parseUnit(m[3]!),
    unitPrice: price,
    amount: price,
    ref: ref,
    selected: ref != null,
  );
}

final _cifRe = RegExp(r'\b([ABCDEFGHJNPQRSUVW])[-\s.]?(\d{7})[-\s.]?([0-9A-J])\b');
final _nifRe = RegExp(r'\b(\d{8})[-\s]?([A-Z])\b');
final _dateRe = RegExp(r'\b(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})\b');
final _companyRe = RegExp(r'\b(S\.?\s?L\.?U?|S\.?\s?A\.?U?|S\.?\s?COOP\.?|SOCIEDAD LIMITADA|SOCIEDAD ANONIMA|C\.?B\.?)(?![A-Z])');
final _addrRe = RegExp(r'(?:^|[^A-Z])(?:C/|CALLE\b|AVDA\b|AVENIDA\b|POL\.|POLIGONO\b|PG\.|P\.I\.|CTRA\b|CARRETERA\b|PLAZA\b|PZA\.|CAMINO\b|PARCELA\b|NAVE\b)|\b\d{5}\b');

/// Lee el texto completo de una factura o tarifa.
ParsedInvoice parseInvoiceText(String text) {
  final lines = [for (final l in text.split(RegExp(r'\r?\n'))) l.trim()]..removeWhere((l) => l.isEmpty);
  final inv = ParsedInvoice();
  final up = [for (final l in lines) _fold(l)];

  // CIF: el primero que aparece suele ser el del emisor (proveedor)
  for (final l in up) {
    final m = _cifRe.firstMatch(l) ?? _nifRe.firstMatch(l);
    if (m != null) {
      inv.cif = m.groupCount == 3 ? '${m[1]}${m[2]}${m[3]}' : '${m[1]}${m[2]}';
      break;
    }
  }
  // Nombre del proveedor: primera línea con forma jurídica en la parte de
  // arriba; si no, la primera línea con letras que no sea un rótulo.
  final top = lines.length < 12 ? lines.length : (lines.length / 3).ceil().clamp(12, 40);
  for (var i = 0; i < top && i < lines.length; i++) {
    if (_companyRe.hasMatch(up[i]) && !RegExp(r'CLIENTE|DESTINATARIO|FACTURAR A|ENVIAR A').hasMatch(up[i])) {
      inv.supplierName = _cleanName(lines[i]);
      break;
    }
  }
  if (inv.supplierName.isEmpty) {
    for (var i = 0; i < top && i < lines.length; i++) {
      final u = up[i];
      if (RegExp(r'[A-Z]{3}').hasMatch(u) &&
          !RegExp(r'FACTURA|FECHA|CLIENTE|PAGINA|ALBARAN|TARIFA|PRESUPUESTO|N\.?I\.?F|C\.?I\.?F|TELEFONO|TLF|EMAIL|WWW|HTTP')
              .hasMatch(u)) {
        inv.supplierName = _cleanName(lines[i]);
        break;
      }
    }
  }
  // Dirección, teléfono, correo
  for (var i = 0; i < top && i < lines.length; i++) {
    if (inv.address.isEmpty && _addrRe.hasMatch(up[i]) && !_cifRe.hasMatch(up[i]) && RegExp(r'[A-Z]{3}').hasMatch(up[i])) {
      inv.address = lines[i];
      // el código postal y la población suelen ir en la línea siguiente
      if (i + 1 < lines.length && RegExp(r'\b\d{5}\b').hasMatch(up[i + 1]) && !RegExp(r'\b\d{5}\b').hasMatch(up[i])) {
        inv.address = '${lines[i]}, ${lines[i + 1]}';
      }
    }
    final tel = RegExp(r'(?:TEL[EÉ]?F?(?:ONO)?|TLF|TFNO|T\.)\.?:?\s*((?:\+34\s?)?[6789]\d{2}[\s.]?\d{2,3}[\s.]?\d{2,3}[\s.]?\d{0,3})').firstMatch(up[i]);
    if (inv.phone.isEmpty && tel != null) inv.phone = tel[1]!.trim();
    final mail = RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+').firstMatch(lines[i]);
    if (inv.email.isEmpty && mail != null) inv.email = mail[0]!;
  }
  // Fecha (preferimos la que va junto a «FECHA»)
  DateTime? toDate(RegExpMatch m) {
    var y = int.parse(m[3]!);
    if (y < 100) y += 2000;
    final mo = int.parse(m[2]!), d = int.parse(m[1]!);
    if (mo < 1 || mo > 12 || d < 1 || d > 31 || y < 2000 || y > 2100) return null;
    return DateTime(y, mo, d);
  }

  for (final l in up) {
    if (l.contains('FECHA')) {
      final m = _dateRe.firstMatch(l);
      if (m != null) inv.date = toDate(m);
      if (inv.date != null) break;
    }
  }
  if (inv.date == null) {
    for (final l in up) {
      final m = _dateRe.firstMatch(l);
      if (m != null && (inv.date = toDate(m)) != null) break;
    }
  }
  // Número de factura
  for (final l in up) {
    final m = RegExp(r'FACTURA\s*(?:N[ºO°.]*|NUM\.?|NUMERO)?\s*[:#]?\s*([A-Z]{0,4}[-/]?\d[\w\-/]*)').firstMatch(l) ??
        RegExp(r'\bN[ºO°]\s*(?:DE\s*)?FACTURA\s*[:#]?\s*([\w\-/]+)').firstMatch(l);
    if (m != null) {
      inv.number = m[1]!;
      break;
    }
  }
  inv.isPriceList = up.take(15).any((l) => RegExp(r'\bTARIFA|\bLISTA DE PRECIOS|\bPRECIOS? NETOS?').hasMatch(l)) &&
      !up.take(15).any((l) => RegExp(r'^FACTURA|\bFACTURA N').hasMatch(l));

  for (final l in lines) {
    final il = parseInvoiceLine(l) ?? parsePriceListLine(l);
    if (il != null) inv.lines.add(il);
  }
  if (inv.lines.isNotEmpty && inv.lines.every((l) => l.qty == 1 && l.amount == l.unitPrice)) inv.isPriceList = true;
  return inv;
}

String _cleanName(String s) => s.replaceAll(RegExp(r'\s{2,}'), ' ').replaceAll(RegExp(r'^[^\wÁÉÍÓÚÑ]+|[^\w.ÁÉÍÓÚÑ]+$'), '').trim();

/// Une los trozos de texto leídos (PDF u OCR) en líneas, de arriba abajo y
/// de izquierda a derecha, para pasarlas por [parseInvoiceText].
String tokensToText(List<PlanToken> tokens) {
  final toks = [for (final t in tokens) if (!t.vertical && t.text.trim().isNotEmpty) t]
    ..sort((a, b) => a.cy.compareTo(b.cy));
  final rows = <List<PlanToken>>[];
  for (final t in toks) {
    final last = rows.isEmpty ? null : rows.last;
    if (last != null) {
      final ref = last.first;
      final tol = 0.55 * (ref.h > 0 ? ref.h : 8);
      if ((t.cy - ref.cy).abs() <= tol) {
        last.add(t);
        continue;
      }
    }
    rows.add([t]);
  }
  final sb = StringBuffer();
  for (final r in rows) {
    r.sort((a, b) => a.x0.compareTo(b.x0));
    final line = StringBuffer();
    PlanToken? prev;
    for (final t in r) {
      if (prev != null) {
        // hueco grande entre columnas: dos espacios
        line.write(t.x0 - prev.x1 > (prev.h > 0 ? prev.h : 8) * 1.2 ? '  ' : ' ');
      }
      line.write(t.text.trim());
      prev = t;
    }
    sb.writeln(line.toString());
  }
  return sb.toString();
}
