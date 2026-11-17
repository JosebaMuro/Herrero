import 'model.dart';
import 'parser.dart';
import 'spanish.dart';
import 'vocabulary.dart';

/// Sugerencia de autocompletado: [label] es lo que se muestra y [apply]
/// devuelve el texto completo con la sugerencia aplicada.
class Suggestion {
  final String label;
  final String text;
  final int cursor;
  const Suggestion(this.label, this.text, this.cursor);
}

/// Términos con tildes que se proponen al escribir (más usados primero).
const List<String> _terms = [
  'nave',
  'nave a dos aguas',
  'nave a un agua',
  'marquesina',
  'marquesina para coches',
  'pérgola',
  'porche',
  'cobertizo',
  'tejadillo',
  'altillo',
  'entreplanta',
  'escalera',
  'escalera recta',
  'escalera de caracol',
  'escalera en L',
  'escalera en U',
  'escalera de zanca central',
  'escala de gato',
  'escalones',
  'peldaños',
  'peldaños de tramex',
  'peldaños de chapa lagrimada',
  'meseta',
  'descansillo',
  'huella',
  'contrahuella',
  'tabica',
  'mamperlán',
  'zanca',
  'barandilla',
  'barandilla de vidrio',
  'barandilla de cables',
  'barandilla de chapa perforada',
  'barandilla con lamas',
  'barandilla de acero inoxidable',
  'barandilla con rodapié',
  'pasamanos',
  'pasamanos a pared',
  'balaustres',
  'barrotes',
  'rodapié',
  'antepecho',
  'guardacuerpos',
  'pasarela',
  'pasarela peatonal',
  'cerchas',
  'cerchas a dos aguas',
  'torre',
  'torre para depósito',
  'estantería',
  'rack para palés',
  'cancela',
  'cancela corredera',
  'cancela abatible',
  'portón',
  'puerta peatonal',
  'valla',
  'valla de malla',
  'vallado perimetral',
  'reja de ventana',
  'rejas',
  'cerramiento de parcela',
  'malla electrosoldada',
  'pórtico para polipasto',
  'grúa pórtico',
  'poste',
  'mástil para bandera',
  'báculo',
  'cartel',
  'galvanizado en caliente',
  'galvanizada',
  'galvanizado',
  'lacado',
  'lacada en negro',
  'pintado',
  'pintura antioxidante',
  'acero corten',
  'acero inoxidable',
  'inoxidable 316',
  'aluminio',
  'panel sándwich',
  'chapa grecada',
  'policarbonato',
  'policarbonato celular',
  'tramex',
  'chapa lagrimada',
  'vidrio laminado',
  'pilares',
  'correas',
  'tirantes',
  'tubo cuadrado',
  'tubo rectangular',
  'tubo redondo',
  'pletina',
  'angular',
  'altura',
  'de altura',
  'de ancho',
  'de largo',
  'al alero',
  'de luz',
  'pórticos cada',
  'de diámetro',
  'exterior',
  'interior',
  'para almacén',
  'para terraza',
  'para coches',
  'para vivienda',
  'sobrecarga',
  'anclada al canto del forjado',
  'anclaje químico',
  'placa de anclaje',
  'soldadura',
  'cubierta',
  'fachada',
];

/// Lo que suele seguir según la tipología: (frase, se omite si el texto ya lo dice).
final Map<StructureType, List<(String, String)>> _next = {
  StructureType.escalera: [
    ('de 3 m de altura', r'altura|alto|desnivel|planta|\d+(?:\.\d+)?\s*m(?!m)'),
    ('y 1 m de ancho', r'ancho|diametro'),
    ('en L', r'en l(?![a-z])|en u(?![a-z])|caracol|gato|zanca central'),
    ('de caracol', r'en l(?![a-z])|en u(?![a-z])|caracol|gato|zanca central'),
    ('con barandilla', r'barandilla|pasamanos|gato'),
    ('con peldaños de tramex', r'tramex|chapa|gato'),
    ('galvanizada', r'galvaniz|lacad|pintad|inox|corten'),
    ('exterior', r'exterior|interior'),
  ],
  StructureType.barandilla: [
    ('de 10 m', r'\d+(?:\.\d+)?\s*m(?!m)'),
    ('de 1,10 m de altura', r'altura|alto'),
    ('de vidrio', r'vidrio|cables|barrotes|chapa|lamas|pared'),
    ('con barrotes', r'vidrio|cables|barrotes|chapa|lamas|pared'),
    ('con rodapié', r'rodapie|pared'),
    ('de acero inoxidable', r'inox|galvaniz|lacad|pintad|corten'),
    ('para terraza', r'terraza|balcon|escalera|rampa|uso|para'),
  ],
  StructureType.nave: [
    ('de 20 x 12 m', r'\d+\s*x\s*\d+'),
    ('a dos aguas', r'agua'),
    ('con 6 m al alero', r'alero|altura'),
    ('pórticos cada 5 m', r'porticos cada|cada \d'),
    ('con panel sándwich', r'sandwich|chapa|cubierta'),
    ('en Madrid', r'(?<![a-z])en [a-z]{4,}'),
  ],
  StructureType.marquesina: [
    ('de 5 x 5 m', r'\d+\s*x\s*\d+'),
    ('para 2 coches', r'coche|plaza|terraza|jardin'),
    ('de 2,5 m de alto', r'alto|altura'),
    ('con panel sándwich', r'sandwich|chapa|policarbonato|vidrio|cubierta'),
    ('galvanizada', r'galvaniz|lacad|pintad|inox|alumin'),
  ],
  StructureType.entreplanta: [
    ('de 8 x 4 m', r'\d+\s*x\s*\d+'),
    ('a 3 m de altura', r'altura|alto'),
    ('con suelo de tramex', r'tramex|chapa|madera|suelo'),
    ('para almacén', r'almacen|oficina|uso|para'),
    ('con escalera', r'escalera'),
  ],
  StructureType.pasarela: [
    ('de 8 m de luz', r'luz|\d+(?:\.\d+)?\s*m(?!m)'),
    ('y 1,5 m de ancho', r'ancho'),
    ('con suelo de tramex', r'tramex|chapa'),
    ('con barandilla', r'barandilla'),
  ],
  StructureType.cercha: [
    ('de 10 m de luz', r'luz'),
    ('a dos aguas', r'agua|paralel'),
    ('sobre pilares de 3 m', r'pilares|muros'),
    ('con panel sándwich', r'sandwich|chapa|teja'),
  ],
  StructureType.torre: [('de 6 m', r'\d+(?:\.\d+)?\s*m(?!m)'), ('para depósito de 5000 litros', r'deposito|litros')],
  StructureType.estanteria: [
    ('de 3 m de largo', r'largo|\d+\s*x'),
    ('con 5 baldas', r'baldas|niveles|alturas'),
    ('de 2,5 m de alto', r'alto|altura'),
    ('para palés', r'pales|cajas'),
  ],
  StructureType.cancela: [
    ('de 4 m', r'\d+(?:\.\d+)?\s*m(?!m)'),
    ('corredera', r'corred|abatible'),
    ('abatible de dos hojas', r'corred|abatible|hoja'),
    ('de 2 m de alto', r'alto|altura'),
    ('con chapa', r'chapa|barrotes|malla'),
    ('lacada en negro', r'lacad|galvaniz|pintad'),
  ],
  StructureType.valla: [
    ('de 20 m', r'\d+(?:\.\d+)?\s*m(?!m)'),
    ('de 2 m de altura', r'altura|alto'),
    ('de malla', r'malla|barrotes|chapa|reja'),
    ('de barrotes', r'malla|barrotes|chapa|reja'),
    ('galvanizada', r'galvaniz|lacad|pintad'),
  ],
  StructureType.portico: [
    ('para polipasto de 2 t', r'polipasto|\d+\s*t(?![a-z])'),
    ('de 5 m de luz', r'luz'),
    ('de 4 m de alto', r'alto|altura'),
  ],
  StructureType.poste: [('de 6 m', r'\d+(?:\.\d+)?\s*m(?!m)'), ('para cartel de 3 x 2 m', r'cartel|bandera|farola')],
};

List<String>? _vocab;

/// Vocabulario de sugerencias: términos propios + glosario (con tildes).
List<String> get _vocabulary => _vocab ??= () {
  final seen = <String>{};
  final out = <String>[];
  void add(String t) {
    if (t.contains('/') || t.contains('(')) return;
    // «Cartela» → «cartela», pero «IPE» o «HEB» se quedan
    if (t.length > 1 && t[1] == t[1].toLowerCase()) t = t[0].toLowerCase() + t.substring(1);
    final n = normalize(t);
    if (seen.any((o) => o.startsWith(n) && o != n)) return; // «galva» ya está en «galvanizado»
    if (seen.add(n)) out.add(t);
  }

  _terms.forEach(add);
  for (final g in glossary) {
    add(g.term);
    g.aka.forEach(add);
  }
  return out;
}();

final _word = RegExp(r'[a-záéíóúüñ0-9]+$', caseSensitive: false);

/// Sugerencias para el texto [text] con el cursor en [cursor] (por defecto, al final).
List<Suggestion> suggest(String text, {int? cursor, int max = 6}) {
  final cur = (cursor == null || cursor < 0 || cursor > text.length) ? text.length : cursor;
  final before = text.substring(0, cur), after = text.substring(cur);
  if (before.trim().isEmpty) return const [];
  final out = <Suggestion>[];
  final seen = <String>{};
  Suggestion make(String label, String head) {
    final glue = after.startsWith(' ') || after.isEmpty ? '' : ' ';
    final t = '$head$label${after.isEmpty ? ' ' : glue}$after';
    return Suggestion(label, t, head.length + label.length + 1);
  }

  final partial = _word.firstMatch(before)?[0] ?? '';
  if (partial.isNotEmpty) {
    // 1) completar la palabra (o la expresión) que se está escribiendo
    final head0 = before.substring(0, before.length - partial.length);
    final tokens = normalize(before).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final p = normalize(partial);
    if (p.length >= 2 || tokens.length >= 2) {
      final cands = <(int, int, String, String)>[]; // (contexto, orden, etiqueta, cabeza)
      final voc = _vocabulary;
      for (var i = 0; i < voc.length; i++) {
        final term = voc[i];
        final n = normalize(term);
        for (var k = 3; k >= 1; k--) {
          if (tokens.length < k || (k == 1 && p.length < 2)) continue;
          final tail = tokens.sublist(tokens.length - k).join(' ');
          if (n.length > tail.length && n.startsWith(tail) && (k == 1 || n.split(' ').length >= k)) {
            // cabeza: el texto sin las k últimas palabras
            var head = head0;
            for (var j = 1; j < k; j++) {
              head = head.replaceFirst(RegExp(r'[a-záéíóúüñ0-9]+\s*$', caseSensitive: false), '');
            }
            cands.add((k, i, term, head));
            break;
          }
        }
      }
      cands.sort((a, b) => a.$1 != b.$1 ? b.$1.compareTo(a.$1) : a.$2.compareTo(b.$2));
      final upper = before.trimLeft().isNotEmpty && before.trimLeft()[0] != before.trimLeft()[0].toLowerCase();
      for (final c in cands) {
        var label = c.$3;
        if (c.$4.trim().isEmpty && upper) label = label[0].toUpperCase() + label.substring(1);
        if (seen.add(normalize(label))) out.add(make(label, c.$4));
        if (out.length >= max) return out;
      }
      // 2) palabra mal escrita: se propone la corrección
      if (out.isEmpty && p.length >= 4) {
        final fix = correctWord(p);
        if (fix != null) {
          final shown = _vocabulary.firstWhere((t) => normalize(t) == fix, orElse: () => fix);
          out.add(make(head0.trim().isEmpty && upper ? shown[0].toUpperCase() + shown.substring(1) : shown, head0));
        }
      }
    }
    return out;
  }

  // 3) palabra terminada: lo que suele seguir para la tipología reconocida
  final t = canonicalize(normalize(before));
  final (type, _, _) = keywordType(t);
  if (type == null) return const [];
  for (final (phrase, skip) in _next[type] ?? const <(String, String)>[]) {
    if (RegExp(skip).hasMatch(t)) continue;
    final head = before.endsWith(' ') ? before : '$before ';
    out.add(make(phrase, head));
    if (out.length >= max) break;
  }
  return out;
}
