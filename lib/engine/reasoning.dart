import 'model.dart';
import 'parser.dart';
import 'spanish.dart';

/// Razonamiento de oficio: lo que un técnico deduce de una petición aunque no
/// traiga medidas («para 2 coches», «que quepa el tractor»…). Determinista y
/// explicado, para que el usuario vea de dónde sale cada número.
class Deduction {
  final String field; // length, width, height, liveLoad…
  final String phrase; // frase en el vocabulario del intérprete
  final String why;
  const Deduction(this.field, this.phrase, this.why);
}

const _units = {
  'cero': 0, 'un': 1, 'una': 1, 'uno': 1, 'dos': 2, 'tres': 3, 'cuatro': 4, 'cinco': 5, 'seis': 6, 'siete': 7,
  'ocho': 8, 'nueve': 9, 'diez': 10, 'once': 11, 'doce': 12, 'trece': 13, 'catorce': 14, 'quince': 15,
  'dieciseis': 16, 'diecisiete': 17, 'dieciocho': 18, 'diecinueve': 19, 'veinte': 20, 'veinticinco': 25,
  'treinta': 30, 'cuarenta': 40, 'cincuenta': 50, 'sesenta': 60, 'cien': 100, 'medio': 0.5,
};

/// Sustantivos tras los que un número escrito con letra es una cantidad o una
/// medida («ocho metros», «cuatro alturas», «dos coches»).
const _counted = r'(?:metros?|m\b|cm|mm|coches?|plazas?|vehiculos?|turismos?|furgonetas?|camion(?:es)?|tractor(?:es)?|'
    r'autocaravanas?|caravanas?|motos?|caballos?|alturas?|niveles?|baldas?|estantes?|pisos?|plantas?|tramos?|'
    r'peldanos?|escalones?|personas?|palets?|pales?|toneladas?|kilos?|kg|litros?|hojas?|vanos?|porticos?)';

/// Convierte en cifras los números escritos con letra que cuentan o miden.
/// Respeta expresiones fijas como «a dos aguas» o «dos hojas» del intérprete.
String spellNumbers(String text) {
  var t = fixSpanish(normalize(text));
  final words = _units.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  final re = RegExp('(?<![a-z])(${words.join('|')})(?:\\s+y\\s+(medio))?(\\s+(?:de\\s+)?)($_counted)');
  t = t.replaceAllMapped(re, (m) {
    final w = m[1]!;
    if ((w == 'un' || w == 'una') && !RegExp(r'^(?:metros?|m|coches?|plazas?|tractor|camion|caballos?)$').hasMatch(m[4]!)) {
      return m[0]!;
    }
    final v = _units[w]! + (m[2] != null ? 0.5 : 0);
    final s = v % 1 == 0 ? v.toInt().toString() : v.toString();
    return '$s${m[3]}${m[4]}';
  });
  return t;
}

String _f(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 2).replaceAll('.', ',');

/// (ancho de plaza, fondo, altura libre) por tipo de vehículo, en m.
const _vehicles = <String, (String, double, double, double)>{
  'coche': ('coche', 2.5, 5.0, 2.5),
  'turismo': ('coche', 2.5, 5.0, 2.5),
  'vehiculo': ('vehículo', 2.5, 5.0, 2.5),
  'plaza': ('plaza', 2.5, 5.0, 2.5),
  'moto': ('moto', 1.2, 2.5, 2.2),
  'furgoneta': ('furgoneta', 3.0, 6.5, 3.0),
  'autocaravana': ('autocaravana', 3.5, 8.0, 3.8),
  'caravana': ('caravana', 3.5, 8.0, 3.8),
  'tractor': ('tractor', 3.5, 6.5, 4.2),
  'cosechadora': ('cosechadora', 4.5, 9.0, 4.5),
  'camion': ('camión', 4.0, 12.0, 4.8),
};

/// Deducciones de oficio a partir del uso. [t] es el texto ya normalizado y
/// con los números en cifras ([spellNumbers]).
List<Deduction> tradeDeductions(String t, StructureType type) {
  final out = <Deduction>[];
  if (type == StructureType.marquesina || type == StructureType.nave) {
    // vehículos: plazas en fila
    final names = _vehicles.keys.join('|');
    final many = RegExp('(\\d+)\\s*(?:plazas?\\s*(?:de\\s*)?)?($names)(?:e?s)?(?![a-z])').firstMatch(t);
    final one = RegExp('(?:el|un|una|mi|la|del|al|para)\\s+($names)(?![a-z])').firstMatch(t);
    final key = many?[2] ?? one?[1];
    if (key != null) {
      final n = many != null ? int.parse(many[1]!) : 1;
      final (name, w, d, h) = _vehicles[key]!;
      if (n >= 1 && n <= 40) {
        final len = n * w;
        final plural = RegExp('[aeiou]\$').hasMatch(name) ? '${name}s' : '${name.replaceAll('ó', 'o')}es';
        final what = n == 1 ? 'un $name' : '$n $plural';
        out.add(Deduction('length', 'largo ${_f(len)} m',
            'Para $what: ${n == 1 ? 'una plaza' : '$n plazas'} de ${_f(w)} m de ancho → ${_f(len)} m de largo.'));
        out.add(Deduction('width', 'ancho ${_f(d)} m', 'Fondo de plaza para $name: ${_f(d)} m.'));
        out.add(Deduction('height', 'altura ${_f(h)} m', 'Altura libre para que pase un $name con holgura: ${_f(h)} m.'));
      }
    }
    // caballos: boxes de 3,5 x 3,5 m en fila con pasillo de 3 m
    final horses = RegExp(r'(\d+)\s*caballos?').firstMatch(t);
    if (horses != null && out.isEmpty) {
      final n = int.parse(horses[1]!);
      out.add(Deduction('length', 'largo ${_f(n * 3.5)} m', '$n boxes de 3,5 x 3,5 m en fila → ${_f(n * 3.5)} m.'));
      out.add(Deduction('width', 'ancho 6,5 m', 'Box de 3,5 m más pasillo de 3 m.'));
      out.add(Deduction('height', 'altura 3,5 m', 'Altura libre en cuadras: 3,5 m.'));
    }
  }
  if (type == StructureType.pasarela) {
    if (RegExp(r'carretilla|transpalet|toro|apilador').hasMatch(t)) {
      out.add(Deduction('width', 'ancho 2 m', 'Paso de carretillas: 2 m de ancho útil.'));
      out.add(Deduction('liveLoad', 'sobrecarga 500 kg/m2', 'Tráfico de carretillas: sobrecarga de 5 kN/m².'));
    } else if (RegExp(r'peatonal|andando|personas|a pie|caminando').hasMatch(t)) {
      out.add(Deduction('width', 'ancho 1,2 m', 'Paso de personas en ambos sentidos: 1,2 m de ancho útil.'));
    }
  }
  if (type == StructureType.cancela) {
    if (RegExp(r'camion').hasMatch(t)) {
      out.add(Deduction('length', 'hueco 5 m', 'Paso de camiones: hueco libre de 5 m.'));
      out.add(Deduction('height', 'altura 2,5 m', 'Puerta de 2,5 m de alto para recinto de camiones.'));
    } else if (RegExp(r'tractor|cosechadora|maquinaria').hasMatch(t)) {
      out.add(Deduction('length', 'hueco 4,5 m', 'Paso de tractor y aperos: hueco libre de 4,5 m.'));
    } else if (RegExp(r'coche|garaje|vehiculo').hasMatch(t)) {
      out.add(Deduction('length', 'hueco 3,5 m', 'Paso de un coche con holgura: hueco libre de 3,5 m.'));
    }
  }
  return out;
}
