/// Diccionario de castellano para leer peticiones escritas deprisa, desde el
/// móvil o al dictado: faltas de tecleo, b/v, h muda, ll/y, c/z/s, k/qu,
/// diminutivos («escalerita»), plurales y palabras del oficio.
///
/// Solo corrige hacia palabras del oficio y nunca toca las palabras corrientes
/// del castellano (lista [_common]), para no inventar lo que no se ha dicho.
/// Trabaja sobre texto ya normalizado (minúsculas y sin tildes).
library;

import 'catalog.dart';
import 'spanish_common.dart';
import 'vocabulary.dart';

/// Palabras del oficio que el intérprete entiende (además de las del catálogo
/// de tipologías y del glosario). Sin tildes.
const List<String> tradeWords = [
  // escaleras
  'escalera', 'escalinata', 'escalon', 'peldano', 'huella', 'contrahuella', 'tabica', 'zanca', 'meseta',
  'rellano', 'descansillo', 'desembarco', 'arranque', 'mamperlan', 'caracol', 'helicoidal', 'espiral',
  'marinera', 'gato', 'escala', 'pates', 'aros', 'jaula', 'quitamiedos', 'voladizo', 'volada', 'central',
  'vertical', 'tramo', 'tramos', 'compensada', 'compensados', 'abanico', 'mastil', 'nucleo',
  // barandillas y pasamanos
  'barandilla', 'baranda', 'barandal', 'pasamanos', 'balaustre', 'balaustrada', 'barrote', 'montante',
  'pilastra', 'rodapie', 'zocalo', 'antepecho', 'pretil', 'guardacuerpos', 'asidero', 'agarradero',
  'soporte', 'soportes', 'vidrio', 'cristal', 'cable', 'cables', 'tensor', 'tensores', 'lamas', 'lama',
  'perforada', 'perforado', 'pletina', 'pletinas', 'cuadradillo', 'redondo', 'tubo', 'tubos',
  // cerrajería
  'reja', 'rejas', 'enrejado', 'verja', 'cancela', 'puerta', 'porton', 'portalon', 'portillo', 'portal',
  'corredera', 'abatible', 'batiente', 'hoja', 'hojas', 'bisagra', 'pernio', 'cerradura', 'cerrojo',
  'pasador', 'guia', 'ruedas', 'automatica', 'motor', 'ventana', 'ventanas', 'balcon', 'cierre',
  'valla', 'vallado', 'cerramiento', 'cercado', 'malla', 'electrosoldada', 'torsion', 'poste', 'postes',
  'celosia', 'chapa', 'ciega', 'opaca',
  // cubiertas y otras tipologías
  'pergola', 'porche', 'marquesina', 'cochera', 'tejavana', 'cobertizo', 'cenador', 'glorieta',
  'toldo', 'visera', 'tejadillo', 'techado', 'cubierta', 'tejado', 'policarbonato', 'sandwich', 'grecada',
  'altillo', 'entreplanta', 'forjado', 'plataforma', 'pasarela', 'nave', 'almacen', 'estanteria',
  'torre', 'deposito', 'cercha', 'cerchas', 'portico', 'polipasto', 'cartel', 'tramex', 'rejilla',
  'lagrimada', 'estriada',
  // estructura, perfiles y uniones
  'estructura', 'estructural', 'metalica', 'metalico', 'hierro', 'acero', 'aluminio', 'inoxidable', 'inox',
  'corten', 'galvanizado', 'galvanizada', 'lacado', 'lacada', 'pintado', 'pintada', 'imprimacion',
  'pilar', 'pilares', 'columna', 'viga', 'vigas', 'vigueta', 'correa', 'correas', 'dintel', 'jabalcon',
  'tirante', 'angular', 'perfil', 'perfiles', 'soldadura', 'soldado', 'soldada', 'tornillo', 'tornillos',
  'anclaje', 'anclajes', 'placa', 'placas', 'zapata', 'zapatas', 'taco', 'tacos', 'quimico', 'bastidor',
  'marco', 'cerco', 'arriostramiento', 'cruces',
  // medidas
  'altura', 'ancho', 'anchura', 'largo', 'longitud', 'fondo', 'profundidad', 'hueco', 'diametro',
  'metros', 'metro', 'centimetros', 'milimetros', 'grados', 'pendiente', 'desnivel', 'separacion',
  'interior', 'exterior', 'galvanizar',
  // soldadura, ensayos y calidad
  'electrodo', 'electrodos', 'argon', 'tungsteno', 'semiautomatica', 'cordon', 'cordones', 'garganta', 'bisel',
  'chaflan', 'biselado', 'precalentamiento', 'punteado', 'penetracion', 'continuo', 'continuos', 'discontinuo',
  'discontinuos', 'radiografia', 'radiografiado', 'radiografiada', 'ultrasonidos', 'penetrantes', 'magnetoscopia',
  'homologado', 'homologados', 'homologacion', 'soldador', 'soldadores', 'soldaduras', 'soldados', 'soldadas',
  'estanco', 'estanca', 'corrosividad', 'salitre', 'costera', 'costero', 'ejecucion',
  // herrería y calderería
  'forja', 'forjado', 'fragua', 'voluta', 'volutas', 'retorcido', 'lanza', 'lanzas', 'calderin', 'calderero',
  'caldereria', 'virola', 'virolas', 'tolva', 'tolvas', 'brida', 'bridas', 'tubuladura', 'tubuladuras', 'klopper',
  'korbbogen', 'toriesferico', 'rolado', 'plegado', 'plegada', 'curvado', 'curvada', 'chimenea', 'tanque', 'silo',
  'presion',
];

/// Palabras corrientes del castellano que se parecen a palabras del oficio y
/// no se deben corregir.
const List<String> _common = [
  'vaya', 'vayas', 'valle', 'valles', 'baya', 'cancelar', 'cancelado', 'puerto', 'puertos', 'poster',
  'postre', 'pilas', 'pila', 'hecho', 'hechos', 'echo', 'dicho', 'mucho', 'mucha', 'muchos', 'parra',
  'llamas', 'llama', 'llamo', 'rojas', 'rojos', 'roja', 'rojo', 'negro', 'negra', 'blanco', 'blanca',
  'verde', 'verdes', 'gris', 'azul', 'marron', 'huevo', 'barco', 'barcos', 'cargo', 'carga', 'cargas',
  'vigor', 'tubas', 'techno', 'mallorca', 'leon', 'vigo', 'bilbao', 'teruel', 'soria', 'burgos', 'avila',
  'ciega', 'casa', 'casas', 'cosa', 'cosas', 'caso', 'pasar', 'paso', 'pasos', 'poner', 'puesto',
  'puesta', 'pueda', 'puedo', 'puede', 'pueden', 'puedes', 'podria', 'podrias', 'quiero', 'quiere',
  'quisiera', 'queria', 'necesito', 'necesita', 'necesitamos', 'hacer', 'haga', 'hagas', 'tengo',
  'tiene', 'tienen', 'sobre', 'entre', 'desde', 'hasta', 'encima', 'debajo', 'delante', 'detras',
  'dentro', 'fuera', 'alrededor', 'cerca', 'lejos', 'donde', 'cuando', 'porque', 'como', 'cual', 'cuanto',
  'cuanta', 'cuantos', 'mismo', 'misma', 'otro', 'otra', 'otros', 'otras', 'todo', 'toda', 'todos',
  'todas', 'cada', 'varios', 'varias', 'poco', 'poca', 'grande', 'grandes', 'pequeno', 'pequena',
  'larga', 'ancha', 'alto', 'alta', 'bajo', 'baja', 'nuevo', 'nueva', 'viejo', 'vieja', 'chalet',
  'vivienda', 'edificio', 'local', 'tienda', 'negocio', 'empresa', 'taller', 'garaje', 'patio', 'jardin',
  'finca', 'parcela', 'terreno', 'solar', 'huerta', 'huerto', 'campo', 'pueblo', 'ciudad', 'calle',
  'carretera', 'camino', 'acera', 'plaza', 'rotonda', 'entrada', 'salida', 'acceso', 'pared', 'paredes',
  'muro', 'muros', 'suelo', 'techo', 'piso', 'planta', 'plantas', 'sotano', 'azotea', 'terraza',
  'fachada', 'esquina', 'lado', 'lados', 'frente', 'arriba', 'abajo', 'subir', 'bajar', 'entrar', 'salir',
  'cruzar', 'guardar', 'meter', 'sacar', 'colgar', 'levantar', 'proteger', 'cubrir', 'cerrar', 'abrir',
  'separar', 'sujetar', 'apoyar', 'anclar', 'soldar', 'pintar', 'montar', 'fabricar', 'calcular',
  'presupuesto', 'precio', 'coste', 'barato', 'urgente', 'rapido', 'gracias', 'favor', 'hola', 'buenas',
  'tardes', 'noches', 'coche', 'coches', 'camion', 'tractor', 'furgoneta', 'caravana', 'moto', 'motos',
  'caballos', 'vacas', 'ovejas', 'gallinas', 'animales', 'personas', 'gente', 'ninos', 'perro', 'perros',
  'gatos', 'agua', 'aguas', 'litros', 'kilos', 'toneladas', 'metro', 'medio', 'media', 'mitad', 'doble',
  'para', 'pero', 'tambien', 'solo', 'sola', 'unos', 'unas', 'algo', 'alguna', 'alguno', 'nada', 'tanto',
  'antes', 'despues', 'ahora', 'luego', 'siempre', 'nunca', 'bien', 'mejor', 'peor', 'mayor', 'menor',
  'menos', 'mas', 'muy', 'segun', 'normal', 'normativa', 'norma', 'cumpla', 'cumplir', 'cumple',
  'segura', 'seguro', 'seguridad', 'facil', 'fuerte', 'ligera', 'ligero', 'pesado', 'pesada', 'barata',
  'bonita', 'bonito', 'moderna', 'moderno', 'rustica', 'rustico', 'industrial', 'oficina', 'oficinas',
  'cocina', 'bano', 'salon', 'dormitorio', 'habitacion', 'escuela', 'colegio', 'hospital', 'iglesia',
  'piscina', 'playa', 'monte', 'montana', 'costa', 'nieve', 'viento', 'lluvia', 'granizo', 'sombra',
  'mesa', 'mesas', 'silla', 'sillas', 'cama', 'camas', 'caja', 'cajas', 'carro', 'carros', 'plazas',
  'vecino', 'vecinos', 'vecina', 'dueno', 'cliente', 'clientes', 'trabajo', 'trabajos', 'obra', 'obras',
  'tipo', 'tipos', 'forma', 'formas', 'modelo', 'estilo', 'color', 'colores', 'quedar', 'queda', 'quede',
  'llevar', 'lleve', 'lleva', 'tenga', 'tener', 'haber', 'sea', 'ser', 'estar', 'este', 'esta', 'esto',
  'estos', 'estas', 'ese', 'esa', 'eso', 'esos', 'esas', 'aquel', 'aquella', 'nuestro', 'nuestra',
  'vuestro', 'vuestra', 'suyo', 'suya', 'mio', 'mia', 'tuyo', 'tuya', 'unir', 'union', 'llegar',
  'llegue', 'llegan', 'acceder', 'cubra', 'cubre', 'tape', 'tapar', 'evitar', 'caer', 'caiga', 'caigan',
  'caida', 'caidas', 'agarrar', 'agarre', 'apoye', 'sube', 'suba', 'baje', 'baja', 'pase', 'pasen',
  'entren', 'entre', 'salga', 'salgan', 'abra', 'abran', 'cierre', 'cierra', 'cierren', 'tuvo', 'tuve',
  'tuvimos', 'tuvieron', 'maya', 'soldadora',
];

final Set<String> _commonSet = {..._common, ...commonSpanishGuard};

Set<String>? _lexicon;

/// Palabras del oficio (con sus plurales) que entiende el intérprete.
Set<String> get tradeLexicon => _lexicon ??= _buildLexicon();

Set<String> _buildLexicon() {
  final out = <String>{};
  const stop = {'entre', 'para', 'sobre', 'desde', 'hasta', 'como', 'solo', 'cada', 'tipo', 'doble', 'simple'};
  void add(String phrase) {
    final words = _plain(phrase).split(RegExp(r'[^a-z]+'));
    for (final w in words) {
      if (w.length < 4 || stop.contains(w)) continue;
      out.add(w);
      // plural solo de nombres sueltos («zanca» -> «zancas»), no de trozos de expresiones
      if (words.length == 1 && !w.endsWith('s')) {
        out.add(RegExp(r'[aeiou]$').hasMatch(w) ? '${w}s' : '${w}es');
      }
    }
  }

  for (final w in tradeWords) {
    add(w);
  }
  for (final ty in typologies) {
    ty.keywords.keys.forEach(add);
  }
  for (final g in glossary) {
    add(g.term);
    g.aka.forEach(add);
  }
  return out;
}

String _plain(String s) {
  const from = 'áàäâéèëêíìïîóòöôúùüûñç';
  const to = 'aaaaeeeeiiiioooouuuunc';
  final sb = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    sb.write(i >= 0 ? to[i] : ch);
  }
  return sb.toString();
}

/// Clave fonética del castellano: lo que suena igual da la misma clave
/// (varandilla = barandilla, balla = valla, zanka = zanca, hierro = ierro).
String phoneticKey(String w) {
  var s = w;
  s = s.replaceAll('ch', '#');
  s = s.replaceAll('ll', 'y');
  s = s.replaceAll(RegExp(r'qu(?=[ei])'), 'k');
  s = s.replaceAll(RegExp(r'gu(?=[ei])'), 'g');
  s = s.replaceAll(RegExp(r'c(?=[ei])'), 's');
  s = s.replaceAll(RegExp(r'g(?=[ei])'), 'j');
  s = s.replaceAll(RegExp(r'[cq]'), 'k');
  s = s.replaceAll('z', 's');
  s = s.replaceAll(RegExp(r'[vw]'), 'b');
  s = s.replaceAll('x', 'ks');
  s = s.replaceAll(RegExp(r'^hi(?=[aeou])'), 'y'); // hierro = yerro
  s = s.replaceAll('h', '');
  s = s.replaceAll(RegExp(r'n(?=[bp])'), 'm');
  s = s.replaceAll(RegExp(r'y(?![aeiou])'), 'i');
  s = s.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);
  return s;
}

Map<String, List<String>>? _byKey;

Map<String, List<String>> get _phonetic => _byKey ??= () {
      final m = <String, List<String>>{};
      for (final w in tradeLexicon) {
        m.putIfAbsent(phoneticKey(w), () => []).add(w);
      }
      return m;
    }();

/// Distancia de Damerau-Levenshtein (transposiciones de letras vecinas).
int editDistance(String a, String b, [int max = 3]) {
  if ((a.length - b.length).abs() > max) return max + 1;
  final d = List.generate(a.length + 1, (i) => List<int>.filled(b.length + 1, 0));
  for (var i = 0; i <= a.length; i++) {
    d[i][0] = i;
  }
  for (var j = 0; j <= b.length; j++) {
    d[0][j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    var rowMin = 1 << 20;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      var v = d[i - 1][j - 1] + cost;
      if (d[i - 1][j] + 1 < v) v = d[i - 1][j] + 1;
      if (d[i][j - 1] + 1 < v) v = d[i][j - 1] + 1;
      if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1] && d[i - 2][j - 2] + 1 < v) {
        v = d[i - 2][j - 2] + 1;
      }
      d[i][j] = v;
      if (v < rowMin) rowMin = v;
    }
    if (rowMin > max) return max + 1;
  }
  return d[a.length][b.length];
}

/// Diminutivos: «escalerita», «puertecita», «portoncito», «vallita».
String? undiminish(String w) {
  final m = RegExp(r'^(.{3,}?)(ecit|cit|it|ill)(a|o)(s?)$').firstMatch(w);
  if (m == null) return null;
  final stem = m[1]!, suf = m[2]!, plural = m[4]!;
  final cands = switch (suf) {
    'ecit' => ['${stem}e', '${stem}a', '${stem}o'],
    'cit' => [stem, '${stem}e', '${stem}a'],
    _ => ['$stem${m[3]}', '${stem}a', '${stem}o', '${stem}e'],
  };
  for (final c in cands) {
    if (tradeLexicon.contains(c)) return '$c$plural';
  }
  return null;
}

/// Palabra del oficio a la que corresponde [w], o null si no hay que tocarla.
String? correctWord(String w) {
  if (w.length < 4 || RegExp(r'[^a-z]').hasMatch(w)) return null;
  if (tradeLexicon.contains(w) || _commonSet.contains(w)) return null;
  final dim = undiminish(w);
  if (dim != null) return dim;
  // suena igual que una palabra del oficio
  final same = _phonetic[phoneticKey(w)];
  if (same != null && same.length == 1) return same.first;
  if (w.length < 6) return null;
  // falta de tecleo: una letra (dos en palabras largas) de diferencia.
  // A igual distancia gana la palabra más larga: al teclear deprisa se comen letras.
  final max = w.length >= 9 ? 2 : 1;
  String? best;
  var bestScore = 1 << 20;
  var tie = false;
  for (final c in tradeLexicon) {
    if ((c.length - w.length).abs() > max) continue;
    if (c[0] != w[0] && phoneticKey(c[0]) != phoneticKey(w[0])) continue;
    final d = editDistance(w, c, max);
    if (d > max) continue;
    final score = d * 10 + (c.length > w.length ? 0 : (c.length == w.length ? 1 : 2));
    if (score < bestScore) {
      bestScore = score;
      best = c;
      tie = false;
    } else if (score == bestScore && c != best && phoneticKey(c) != phoneticKey(best!)) {
      tie = true;
    }
  }
  return tie ? null : best;
}

/// Correcciones hechas en el último texto: (lo escrito, lo entendido).
class SpanishFix {
  final String text;
  final List<(String, String)> changes;
  const SpanishFix(this.text, this.changes);
}

final Map<String, SpanishFix> _cache = {};

/// Corrige el texto normalizado con el diccionario de castellano.
SpanishFix fixSpanishText(String t) {
  final hit = _cache[t];
  if (hit != null) return hit;
  final changes = <(String, String)>[];
  final out = t.replaceAllMapped(RegExp(r'[a-z]+'), (m) {
    final w = m[0]!;
    final c = correctWord(w);
    if (c == null || c == w) return w;
    changes.add((w, c));
    return c;
  });
  final r = SpanishFix(out, changes);
  if (_cache.length > 200) _cache.clear();
  _cache[t] = r;
  return r;
}

/// Solo el texto corregido.
String fixSpanish(String t) => fixSpanishText(t).text;

/// Nota para el usuario con lo que se ha corregido, o null si nada.
String? spanishNote(String normalized) {
  final ch = fixSpanishText(normalized).changes;
  if (ch.isEmpty) return null;
  final seen = <String>{};
  final parts = [for (final (a, b) in ch) if (seen.add(a)) '«$a» → $b'];
  return 'Entiendo ${parts.join(', ')}.';
}
