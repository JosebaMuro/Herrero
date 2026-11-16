import 'dart:math' as math;

import 'model.dart';
import 'profiles.dart';

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
      .replaceAllMapped(RegExp(r'(\d),(\d)'), (m) => '${m[1]}.${m[2]}');
}


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

/// Interpreta el prompt en lenguaje natural y devuelve la especificación.
StructureSpec parsePrompt(String prompt) {
  final t = normalize(prompt);
  final notes = <String>[];

  // --- Tipo de estructura --------------------------------------------------
  StructureType type;
  if (RegExp(r'altillo|entreplanta|entre planta|forjado|plataforma|mezzanine|altell|tarima elevada|piso intermedio')
      .hasMatch(t)) {
    type = StructureType.entreplanta;
  } else if (RegExp(r'marquesina|pergola|porche|cobertizo|carport|cochera|parking|aparcamiento|tejavana|voladizo|sombraje|toldo')
      .hasMatch(t)) {
    type = StructureType.marquesina;
  } else if (RegExp(r'nave|portico|almacen|hangar|taller|granja|establo|pabellon|cubierta a dos aguas')
      .hasMatch(t)) {
    type = StructureType.nave;
  } else {
    type = StructureType.nave;
    notes.add('No se reconoce el tipo de estructura: se asume nave de pórticos.');
  }

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

  switch (type) {
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
  double slope = type == StructureType.nave
      ? 10
      : (type == StructureType.marquesina ? 5 : 0);
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
  if (RegExp(r'cubierta plana|techo plano|plana').hasMatch(t) &&
      type != StructureType.entreplanta) {
    slope = type == StructureType.nave ? 3 : 2;
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
  String roofing = 'chapa grecada';
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
  if (type == StructureType.entreplanta) snow = 0;

  // --- Viento ---------------------------------------------------------------
  double wind = 0.45;
  final wz = RegExp(r'zona (?:eolica )?([abc])\b').firstMatch(t);
  if (wz != null) {
    wind = {'a': 0.42, 'b': 0.45, 'c': 0.52}[wz[1]]!;
  } else if (_windZoneC.any(t.contains)) {
    wind = 0.52;
  }
  if (RegExp(r'interior|dentro de (?:una )?nave|bajo cubierta').hasMatch(t) ||
      type == StructureType.entreplanta) {
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
  if (t.contains('galvaniz')) finish = 'galvanizado en caliente';
  if (t.contains('oxid') || t.contains('corten')) finish = 'acero corten';
  if (t.contains('lacad') || t.contains('negro')) finish = 'lacado en negro';
  final railing = type == StructureType.entreplanta
      ? !RegExp(r'sin barandilla').hasMatch(t)
      : RegExp(r'barandilla').hasMatch(t);

  // --- Validaciones de rango ----------------------------------------------
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
