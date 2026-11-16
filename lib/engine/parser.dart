import 'dart:math' as math;

import 'catalog.dart';
import 'model.dart';
import 'profiles.dart';
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

/// Elige la tipología: gana la palabra clave de más peso y, a igualdad, la que
/// aparece antes (el sustantivo principal suele ir primero).
StructureType detectType(String t, List<String> notes) {
  StructureType? best;
  var bestScore = -1.0;
  for (final ty in typologies) {
    for (final e in ty.keywords.entries) {
      final m = RegExp('(?<![a-z])${RegExp.escape(e.key)}(?![a-z])').firstMatch(t);
      if (m == null) continue;
      final score = e.value * 1000.0 + e.key.length * 10 - m.start * 0.5;
      if (score > bestScore) {
        bestScore = score;
        best = ty.type;
      }
    }
  }
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

/// Interpreta el prompt en lenguaje natural y devuelve la especificación.
StructureSpec parsePrompt(String prompt) {
  final t = canonicalize(normalize(prompt));
  final notes = <String>[];

  // --- Tipo de estructura (catálogo de tipologías con sinónimos) ---------
  final type = detectType(t, notes);

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
    '(?<n>\\d+(?:\\.\\d+)?)\\s*(?<u>mm|cm|m)?(?:etros?|ts?)?\\s*(?:de\\s+)?${_kw("alto|altura")}',
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
    } else if (width == null) {
      width = (length - a).abs() < 1e-6 ? b : a;
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
      height ??= def('altura a salvar', 3.0);
      if (width == null || width > 3) width = def('ancho de paso', 1.0);
      length = 0; // el desarrollo lo calcula el diseño
      break;
    case StructureType.pasarela:
      length ??= def('longitud', 6.0);
      width ??= def('ancho útil', 1.0);
      height ??= def('altura', 3.0);
      break;
    case StructureType.barandilla:
      length ??= def('longitud', 10.0);
      if (height == null || height > 1.5) {
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
      length ??= def('longitud', 20.0);
      height ??= def('altura', 2.0);
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

  // --- Cubierta -------------------------------------------------------------
  var roofing = 'chapa grecada';
  if (RegExp(r'sandwich').hasMatch(t)) {
    roofing = 'panel sándwich';
  } else if (RegExp(r'policarbonato').hasMatch(t)) {
    roofing = 'policarbonato celular';
  } else if (RegExp(r'teja').hasMatch(t)) {
    roofing = 'teja sobre panel';
  } else if (RegExp(r'fotovoltaic|placas solares|paneles solares').hasMatch(t)) {
    roofing = 'paneles fotovoltaicos';
  } else if (RegExp(r'sin cubierta|abierta|lamas|celosia|vegetal|toldo').hasMatch(t)) {
    roofing = 'sin cubierta (pérgola abierta)';
  } else if (type == StructureType.entreplanta) {
    roofing = RegExp(r'tramex|rejilla').hasMatch(t)
        ? 'rejilla tramex'
        : (RegExp(r'colaborante|hormigon').hasMatch(t)
            ? 'chapa colaborante + losa de hormigón'
            : 'tablero/chapa lagrimada');
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
  SteelGrade grade = s275;
  if (t.contains('s355')) grade = s355;
  if (t.contains('s235')) grade = s235;
  String finish = 'pintado (imprimación + esmalte)';
  final color = RegExp(r'(negro|blanco|gris antracita|antracita|gris|verde|rojo|marron|azul|oxiron|ral ?\d{4})')
      .firstMatch(t)?[1];
  if (t.contains('galvaniz')) {
    finish = 'galvanizado en caliente';
    if (t.contains('lacad') || t.contains('pintad')) finish = 'galvanizado + lacado${color != null ? ' en $color' : ''}';
  } else if (t.contains('corten')) {
    finish = 'acero corten';
  } else if (t.contains('inox')) {
    finish = 'acero inoxidable';
    notes.add('Acero inoxidable: el predimensionado se hace con acero al carbono S275; el inoxidable (EN 1993-1-4) '
        'tiene otro módulo y resistencia, revisar con el fabricante.');
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
      variant = infill();
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
      variant = RegExp(r'exterior|intemperie|fachada').hasMatch(t) ? 'exterior' : 'interior';
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
