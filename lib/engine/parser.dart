import 'dart:math' as math;

import 'catalog.dart';
import 'model.dart';
import 'profiles.dart';
import 'spanish.dart';
import 'vocabulary.dart';

/// Normaliza el texto: minúsculas, sin tildes, coma decimal -> punto.
String normalize(String s) {
  const from = 'áàäâéèëêíìïîóòöôúùüûñç×';
  const to = 'aaaaeeeeiiiioooouuuuncx';
  final sb = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    sb.write(i >= 0 ? to[i] : ch);
  }
  return sb
      .toString()
      // separador de miles español: 10.000 -> 10000
      .replaceAllMapped(RegExp(r'(?<![\d.,])(\d{1,3})((?:\.\d{3})+)(?![\d.,])'),
          (m) => '${m[1]}${m[2]!.replaceAll('.', '')}')
      .replaceAllMapped(RegExp(r'(\d),(\d)'), (m) => '${m[1]}.${m[2]}');
}


String _fmt(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 2).replaceAll('.', ',');

double _toM(String n, String? unit) {
  final v = double.parse(n);
  switch (unit) {
    case 'mm':
      return v / 1000;
    case 'cm':
      return v / 100;
    default:
      return v;
  }
}

double? _find(String t, List<String> patterns) {
  for (final p in patterns) {
    final m = RegExp(p).firstMatch(t);
    if (m != null) {
      final n = m.namedGroup('n')!;
      final u = m.namedGroup('u');
      return _toM(n, u);
    }
  }
  return null;
}

String _kw(String words) => '(?:$words)';

/// Valor característico de nieve sk (kN/m²) para capitales (CTE DB-SE-AE
/// tabla 3.8, valores redondeados).
const Map<String, double> _snowCities = {
  'madrid': 0.6,
  'barcelona': 0.4,
  'valencia': 0.2,
  'sevilla': 0.2,
  'malaga': 0.2,
  'cadiz': 0.2,
  'murcia': 0.2,
  'alicante': 0.2,
  'bilbao': 0.3,
  'san sebastian': 0.3,
  'donostia': 0.3,
  'santander': 0.3,
  'coruna': 0.3,
  'vigo': 0.2,
  'oviedo': 0.5,
  'gijon': 0.2,
  'vitoria': 0.7,
  'gasteiz': 0.7,
  'pamplona': 0.7,
  'logrono': 0.6,
  'zaragoza': 0.5,
  'huesca': 0.7,
  'teruel': 0.9,
  'burgos': 0.6,
  'leon': 1.2,
  'valladolid': 0.4,
  'salamanca': 0.5,
  'segovia': 0.7,
  'avila': 1.0,
  'soria': 0.9,
  'cuenca': 1.0,
  'guadalajara': 0.6,
  'toledo': 0.5,
  'granada': 0.5,
  'jaen': 0.4,
  'cordoba': 0.2,
  'badajoz': 0.2,
  'caceres': 0.4,
  'lleida': 0.5,
  'lerida': 0.5,
  'girona': 0.4,
  'tarragona': 0.4,
  'castellon': 0.2,
  'palma': 0.2,
  'mallorca': 0.2,
  'tenerife': 0.2,
  'las palmas': 0.2,
  'canarias': 0.2,
};

/// Primera capital reconocida en el texto normalizado (para nieve/viento).
String? cityIn(String t) {
  for (final k in _snowCities.keys) {
    if (RegExp('(?<![a-z])$k(?![a-z])').hasMatch(t)) return k;
  }
  return null;
}

/// Zona eólica C (qb 0,52) para algunas zonas costeras/insulares.
const List<String> _windZoneC = [
  'canarias',
  'tenerife',
  'las palmas',
  'cadiz',
  'tarifa',
  'huelva',
  'coruna',
  'almeria',
];

/// Palabra clave de tipología más fuerte del texto: (tipología, peso, posición).
/// Gana la de más peso y, a igualdad, la que aparece antes (el sustantivo
/// principal suele ir primero). Lo que va como complemento («escalera con
/// barandilla», «nave y altillo») cuenta menos que lo pedido.
(StructureType?, int, int) keywordType(String t) {
  StructureType? best;
  var bestScore = -1e9;
  var weight = 0, at = 1 << 30;
  final component = RegExp(
      r'(?:con|sin|y|e|de|del|para|al|a|sobre|encima de|incluid[oa]s?|lleva|llevara|ademas de|mas)\s+(?:(?:una|un|unos|unas|el|la|los|las|su|sus|mi|mis)\s+)?$');
  for (final ty in typologies) {
    for (final e in ty.keywords.entries) {
      final m = RegExp('(?<![a-z])${RegExp.escape(e.key)}(?![a-z])').firstMatch(t);
      if (m == null) continue;
      final before = t.substring(math.max(0, m.start - 14), m.start);
      // «para depósito», «para polipasto»: la carga que sostiene define la estructura
      final purpose = _purposeKeys.contains(e.key) && RegExp(r'para\s+(?:(?:un|una|el|la|los|las)\s+)?$').hasMatch(before);
      final isPart = m.start > 0 && !purpose && component.hasMatch(before);
      final score = e.value * 1000.0 + e.key.length * 10 - m.start * 0.5 - (isPart ? 6000 : 0);
      if (score > bestScore) {
        bestScore = score;
        best = ty.type;
        weight = isPart ? math.max(1, e.value - 6) : e.value;
        at = m.start;
      }
    }
  }
  return (best, weight, at);
}

const _purposeKeys = {
  'deposito', 'aljibe', 'tanque', 'silo', 'polipasto', 'diferencial', 'cartel', 'letrero', 'bandera', 'rotulo', 'farola', 'antena',
};

/// Elige la tipología por palabras clave (ver [keywordType]).
StructureType detectType(String t, List<String> notes) {
  var (best, _, _) = keywordType(t);
  for (final h in unsupportedHints.entries) {
    if (RegExp('(?<![a-z])${RegExp.escape(h.key)}').hasMatch(t)) {
      notes.add(h.value.$2);
      best ??= h.value.$1;
      break;
    }
  }
  if (best == null) {
    // Sin tipología reconocible: se decide por la forma de la petición
    if (RegExp(r'kg/m|uso|oficina|almacenar').hasMatch(t)) {
      best = StructureType.entreplanta;
    } else if (RegExp(r'coche|vehiculo|sombra').hasMatch(t)) {
      best = StructureType.marquesina;
    } else {
      best = StructureType.nave;
    }
    notes.add('No se reconoce la tipología: se toma «${best.label}». Tipologías disponibles: '
        '${typologies.map((e) => e.type.label).join('; ')}.');
  }
  return best;
}

/// Forma pedida por el usuario en la ficha («variante caracol»), si la hay.
String? _forcedVariant(String t) => RegExp(r'variante ([a-z ]+?)\s*(?:[,.;]|$)').firstMatch(t)?[1]?.trim();

/// Forma de la escalera: recta, en L, en U, zanca central, caracol o escala de gato.
String stairForm(String t) {
  final f = _forcedVariant(t);
  if (f != null && stairForms.contains(f)) return f;
  if (RegExp(r'escala de gato').hasMatch(t)) return 'escala de gato';
  if (RegExp(r'caracol').hasMatch(t)) return 'caracol';
  if (RegExp(r'escalera en l(?![a-z])|(?<![a-z])en l(?![a-z0-9])|cuarto de vuelta|giro de 90').hasMatch(t)) return 'en l';
  if (RegExp(r'escalera en u(?![a-z])|(?<![a-z])en u(?![a-z0-9])|media vuelta|ida y vuelta|giro de 180').hasMatch(t)) return 'en u';
  if (RegExp(r'zanca central').hasMatch(t)) return 'zanca central';
  return 'recta';
}

const stairForms = ['recta', 'en l', 'en u', 'zanca central', 'caracol', 'escala de gato'];

/// Relleno de la barandilla o pasamanos a pared.
String railForm(String t) {
  final f = _forcedVariant(t);
  if (f != null && railForms.contains(f)) return f;
  if (t.contains('pasamanos a pared') ||
      (t.contains('pasamanos') && !RegExp(r'barandilla|antepecho|guardacuerpos|barrotes|montantes|vidrio|cables|peto').hasMatch(t))) {
    return 'pasamanos a pared';
  }
  if (t.contains('vidrio')) return 'vidrio';
  if (t.contains('cables')) return 'cables';
  if (t.contains('chapa perforada') || RegExp(r'(?<![a-z])chapa(?! lagrimada)').hasMatch(t)) return 'chapa perforada';
  if (RegExp(r'(?<![a-z])lamas?(?![a-z])').hasMatch(t)) return 'lamas';
  if (t.contains('barras horizontales')) return 'barras horizontales';
  return 'barrotes';
}

const railForms = ['barrotes', 'vidrio', 'cables', 'chapa perforada', 'lamas', 'barras horizontales', 'pasamanos a pared'];

/// ¿Es una reja de ventana (y no una valla de parcela)?
bool isWindowGrille(String t) {
  final f = _forcedVariant(t);
  if (f != null) return f == 'reja';
  return t.contains('reja de ventana') || (RegExp(r'(?<![a-z])rejas?(?![a-z])').hasMatch(t) && RegExp(r'ventana|balcon').hasMatch(t));
}

/// Interpreta el prompt en lenguaje natural y devuelve la especificación.
/// [type] fija la tipología (p. ej. la que ha decidido la comprensión IA).
StructureSpec parsePrompt(String prompt, {StructureType? type}) {
  final t = canonicalize(normalize(prompt));
  final notes = <String>[];
  final fixes = spanishNote(normalize(prompt));
  if (fixes != null) notes.add(fixes);

  // --- Tipo de estructura (catálogo de tipologías con sinónimos) ---------
  type ??= detectType(t, notes);

  // --- Dimensiones ---------------------------------------------------------
  double? length = _find(t, [
    '${_kw("largo|longitud|fondo|profundidad")}\\s*(?:total\\s*)?(?:de|:|=)?\\s*(?<n>\\d+(?:\\.\\d+)?)\\s*(?<u>mm|cm|m)?',
    '(?<n>\\d+(?:\\.\\d+)?)\\s*(?<u>mm|cm|m)?(?:etros?|ts?)?\\s*(?:de\\s+)?${_kw("largo|longitud|fondo|profundidad")}',
  ]);
  double? width = _find(t, [
    '${_kw("ancho|anchura|luz|vano libre")}\\s*(?:de|:|=)?\\s*(?<n>\\d+(?:\\.\\d+)?)\\s*(?<u>mm|cm|m)?',
    '(?<n>\\d+(?:\\.\\d+)?)\\s*(?<u>mm|cm|m)?(?:etros?|ts?)?\\s*(?:de\\s+)?${_kw("ancho|anchura|luz")}',
  ]);
  double? height = _find(t, [
    '${_kw("altura libre|altura al alero|altura de alero|altura|alto|alero|gálibo|galibo|cota")}\\s*(?:libre\\s*)?(?:de|:|=|a)?\\s*(?<n>\\d+(?:\\.\\d+)?)\\s*(?<u>mm|cm|m)?',
    '(?<n>\\d+(?:\\.\\d+)?)\\s*(?<u>mm|cm|m)?(?:etros?|ts?)?\\s*(?:de\\s+)?${_kw("alto|altura|libres?(?! de ancho)")}',
  ]);

  // Formato "A x B (x C)"
  final dimRe = RegExp(
      r'(\d+(?:\.\d+)?)\s*(mm|cm|m)?(?:etros?|ts?)?\s*(?:x|por|\*)\s*(\d+(?:\.\d+)?)\s*(mm|cm|m)?(?:etros?|ts?)?(?:\s*(?:x|por|\*)\s*(\d+(?:\.\d+)?)\s*(mm|cm|m)?)?');
  final dm = dimRe.firstMatch(t);
  if (dm != null) {
    final u2 = dm[4] ?? dm[2];
    final a = _toM(dm[1]!, dm[2] ?? u2);
    final b = _toM(dm[3]!, u2);
    final big = math.max(a, b), small = math.min(a, b);
    if (length == null && width == null) {
      length = big;
      width = small;
    } else if (length == null) {
      length = (width! - a).abs() < 1e-6 ? b : a;
    } else {
      width ??= (length - a).abs() < 1e-6 ? b : a;
    }
    if (dm[5] != null && height == null) {
      height = _toM(dm[5]!, dm[6] ?? u2);
    }
  }

  // Superficie "de 60 m2" sin dimensiones -> cuadrado aproximado
  final area = RegExp(r'(\d+(?:\.\d+)?)\s*(?:m2|m²|metros cuadrados)').firstMatch(t);
  if (area != null && length == null && width == null) {
    final s = math.sqrt(double.parse(area[1]!));
    final w = (s * 0.8).clamp(2.0, 30.0);
    width = double.parse(w.toStringAsFixed(1));
    length = double.parse((double.parse(area[1]!) / w).toStringAsFixed(1));
    notes.add('Solo se indica superficie: se supone planta de ${length}x$width m.');
  }

  // Cancelas, vallas y barandillas: "A x B" es hueco/longitud x altura
  const linear = [StructureType.cancela, StructureType.valla, StructureType.barandilla];
  if (linear.contains(type) && height == null && width != null && dm != null) {
    height = width;
    width = null;
  }
  // Medida suelta "de 3 m" sin palabra clave: según la tipología
  final bare = RegExp(r'(?:de|con|a)\s+(\d+(?:\.\d+)?)\s*(mm|cm|m)(?:etros?|ts?)?\b(?!\s*(?:de\s+)?(?:ancho|anchura|largo|alto|altura|fondo|luz|hueco))')
      .firstMatch(t);
  if (bare != null && dm == null) {
    final v = _toM(bare[1]!, bare[2]);
    switch (type) {
      case StructureType.escalera:
      case StructureType.torre:
        height ??= v;
        break;
      case StructureType.barandilla:
      case StructureType.valla:
      case StructureType.pasarela:
        length ??= v;
        break;
      case StructureType.cancela:
        length ??= v;
        break;
      case StructureType.cercha:
      case StructureType.portico:
        width ??= v;
        break;
      default:
        break;
    }
  }
  final hueco = _find(t, ['hueco\\s*(?:libre\\s*)?(?:de|:)?\\s*(?<n>\\d+(?:\\.\\d+)?)\\s*(?<u>mm|cm|m)?']);
  if (hueco != null && type == StructureType.cancela) length = hueco;

  final ridge = _find(t, ['cumbrera\\s*(?:de|:|=|a)?\\s*(?<n>\\d+(?:\\.\\d+)?)\\s*(?<u>mm|cm|m)?']);
  final heightGiven = height != null;

  double def(String what, double v) {
    notes.add('Sin $what indicado: se supone ${v.toString().replaceAll('.', ',')} m.');
    return v;
  }

  switch (type) {
    case StructureType.escalera:
      final form = stairForm(t);
      height ??= def('altura a salvar', 3.0);
      if (form == 'caracol') {
        // en la de caracol, «ancho» es el diámetro total
        final diam = _find(t, [
          'diametro\\s*(?:total\\s*)?(?:de|:|=)?\\s*(?<n>\\d+(?:\\.\\d+)?)\\s*(?<u>mm|cm|m)?',
          '(?<n>\\d+(?:\\.\\d+)?)\\s*(?<u>mm|cm|m)?(?:etros?|ts?)?\\s*de\\s+diametro',
        ]);
        width = diam ?? (width != null && width >= 1.2 && width <= 3 ? width : null);
        if (width == null || width < 1.2 || width > 3) width = def('diámetro', 1.8);
      } else if (form == 'escala de gato') {
        if (width == null || width < 0.35 || width > 0.8) width = def('ancho entre largueros', 0.45);
      } else if (width == null || width > 3) {
        width = def('ancho de paso', 1.0);
      }
      length = 0; // el desarrollo lo calcula el diseño
      break;
    case StructureType.pasarela:
      length ??= def('longitud', 6.0);
      width ??= def('ancho útil', 1.0);
      height ??= def('altura', 3.0);
      break;
    case StructureType.barandilla:
      final wall = railForm(t) == 'pasamanos a pared';
      length ??= def('longitud', wall ? 4.0 : 10.0);
      if (wall) {
        if (height == null || height > 1.2 || height < 0.7) {
          height = 0.9;
          notes.add('Pasamanos a 0,90 m sobre la línea de peldaños o el suelo (CTE DB-SUA 1: entre 0,90 y 1,10 m).');
        }
      } else if (height == null || height > 1.5) {
        final fall = height;
        final hr = (fall != null && fall > 6) || RegExp(r'publica|comercial|colegio|1\.1').hasMatch(t) ? 1.1 : 0.9;
        height = hr;
        notes.add('Altura de barandilla ${hr.toStringAsFixed(2).replaceAll('.', ',')} m (CTE DB-SUA 1: 0,90 m si la caída es ≤ 6 m; 1,10 m en el resto).');
      }
      width = 0;
      break;
    case StructureType.cercha:
      width ??= def('luz de cercha', 10.0);
      length ??= def('longitud de cubierta', 12.0);
      height ??= def('altura de apoyo', 3.0);
      break;
    case StructureType.torre:
      length ??= def('lado de la base', 2.0);
      width ??= length;
      height ??= def('altura', 3.0);
      break;
    case StructureType.estanteria:
      final pallets = RegExp(r'pale|palet|paleta|rack|carretilla').hasMatch(t);
      length ??= def('largo', pallets ? 5.6 : 3.0);
      width ??= def('fondo', pallets ? 1.1 : 0.6);
      height ??= def('altura', pallets ? 4.5 : 2.5);
      break;
    case StructureType.cancela:
      length ??= def('hueco libre', RegExp(r'peatonal').hasMatch(t) ? 1.0 : 3.0);
      height ??= def('altura', 2.0);
      width = 0;
      break;
    case StructureType.valla:
      if (isWindowGrille(t)) {
        if (length == null && width != null && width >= 0.3 && width <= 4) length = width;
        length ??= def('ancho del hueco', 1.2);
        height ??= def('alto del hueco', 1.2);
      } else {
        length ??= def('longitud', 20.0);
        height ??= def('altura', 2.0);
      }
      width = 0;
      break;
    case StructureType.portico:
      width ??= def('luz entre patas', 4.0);
      height ??= def('altura bajo viga', 3.0);
      length = 0;
      break;
    case StructureType.poste:
      final sign = RegExp(r'cartel|letrero|publicitari|rotulo|totem|pantalla').hasMatch(t);
      length ??= def(sign ? 'ancho del cartel' : 'ancho de la placa/bandera', sign ? 3.0 : 0.6);
      width ??= def(sign ? 'alto del cartel' : 'alto de la placa/bandera', sign ? 1.5 : 0.4);
      height ??= def('altura libre', sign ? 3.0 : 6.0);
      break;
    case StructureType.nave:
      if (width == null) {
        width = 12;
        notes.add('Sin luz indicada: se supone 12 m.');
      }
      if (length == null) {
        length = 20;
        notes.add('Sin longitud indicada: se supone 20 m.');
      }
      if (height == null) {
        height = 5;
        notes.add('Sin altura indicada: se supone 5 m al alero.');
      }
      break;
    case StructureType.marquesina:
      if (width == null) {
        width = 5;
        notes.add('Sin ancho indicado: se supone 5 m.');
      }
      if (length == null) {
        length = 6;
        notes.add('Sin largo indicado: se supone 6 m.');
      }
      if (height == null) {
        height = 2.5;
        notes.add('Sin altura indicada: se supone 2,5 m libres.');
      }
      break;
    case StructureType.entreplanta:
      if (width == null) {
        width = 4;
        notes.add('Sin ancho indicado: se supone 4 m.');
      }
      if (length == null) {
        length = 6;
        notes.add('Sin largo indicado: se supone 6 m.');
      }
      if (height == null) {
        height = 2.7;
        notes.add('Sin altura indicada: se supone 2,7 m al forjado.');
      }
      break;
  }

  // --- Pendiente ------------------------------------------------------------
  double slope = switch (type) {
    StructureType.nave => 10,
    StructureType.marquesina => 5,
    StructureType.cercha => 20,
    _ => 0,
  };
  final sp = RegExp(r'pendiente\s*(?:de|del)?\s*(\d+(?:\.\d+)?)\s*(%|por ?ciento|grados|º|°)?')
      .firstMatch(t);
  if (sp != null) {
    final v = double.parse(sp[1]!);
    if (sp[2] == 'grados' || sp[2] == 'º' || sp[2] == '°') {
      slope = math.tan(v * math.pi / 180) * 100;
    } else {
      slope = v;
    }
  }
  if (RegExp(r'cubierta plana|techo plano|plana').hasMatch(t) && type.hasRoof) {
    slope = type == StructureType.nave ? 3 : 2;
  }
  if (ridge != null && !heightGiven && type.hasRoof && slope > 0) {
    final rise = (type == StructureType.marquesina ? width : width / 2) * slope / 100;
    height = math.max(2.0, double.parse((ridge - rise).toStringAsFixed(2)));
    notes.removeWhere((n) => n.startsWith('Sin altura'));
    notes.add('Altura a cumbrera ${_fmt(ridge)} m con pendiente ${_fmt(slope)} %: altura al alero ${_fmt(height)} m.');
  }

  // --- Separación entre pórticos ------------------------------------------
  double? bay = _find(t, [
    '${_kw("porticos|pilares|apoyos|cerchas")}\\s*(?:separados\\s*|colocados\\s*)?(?:cada|a)\\s*(?<n>\\d+(?:\\.\\d+)?)\\s*(?<u>mm|cm|m)?',
    '${_kw("separacion|intereje|crujia|modulacion")}\\s*(?:entre\\s+\\w+\\s*)?(?:de|:|=)?\\s*(?<n>\\d+(?:\\.\\d+)?)\\s*(?<u>mm|cm|m)?',
    'cada\\s*(?<n>\\d+(?:\\.\\d+)?)\\s*(?<u>mm|cm|m)?',
  ]);
  final nPort = RegExp(r'(\d+)\s*(porticos|vanos|crujias|modulos)').firstMatch(t);
  if (bay == null && nPort != null) {
    final n = int.parse(nPort[1]!);
    if (nPort[2] == 'porticos' && n > 1) {
      bay = length / (n - 1);
    } else if (n > 0) {
      bay = length / n;
    }
  }

  // --- Materiales por partes ---------------------------------------------------
  final parts = partProfiles(t, notes);
  // Cerramiento lateral: se aparta del texto para no confundirlo con la cubierta
  var cladding = '';
  var tr = t; // texto para detectar la cubierta
  final cl = RegExp(r'(?:cerramientos?|fachadas?|paredes|laterales|cerrada con|cerrado con)(?:\s+laterales?)?\s+(?:de|con|en)?\s*'
          r'(panel sandwich(?:\s+de\s+\d+\s*mm)?|chapa grecada|chapa|bloque de hormigon|bloque|ladrillo|policarbonato|malla|lamas)')
      .firstMatch(t);
  if (cl != null) {
    cladding = cl[1]!.replaceAll('sandwich', 'sándwich').replaceAll('hormigon', 'hormigón');
    tr = t.replaceRange(cl.start, cl.end, ' ');
    notes.add('Cerramiento lateral: $cladding.');
  }
  // Cubierta indicada expresamente ("cubierta de …", "techo de …")
  final rc = RegExp(r'(?:cubierta|techo|tejado|cubricion)\s+(?:de|con|en)\s+([a-z ]{4,40}?)(?=[,.;]|$| y | sobre | a | en )').firstMatch(tr);
  if (rc != null) tr = '${rc[1]} $tr';

  // --- Cubierta -------------------------------------------------------------
  var roofing = 'chapa grecada';
  final rt = rc != null ? rc[1]! : tr;
  String? mm(String what) {
    final m = RegExp('$what\\D{0,14}?(\\d{1,3}(?:\\.\\d)?)\\s*mm|(\\d{1,3}(?:\\.\\d)?)\\s*mm\\D{0,10}$what').firstMatch(rt);
    return m == null ? null : (m[1] ?? m[2]);
  }
  if (RegExp(r'sandwich').hasMatch(rt)) {
    final e = mm('sandwich');
    final rock = RegExp(r'lana de roca|lana mineral').hasMatch(rt);
    roofing = 'panel sándwich${e != null ? ' $e mm' : ''}${rock ? ' lana de roca' : ''}';
  } else if (RegExp(r'policarbonato').hasMatch(rt)) {
    final e = mm('policarbonato');
    roofing = RegExp(r'compacto').hasMatch(rt)
        ? 'policarbonato compacto${e != null ? ' $e mm' : ''}'
        : 'policarbonato celular${e != null ? ' $e mm' : ''}';
  } else if (RegExp(r'(?<![a-z])tejas?(?![a-z])').hasMatch(rt)) {
    roofing = 'teja sobre panel';
  } else if (RegExp(r'fotovoltaic|placas solares|paneles solares').hasMatch(rt)) {
    roofing = 'paneles fotovoltaicos';
  } else if (RegExp(r'vidrio|cristal').hasMatch(rt) && type.hasRoof) {
    roofing = 'vidrio laminado de seguridad';
  } else if (RegExp(r'fibrocemento|uralita').hasMatch(rt)) {
    roofing = 'placa de fibrocemento sin amianto';
  } else if (RegExp(r'sin cubierta|abierta|lamas|celosia|vegetal|toldo').hasMatch(rt)) {
    roofing = 'sin cubierta (pérgola abierta)';
  } else if (type == StructureType.entreplanta) {
    final e = mm('lagrimada');
    roofing = RegExp(r'tramex|rejilla').hasMatch(rt)
        ? 'rejilla tramex'
        : (RegExp(r'colaborante|hormigon').hasMatch(rt)
            ? 'chapa colaborante + losa de hormigón'
            : (RegExp(r'tablero|madera|fenolico|osb').hasMatch(rt)
                ? 'tablero fenólico/madera'
                : 'chapa lagrimada${e != null ? ' $e mm' : ''}'));
  } else if (RegExp(r'chapa grecada|chapa').hasMatch(rt)) {
    final e = mm('chapa');
    roofing = 'chapa grecada${e != null ? ' $e mm' : ''}';
  }

  // --- Nieve ----------------------------------------------------------------
  double snow = 0.4;
  bool snowSet = false;
  for (final e in _snowCities.entries) {
    if (t.contains(e.key)) {
      snow = e.value;
      snowSet = true;
      notes.add('Nieve: sk = ${e.value} kN/m² (capital ${e.key}, CTE DB-SE-AE tabla 3.8).');
      break;
    }
  }
  final alt = RegExp(r'(?:altitud|cota)\s*(?:de)?\s*(\d{3,4})\s*m').firstMatch(t);
  if (alt != null) {
    final h = double.parse(alt[1]!);
    snow = math.max(snow, _snowFromAltitude(h));
    snowSet = true;
    notes.add('Nieve estimada por altitud ${h.toStringAsFixed(0)} m: ${snow.toStringAsFixed(2)} kN/m² (aprox., verificar CTE anejo E).');
  }
  final sn = RegExp(r'nieve\s*(?:de)?\s*(\d+(?:\.\d+)?)\s*(kn|kg)').firstMatch(t);
  if (sn != null) {
    final v = double.parse(sn[1]!);
    snow = sn[2] == 'kg' ? v / 100 : v;
    snowSet = true;
  } else if (!snowSet && RegExp(r'montana|pirineo|sierra|nieva mucho|zona de nieve').hasMatch(t)) {
    snow = 1.5;
    notes.add('Zona de montaña: se toma nieve 1,5 kN/m² (verificar con la altitud real).');
  }
  if (!type.hasRoof) snow = 0;

  // --- Viento ---------------------------------------------------------------
  double wind = 0.45;
  final wz = RegExp(r'zona (?:eolica )?([abc])\b').firstMatch(t);
  if (wz != null) {
    wind = {'a': 0.42, 'b': 0.45, 'c': 0.52}[wz[1]]!;
  } else if (_windZoneC.any(t.contains)) {
    wind = 0.52;
  }
  final indoorType = type == StructureType.entreplanta ||
      type == StructureType.estanteria ||
      (type == StructureType.portico && !t.contains('exterior'));
  if (RegExp(r'interior|dentro de (?:una )?nave|bajo cubierta').hasMatch(t) || indoorType) {
    wind = 0;
  }

  // --- Sobrecarga de uso ---------------------------------------------------
  double live = 0;
  String use = '';
  if (type == StructureType.entreplanta) {
    if (RegExp(r'almacen|stock|estanteria|palet|archivo').hasMatch(t)) {
      live = 5;
      use = 'almacenamiento';
    } else if (RegExp(r'tienda|comercial|publico').hasMatch(t)) {
      live = 5;
      use = 'zona comercial (D)';
    } else if (RegExp(r'trastero').hasMatch(t)) {
      live = 3;
      use = 'trastero (A2)';
    } else if (RegExp(r'oficina|despacho').hasMatch(t)) {
      live = 2;
      use = 'administrativo (B)';
    } else if (RegExp(r'vivienda|dormitorio|habitacion|casa|loft').hasMatch(t)) {
      live = 2;
      use = 'vivienda (A1)';
    } else if (RegExp(r'maquina|instalacion|equipos').hasMatch(t)) {
      live = 5;
      use = 'instalaciones / maquinaria ligera';
    } else {
      live = 3;
      use = 'uso general (supuesto)';
      notes.add('Uso de la entreplanta no indicado: se toman 3 kN/m².');
    }
  } else if (type == StructureType.escalera) {
    final pub = RegExp(r'publica|comercial|industrial|incendio|emergencia|evacuacion|colegio').hasMatch(t);
    live = pub ? 4 : 3;
    use = pub ? 'escalera de uso público / evacuación' : 'escalera de uso privado';
  } else if (type == StructureType.pasarela) {
    if (RegExp(r'peatonal|publica|puente').hasMatch(t)) {
      live = 5;
      use = 'pasarela peatonal pública (aglomeración)';
    } else if (RegExp(r'mantenimiento|inspeccion|acceso a maquina').hasMatch(t)) {
      live = 2;
      use = 'pasarela de mantenimiento (EN ISO 14122-2)';
    } else {
      live = 3;
      use = 'pasarela de acceso (uso general)';
    }
  } else if (type == StructureType.barandilla) {
    if (RegExp(r'estadio|grada|aglomeracion|concierto').hasMatch(t)) {
      live = 3.0;
      use = 'zona de aglomeración (C5)';
    } else if (RegExp(r'publica|comercial|colegio|oficina|industrial|hotel').hasMatch(t)) {
      live = 1.6;
      use = 'zona pública / comercial';
    } else {
      live = 0.8;
      use = 'uso residencial / privado';
    }
  } else if (type == StructureType.torre && RegExp(r'plataforma|mirador|atalaya').hasMatch(t)) {
    live = 3;
    use = 'plataforma accesible';
  } else if (!type.hasRoof) {
    live = 0;
    use = '';
  } else {
    live = 0.4; // G1: cubiertas accesibles solo para conservación
    use = 'cubierta accesible solo para conservación (G1)';
  }
  final q = RegExp(r'(?:carga|sobrecarga|uso de|soportar|aguante)\D{0,20}(\d+(?:\.\d+)?)\s*(kg|kn)\s*/?\s*m(?:2|²)')
      .firstMatch(t);
  if (q != null) {
    final v = double.parse(q[1]!);
    live = q[2] == 'kg' ? v / 100 : v;
    use = '${use.isEmpty ? '' : '$use, '}carga indicada ${live.toStringAsFixed(2)} kN/m²';
  }

  // --- Acero, acabado, barandilla -----------------------------------------
  final given = gradeFromText(t);
  SteelGrade grade = given ?? s275;
  if (given != null) notes.add('Material: ${given.name} – ${given.description}');
  String finish = 'pintado (imprimación + esmalte)';
  final color = RegExp(r'(negro|blanco|gris antracita|antracita|gris|verde|rojo|marron|azul|oxiron|ral ?\d{4})')
      .firstMatch(t)?[1];
  if (grade.kind == MaterialKind.aluminium) {
    finish = t.contains('lacad') || color != null ? 'aluminio lacado en ${color ?? 'blanco'}' : 'aluminio anodizado';
  } else if (grade.kind == MaterialKind.stainless) {
    finish = RegExp(r'pulid|brillo|espejo').hasMatch(t) ? 'inox pulido brillante' : 'inox satinado (grano 240)';
  } else if (t.contains('galvaniz')) {
    finish = 'galvanizado en caliente';
    if (t.contains('lacad') || t.contains('pintad')) finish = 'galvanizado + lacado${color != null ? ' en $color' : ''}';
  } else if (t.contains('corten') || grade.kind == MaterialKind.weathering) {
    finish = 'acero corten (pátina natural)';
  } else if (t.contains('lacad') || color != null) {
    finish = 'lacado en ${color ?? 'negro'}';
  }
  final noRail = RegExp(r'sin barandilla').hasMatch(t);
  final railing = switch (type) {
    StructureType.entreplanta || StructureType.escalera || StructureType.pasarela || StructureType.barandilla =>
      !noRail || type == StructureType.barandilla,
    StructureType.torre => !noRail && RegExp(r'plataforma|mirador|atalaya|barandilla').hasMatch(t),
    _ => RegExp(r'barandilla').hasMatch(t),
  };

  // --- Cargas concentradas, niveles y subtipo ------------------------------
  double pointLoad = 0;
  final liters = RegExp(r'(\d+(?:\.\d+)?)\s*(litros|l\b|m3|m³|metros cubicos)').firstMatch(t);
  final mass = RegExp(r'(\d+(?:\.\d+)?)\s*(kg|kilos|t\b|tn\b|toneladas)(?!\s*/\s*m)').firstMatch(t);
  final pal = RegExp(r'(\d+)\s*(?:pales|palets|paletas|pale|palet)\s*(?:de\s*)?(\d+(?:\.\d+)?)\s*(kg|t)').firstMatch(t);
  if (pal != null) {
    final kg = double.parse(pal[2]!) * (pal[3] == 't' ? 1000 : 1);
    pointLoad = int.parse(pal[1]!) * kg / 100;
  } else if (liters != null) {
    final v = double.parse(liters[1]!);
    final l = liters[2]!.startsWith('m') ? v * 1000 : v;
    pointLoad = l / 100 * 1.1; // agua + 10 % del propio depósito
    notes.add('Depósito de ${l.toStringAsFixed(0)} l: carga ${(pointLoad).toStringAsFixed(1).replaceAll('.', ',')} kN (agua + 10 % del depósito).');
  } else if (mass != null) {
    final v = double.parse(mass[1]!);
    pointLoad = mass[2]!.startsWith('t') ? v * 10 : v / 100;
  }
  final lv = RegExp(r'(\d+)\s*(niveles|alturas|baldas|estantes|pisos|plantas|tramos)').firstMatch(t);
  int levels = lv != null ? int.parse(lv[1]!) : 0;
  String variant = '';
  String infill() => RegExp(r'chapa|ciega|opaca|panel').hasMatch(t)
      ? 'chapa'
      : (RegExp(r'malla|rejilla|electrosoldada|simple torsion').hasMatch(t) ? 'malla' : 'barrotes');
  switch (type) {
    case StructureType.cancela:
      final sliding = RegExp(r'corred|deslizante|autoportante').hasMatch(t);
      final two = RegExp(r'dos hojas|2 hojas|doble hoja').hasMatch(t) ||
          (!sliding && !RegExp(r'una hoja|1 hoja').hasMatch(t) && length > 2.5);
      variant = '${sliding ? (t.contains('autoportante') ? 'corredera autoportante' : 'corredera') : 'abatible'}'
          '${sliding ? '' : (two ? ' 2 hojas' : ' 1 hoja')} · ${infill()}';
      break;
    case StructureType.valla:
      variant = isWindowGrille(t) ? 'reja · ${infill() == 'chapa' ? 'barrotes' : infill()}' : infill();
      break;
    case StructureType.barandilla:
      final form = railForm(t);
      final toe = form != 'pasamanos a pared' &&
          (t.contains('rodapie') || RegExp(r'industrial|nave|fabrica|mantenimiento|pasarela|plataforma').hasMatch(t));
      variant = '$form${toe ? ' · rodapié' : ''}';
      break;
    case StructureType.cercha:
      variant = '${RegExp(r'pilares|columnas|soportes metalicos').hasMatch(t) ? 'sobre pilares' : 'sobre muros'}'
          '${RegExp(r'plana|cordones paralelos|viga celosia|viga en celosia').hasMatch(t) || slope < 8 ? ' · cordones paralelos' : ' · a dos aguas'}';
      break;
    case StructureType.poste:
      variant = RegExp(r'cartel|letrero|publicitari|rotulo|totem|pantalla').hasMatch(t)
          ? 'cartel'
          : (RegExp(r'farola|baculo').hasMatch(t) ? 'farola' : 'mástil');
      break;
    case StructureType.torre:
      variant = RegExp(r'deposito|aljibe|tanque|litros|silo').hasMatch(t)
          ? 'depósito'
          : (RegExp(r'bancada|maquina|mesa|banco').hasMatch(t) ? 'bancada' : 'plataforma');
      if (pointLoad == 0) {
        pointLoad = variant == 'plataforma' ? 0 : 20;
        if (variant != 'plataforma') notes.add('Carga no indicada: se suponen 2000 kg (20 kN).');
      }
      break;
    case StructureType.estanteria:
      final pallets = RegExp(r'pale|palet|paleta|rack|carretilla').hasMatch(t);
      variant = pallets ? 'palés' : 'baldas';
      if (levels == 0) levels = math.max(2, (height / (pallets ? 1.5 : 0.5)).floor());
      if (pointLoad == 0) {
        pointLoad = pallets ? 16 : 1.5;
        notes.add(pallets
            ? 'Carga no indicada: 2 palés de 800 kg por nivel y vano.'
            : 'Carga no indicada: 150 kg por balda.');
      }
      break;
    case StructureType.portico:
      if (pointLoad == 0) {
        pointLoad = 10;
        notes.add('Carga no indicada: polipasto de 1000 kg.');
      }
      break;
    case StructureType.pasarela:
      variant = live <= 2 ? 'mantenimiento' : (live >= 5 ? 'peatonal pública' : 'acceso');
      break;
    case StructureType.escalera:
      variant = '${stairForm(t)}${RegExp(r'exterior|intemperie|fachada').hasMatch(t) ? ' · exterior' : ''}';
      break;
    default:
      break;
  }
  if (type == StructureType.escalera || type == StructureType.pasarela) {
    roofing = RegExp(r'lagrimada|chapa').hasMatch(t) ? 'chapa lagrimada' : 'rejilla tramex';
  } else if (type == StructureType.torre) {
    roofing = variant == 'plataforma' || RegExp(r'tramex|rejilla').hasMatch(t) ? 'rejilla tramex' : '';
  } else if (!type.hasRoof && type != StructureType.entreplanta) {
    roofing = '';
  }

  // --- Validaciones de rango ----------------------------------------------
  if (type == StructureType.cercha && width > 30) {
    notes.add('Luz > 30 m: cercha fuera del rango habitual de taller; requiere cálculo específico y montaje por tramos.');
  }
  if (type == StructureType.nave && width > 30) {
    notes.add('Luz > 30 m: fuera del rango del predimensionado con pórticos de alma llena; considere celosía.');
  }
  if (height > 15) notes.add('Altura > 15 m: el predimensionado pierde fiabilidad.');

  return StructureSpec(
    type: type,
    length: length,
    width: width,
    height: height,
    slopePct: slope,
    bay: bay,
    roofing: roofing,
    cladding: cladding,
    parts: parts,
    snow: snow,
    wind: wind,
    liveLoad: live,
    use: use,
    grade: grade,
    railing: railing,
    finish: finish,
    pointLoad: pointLoad,
    levels: levels,
    variant: variant,
    notes: notes,
  );
}

/// Aproximación de sk por altitud (interpolación conservadora a partir de las
/// tablas del anejo E del CTE DB-SE-AE para zonas de interior).
double _snowFromAltitude(double h) {
  const pts = [
    [0.0, 0.4],
    [200.0, 0.5],
    [400.0, 0.6],
    [600.0, 0.9],
    [800.0, 1.2],
    [1000.0, 1.6],
    [1200.0, 2.1],
    [1400.0, 2.7],
    [1600.0, 3.4],
    [1800.0, 4.2],
  ];
  if (h <= 0) return 0.4;
  for (var i = 1; i < pts.length; i++) {
    if (h <= pts[i][0]) {
      final f = (h - pts[i - 1][0]) / (pts[i][0] - pts[i - 1][0]);
      return pts[i - 1][1] + f * (pts[i][1] - pts[i - 1][1]);
    }
  }
  return 4.2;
}

// ---------------------------------------------------------------------------
// Perfiles / materiales por partes de la estructura
// ---------------------------------------------------------------------------

const Map<String, String> _partWords = {
  'pilares': r'pilar(?:es)?|columnas?|soportes?|postes?|pies derechos|patas',
  'vigas': r'vigas?(?! de atado)(?! carril)|dinteles?|jacenas?|largueros?',
  'correas': r'correas?',
  'arriostramiento': r'tirantes?|cruces(?: de san andres)?|cruz de san andres|arriostramientos?|contravientos?|diagonales|riostras?',
  'viguetas': r'viguetas?',
  'zancas': r'zancas?',
  'barandilla': r'barandillas?|pasamanos',
  'cordones': r'cordon(?:es)?(?: superior(?:es)?| inferior(?:es)?)?',
};

/// Interpreta la designación de un perfil o familia en un fragmento de texto.
/// Devuelve un perfil exacto ("HEB 220"), un prefijo ("SHS 80x*": espesor a
/// elegir) o una familia (heb, ipe, upn, shs, rhs, tubo, angle, round).
String? _profileIn(String w, List<String> notes) {
  final open = RegExp(r'(?<![a-z])(ipe|ipn|heb|hea|hem|upn|upe)\s*(\d{2,3})(?!\d)').firstMatch(w);
  if (open != null) {
    var fam = open[1]!;
    final n = open[2]!;
    if (fam == 'hea' || fam == 'hem') {
      notes.add('${fam.toUpperCase()} $n no está en el catálogo de la app: se usa HEB $n (mismo canto, del lado de la seguridad).');
      fam = 'heb';
    } else if (fam == 'ipn') {
      fam = 'ipe';
    } else if (fam == 'upe') {
      fam = 'upn';
    }
    final name = '${fam.toUpperCase()} $n';
    if (profileByName(name) != null) return name;
    notes.add('$name no está en el catálogo: la app elige el ${fam.toUpperCase()} adecuado.');
    return fam;
  }
  final lm = RegExp(r'(?<![a-z])(?:l|angular(?:es)?|angulos?)\s*(\d{2,3})\s*x\s*(?:\d{2,3}\s*x\s*)?(\d{1,2})(?![\d.])').firstMatch(w);
  if (lm != null) {
    final name = 'L ${lm[1]}x${lm[2]}';
    return profileByName(name) != null ? name : 'angle';
  }
  final tb = RegExp(r'(?:(shs|rhs|tubos?(?: estructural(?:es)?)?(?: cuadrados?| rectangular(?:es)?)?|tubular(?:es)?|cuadradillos?)\s*(?:de\s*)?)?'
          r'(?<![\d.])(\d{2,3})\s*x\s*(\d{1,3}(?:\.\d)?)(?:\s*x\s*(\d{1,2}(?:\.\d)?))?(?![\d.])(?!\s*(?:m|cm)\b)')
      .firstMatch(w);
  if (tb != null) {
    final a = double.parse(tb[2]!), b = double.parse(tb[3]!);
    final t = tb[4] == null ? null : double.parse(tb[4]!);
    String n(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 1);
    if (tb[1] != null || (a >= 20 && (b >= 20 || t == null && b <= 12))) {
      if (t == null && b <= 12 && tb[1] != null) {
        // "SHS 100x5" (lado x espesor)
        final name = 'SHS ${n(a)}x${n(b)}';
        return profileByName(name) != null ? name : 'SHS ${n(a)}x*';
      }
      if (b >= 20) {
        final square = a == b;
        if (t != null) {
          final name = square ? 'SHS ${n(a)}x${n(t)}' : 'RHS ${n(math.max(a, b))}x${n(math.min(a, b))}x${n(t)}';
          if (profileByName(name) != null) return name;
        }
        final pre = square ? 'SHS ${n(a)}x' : 'RHS ${n(math.max(a, b))}x${n(math.min(a, b))}x';
        if (allProfiles.any((p) => p.name.startsWith(pre))) return '$pre*';
        notes.add('Tubo ${n(a)}x${n(b)} no está en el catálogo: la app elige el tubo adecuado.');
        return square ? 'shs' : 'rhs';
      }
    }
  }
  final rd = RegExp(r'(?<![a-z])(?:(?:redondos?|varillas?|barras?|cables?)\s*(?:macizos?\s*)?(?:de\s*)?(?:ø\s*|diametro\s*|d\s*)?|r\s*)(\d{1,2})(?:\s*mm)?(?![\d.x])')
      .firstMatch(w);
  if (rd != null) {
    final name = 'R${rd[1]}';
    return profileByName(name) != null ? name : 'round';
  }
  if (RegExp(r'(?<![a-z])(redondos?|varillas?|barras? macizas?|cables?)(?![a-z])').hasMatch(w)) return 'round';
  if (RegExp(r'(?<![a-z])(angular(?:es)?|angulos?|perfil(?:es)? (?:en )?l)(?![a-z])').hasMatch(w)) return 'angle';
  final chs = RegExp(r'(?:chs|tubos? (?:redondos?|circular(?:es)?))\s*(?:de\s*)?(?:ø\s*|diametro\s*)?(\d{2,3}(?:\.\d)?)(?:\s*x\s*(\d+(?:\.\d)?))?')
      .firstMatch(w);
  if (chs != null) {
    final d = double.parse(chs[1]!);
    final t = chs[2] == null ? null : double.parse(chs[2]!);
    final c = chsTable.where((p) => (p.h - d).abs() < 1.5 && (t == null || (p.tw - t).abs() < 0.2)).toList();
    if (c.isNotEmpty) return t == null ? '${c.first.name.split('x').first}x*' : c.first.name;
    return 'chs';
  }
  if (RegExp(r'(?<![a-z])(chs|tubos? (?:redondos?|circular(?:es)?))(?![a-z])').hasMatch(w)) return 'chs';
  if (RegExp(r'(?<![a-z])(pletinas?|llantas?|platabandas?)(?![a-z])').hasMatch(w)) return 'flat';
  if (RegExp(r'(?<![a-z])(rhs|tubos? rectangular(?:es)?)(?![a-z])').hasMatch(w)) return 'rhs';
  if (RegExp(r'(?<![a-z])(shs|tubos? cuadrados?|cuadradillos?)(?![a-z])').hasMatch(w)) return 'shs';
  if (RegExp(r'(?<![a-z])(tubos?|tubular(?:es)?)(?![a-z])').hasMatch(w)) return 'tubo';
  final fam = RegExp(r'(?<![a-z])(ipe|ipn|heb|hea|hem|upn|upe)(?![a-z])').firstMatch(w);
  if (fam != null) {
    return switch (fam[1]) { 'hea' || 'hem' => 'heb', 'ipn' => 'ipe', 'upe' => 'upn', final f => f! };
  }
  if (RegExp(r'perfil(?:es)? (?:en )?u(?![a-z])').hasMatch(w)) return 'upn';
  if (RegExp(r'perfil(?:es)? (?:en )?(?:doble t|i)(?![a-z])').hasMatch(w)) return 'ipe';
  if (RegExp(r'perfil(?:es)? (?:en )?h(?![a-z])').hasMatch(w)) return 'heb';
  return null;
}

/// Perfiles o familias que el usuario impone a cada parte de la estructura
/// ("pilares HEB 220, correas de tubo, tirantes de redondo"). Lo no indicado
/// lo elige la app.
Map<String, String> partProfiles(String t, [List<String>? notes]) {
  final out = <String, String>{};
  final ns = notes ?? <String>[];
  final all = RegExp('(?<![a-z])(?:${_partWords.values.join('|')})(?![a-z])');
  for (final e in _partWords.entries) {
    for (final m in RegExp('(?<![a-z])(?:${e.value})(?![a-z])').allMatches(t)) {
      // ventana: hasta la siguiente coma/punto o la siguiente parte
      var end = t.length;
      final stop = RegExp(r'[,;.](?!\d)|\s+(?:y|e)\s+').firstMatch(t.substring(m.end));
      if (stop != null) end = m.end + stop.start;
      final next = all.firstMatch(t.substring(m.end));
      if (next != null && m.end + next.start < end) end = m.end + next.start;
      if (end - m.end > 48) end = m.end + 48;
      final w = t.substring(m.end, end);
      // evita "pilares de 3 m", "barandilla de 1 m de alto"
      final p = _profileIn(w, ns);
      if (p != null) {
        out.putIfAbsent(e.key, () => p);
        break;
      }
    }
  }
  // Forma inversa: "HEB 200 en (los) pilares", "tubo 80x80 para las vigas"
  final inv = RegExp('([a-z0-9 .x]{2,32}?)\\s+(?:en|para)\\s+(?:los\\s+|las\\s+|el\\s+|la\\s+)?(${_partWords.values.join('|')})(?![a-z])');
  for (final m in inv.allMatches(t)) {
    final p = _profileIn(m[1]!, ns);
    if (p == null) continue;
    for (final e in _partWords.entries) {
      if (RegExp('^(?:${e.value})\$').hasMatch(m[2]!)) out.putIfAbsent(e.key, () => p);
    }
  }
  // "estructura de tubo", "todo en tubo": se aplica a pilares y vigas no indicados
  final g = RegExp(r'(?:estructura|todo|toda)\s+(?:de|en|con)\s+(?:perfiles?\s+)?([a-z0-9 .x]{3,30})').firstMatch(t);
  if (g != null) {
    final p = _profileIn(g[1]!, ns);
    if (p != null && !RegExp(r'\d').hasMatch(p)) {
      out.putIfAbsent('pilares', () => p);
      out.putIfAbsent('vigas', () => p);
    }
  }
  return out;
}
