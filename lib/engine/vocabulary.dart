/// Vocabulario técnico del oficio (estructura metálica, calderería ligera y
/// cerrajería) y regionalismos. Sirve para dos cosas:
///  1. [canonicalize] reescribe sinónimos, abreviaturas, faltas habituales y
///     números escritos con letra a la forma que entiende el intérprete.
///  2. [glossary] es el diccionario que se muestra en la app.
library;

class TradeTerm {
  final String term;
  final String meaning;
  final String category;
  final List<String> aka;
  const TradeTerm(this.term, this.category, this.meaning, [this.aka = const []]);
}

const glossaryCategories = [
  'Perfiles y materiales',
  'Elementos estructurales',
  'Uniones y soldadura',
  'Cerrajería y herrajes',
  'Cubiertas, suelos y cerramientos',
  'Escaleras y barandillas',
  'Geometría y cálculo',
  'Cimentación y anclajes',
  'Acabados y protección',
];

/// Reglas de reescritura (texto ya normalizado: minúsculas y sin tildes).
/// El orden importa: primero unidades y números, luego términos.
const List<(String, String)> _unitRules = [
  (r'(\d)\s*(?:ml|m\.l\.|metros lineales|metro lineal|m lineales)(?![a-z])', r'$1 m de longitud'),
  (r'(\d)\s*(?:mtrs?|mt|mtr)\.?(?![a-z0-9])', r'$1 m'),
  (r'(\d)\s*(?:metros cuadrados|mts2|mt2|m\^2|mtrs2)', r'$1 m2'),
  (r'(\d)\s*(?:metros cubicos|mts3|m\^3)', r'$1 m3'),
  (r'(\d)\s*(?:centimetros|cms)(?![a-z])', r'$1 cm'),
  (r'(\d)\s*(?:milimetros)(?![a-z])', r'$1 mm'),
  (r'(\d)\s*(?:kilos|kgs|kilogramos|kilo)(?![a-z])', r'$1 kg'),
  (r'(\d)\s*(?:toneladas|tonelada|tns?|tm)(?![a-z])', r'$1 t'),
  (r'(\d)\s*(?:kilonewtons?|kilonewton)(?![a-z])', r'$1 kn'),
];

/// Prefijos (raíces de palabra): solo se exige separación por la izquierda.
const List<(String, String)> _prefixRules = [
  (r'sandwitch|sanwich|sandwic(?!h)|sandwhich|sandwch|sanguich', 'sandwich'),
  (r'galbaniz', 'galvaniz'),
  (r'termolacad|lacado al horno', 'lacad'),
  (r'zincad\w*|cincad\w*|galvanizacion', 'galvanizado'),
  (r'antioxid\w*', 'imprimacion'),
];

/// Palabras o expresiones completas.
const List<(String, String)> _termRules = [
  // --- Medidas -------------------------------------------------------------
  ('luz libre|vano libre|claro libre|luz entre apoyos|luz entre pilares', 'luz'),
  ('altura a salvar|desnivel|altura de planta|de suelo a suelo|altura entre plantas|altura entre forjados', 'altura'),
  ('ancho de paso|ancho util|anchura util|anchura libre|ancho libre', 'ancho'),
  ('longitud total|largo total|desarrollo total', 'longitud'),
  ('hueco de paso|paso libre|luz de paso|vano de (?:la )?puerta|ancho de (?:la )?puerta|apertura libre', 'hueco'),
  ('separacion entre ejes|distancia entre ejes|entre ejes', 'intereje'),
  ('altura de cumbrera|altura a cumbrera|altura en cumbrera|altura maxima en cumbrera', 'cumbrera'),
  // --- Tipologías y elementos --------------------------------------------
  ('escalera caracol|escalera helicoidal', 'escalera de caracol'),
  ('palets?|paletas?|palles', 'pales'),
  ('diferencial(?:es)? electric[oa]s?|tecles?|aparejo electrico', 'polipasto'),
  ('jacenas?', 'viga'),
  ('pies? derechos?', 'pilares'),
  ('galpon(?:es)?|tinglado', 'nave'),
  ('tranqueras?|tranqueros?|talanqueras?', 'cancela'),
  ('puerta de (?:finca|parcela|cochera|vehiculos|entrada de vehiculos)', 'porton'),
  ('cuchillos?(?: de cubierta)?|tijeras? de cubierta|formas de cubierta', 'cerchas'),
  ('alambrada|cercado|cerco perimetral|vallado perimetral', 'valla'),
  ('pretil(?:es)?|balaustrada|barandado|barandal(?:es)?', 'barandilla'),
  ('astas?(?: de bandera)?', 'mastil'),
  ('escalones', 'peldanos'),
  ('descansillo|rellano', 'meseta'),
  ('pasadizo|pasillo volado', 'pasarela'),
  ('emparrado|parral', 'pergola'),
  ('columna de alumbrado|poste de luz|poste de alumbrado', 'farola'),
  ('cartel publicitario|valla de publicidad|panel publicitario', 'valla publicitaria'),
  // --- Cubiertas y suelos ---------------------------------------------------
  (
    'panel aislante|panel aislado|chapa aislada|panel de poliuretano|panel termoaislante|chapa sandwich',
    'panel sandwich',
  ),
  ('chapa (?:trapezoidal|perfilada|nervada|minionda|ondulada)', 'chapa grecada'),
  ('onduline|placas? traslucidas?|lucernarios?|policarbonato (?:alveolar|compacto)', 'policarbonato'),
  (
    'trames|tramix|tramet|tramez|tramek|emparrillado|rejilla de piso|piso de rejilla|suelo de rejilla|rejilla tramex',
    'tramex',
  ),
  ('chapa (?:estriada|damero|antideslizante|de lagrima|de diamante|diamante|de botones)', 'chapa lagrimada'),
  ('forjado colaborante|chapa colaborante|losa mixta|forjado mixto', 'colaborante'),
  ('placas fotovoltaicas|modulos fotovoltaicos|paneles fv|placas fv|modulos solares', 'paneles solares'),
  // --- Acero y acabados ------------------------------------------------------
  ('a42|ae ?275|st ?37|s275jr|s275j0', 's275'),
  ('a52|ae ?355|st ?52|s355jr|s355j2|s355j0', 's355'),
  ('galva', 'galvanizado'),
  ('pintura en polvo|pintura epoxi|epoxi|poliester en polvo', 'lacado'),
  ('minio|imprimado', 'imprimacion'),
  ('acero patinable|acero autopatinable|oxidado|oxido', 'corten'),
  ('acero inox|inoxidable|aisi ?304|aisi ?316', 'inox'),
];

const Map<String, num> _numbers = {
  'un': 1,
  'una': 1,
  'uno': 1,
  'dos': 2,
  'tres': 3,
  'cuatro': 4,
  'cinco': 5,
  'seis': 6,
  'siete': 7,
  'ocho': 8,
  'nueve': 9,
  'diez': 10,
  'once': 11,
  'doce': 12,
  'trece': 13,
  'catorce': 14,
  'quince': 15,
  'dieciseis': 16,
  'diecisiete': 17,
  'dieciocho': 18,
  'diecinueve': 19,
  'veinte': 20,
  'veinticinco': 25,
  'treinta': 30,
  'cuarenta': 40,
  'cincuenta': 50,
  'sesenta': 60,
  'cien': 100,
  'mil': 1000,
};

const _units =
    r'metros?|m|cm|mm|kg|t|litros|hojas?|niveles|alturas|baldas|estantes|pales|plantas|pisos|tramos|coches|vanos|porticos';

String _expand(String rep, Match m) => rep.replaceAllMapped(RegExp(r'\$(\d)'), (g) => m.group(int.parse(g[1]!)) ?? '');

/// Reescribe el texto normalizado con el vocabulario canónico.
String canonicalize(String t) {
  var s = t;
  final words = _numbers.keys.join('|');
  // "cinco mil litros" / "5 mil kg"
  s = s.replaceAllMapped(RegExp('(?<![a-z])($words)\\s+mil(?![a-z])'), (m) => '${_numbers[m[1]!]! * 1000}');
  s = s.replaceAllMapped(RegExp(r'(\d+(?:\.\d+)?)\s+mil(?![a-z])'), (m) => '${(double.parse(m[1]!) * 1000).round()}');
  // Números con letra: "tres metros y medio" -> "3.5 metros"
  s = s.replaceAllMapped(RegExp('(?<![a-z])($words)\\s+($_units)(\\s+y\\s+medio)?(?![a-z])'), (m) {
    final v = _numbers[m[1]!]! + (m[3] != null ? 0.5 : 0);
    return '${v % 1 == 0 ? v.toInt() : v} ${m[2]}';
  });
  s = s.replaceAllMapped(RegExp(r'(\d+)\s+(metros?|m)\s+y\s+medio'), (m) => '${int.parse(m[1]!) + 0.5} ${m[2]}');
  s = s.replaceAll(RegExp(r'(?<![a-z])medio metro'), '0.5 m');
  s = s.replaceAll(RegExp(r'(?<![a-z0-9] )metro y medio'), '1.5 m');
  for (final r in _unitRules) {
    s = s.replaceAllMapped(RegExp(r.$1), (m) => _expand(r.$2, m));
  }
  for (final r in _prefixRules) {
    s = s.replaceAll(RegExp('(?<![a-z])(?:${r.$1})'), r.$2);
  }
  for (final r in _termRules) {
    s = s.replaceAll(RegExp('(?<![a-z])(?:${r.$1})(?![a-z])'), r.$2);
  }
  return s;
}

/// Diccionario del oficio que se muestra en la app.
const List<TradeTerm> glossary = [
  // Perfiles y materiales
  TradeTerm(
    'IPE',
    'Perfiles y materiales',
    'Perfil laminado en doble T de alas estrechas. Trabaja muy bien a flexión en su plano: vigas, correas y dinteles.',
    ['viga doble T'],
  ),
  TradeTerm(
    'HEB / HEA',
    'Perfiles y materiales',
    'Perfil en H de alas anchas (HEB macizo, HEA aligerado). Pilares y vigas muy cargadas.',
    ['perfil H'],
  ),
  TradeTerm(
    'UPN',
    'Perfiles y materiales',
    'Perfil en U de alas inclinadas. Zancas de escalera, bastidores, cercos de cancela y vigas de borde.',
    ['U', 'canal'],
  ),
  TradeTerm('UPE / UAP', 'Perfiles y materiales', 'Perfil en U de alas paralelas; más fácil de unir que el UPN.'),
  TradeTerm(
    'SHS (tubo cuadrado)',
    'Perfiles y materiales',
    'Perfil hueco cuadrado conformado en frío o en caliente. Pilares, montantes, postes y celosías.',
    ['tubo cuadrado', 'cuadradillo'],
  ),
  TradeTerm(
    'RHS (tubo rectangular)',
    'Perfiles y materiales',
    'Perfil hueco rectangular. Largueros, viguetas, bastidores y travesaños.',
    ['tubo rectangular', 'tubo estructural'],
  ),
  TradeTerm('CHS (tubo redondo)', 'Perfiles y materiales', 'Perfil hueco circular. Pasamanos, mástiles y báculos.', [
    'tubo redondo',
  ]),
  TradeTerm(
    'Angular (L)',
    'Perfiles y materiales',
    'Perfil en L de alas iguales o desiguales. Arriostramientos, cantoneras, casquillos y montantes ligeros.',
    ['cantonera', 'ángulo', 'perfil L'],
  ),
  TradeTerm(
    'Pletina',
    'Perfiles y materiales',
    'Llanta o barra plana laminada. Cartelas, orejetas, casquillos y refuerzos.',
    ['llanta', 'platabanda'],
  ),
  TradeTerm(
    'Redondo / varilla',
    'Perfiles y materiales',
    'Barra maciza de sección circular. Tirantes, barrotes y pernos de anclaje.',
    ['varilla', 'barra'],
  ),
  TradeTerm(
    'Cuadradillo',
    'Perfiles y materiales',
    'Barra maciza cuadrada (12, 14, 16 mm…). Barrotes de rejas y barandillas.',
  ),
  TradeTerm(
    'Perfil conformado (C / Z)',
    'Perfiles y materiales',
    'Chapa plegada en frío en forma de C o Z. Correas ligeras de cubierta y fachada.',
    ['correa Z', 'correa C'],
  ),
  TradeTerm(
    'S275 / S355',
    'Perfiles y materiales',
    'Calidades de acero estructural (límite elástico 275 o 355 N/mm²). Antes A42 y A52.',
    ['A42', 'A52', 'St37', 'St52'],
  ),
  TradeTerm('Acero corten', 'Perfiles y materiales', 'Acero autopatinable que forma una pátina de óxido protectora.', [
    'acero patinable',
  ]),
  TradeTerm(
    'Acero inoxidable',
    'Perfiles y materiales',
    'AISI 304 / 316. Barandillas y elementos vistos; se calcula con EN 1993-1-4.',
    ['inox'],
  ),

  // Elementos estructurales
  TradeTerm('Pilar', 'Elementos estructurales', 'Elemento vertical que baja las cargas a la cimentación.', [
    'columna',
    'soporte',
    'pie derecho',
  ]),
  TradeTerm('Viga', 'Elementos estructurales', 'Elemento horizontal que trabaja a flexión.', ['jácena']),
  TradeTerm(
    'Pórtico',
    'Elementos estructurales',
    'Conjunto de dos pilares y el dintel (viga) que los une, normalmente con nudos rígidos.',
  ),
  TradeTerm(
    'Dintel',
    'Elementos estructurales',
    'Viga del pórtico; en naves a dos aguas va inclinada hasta la cumbrera.',
  ),
  TradeTerm(
    'Correa',
    'Elementos estructurales',
    'Viga secundaria que apoya sobre dinteles o cerchas y recibe la chapa de cubierta.',
  ),
  TradeTerm('Larguero de fachada', 'Elementos estructurales', 'Correa vertical de fachada que soporta el cerramiento.'),
  TradeTerm(
    'Cercha',
    'Elementos estructurales',
    'Estructura triangulada que salva una luz trabajando a esfuerzos axiles.',
    ['cuchillo', 'armadura', 'celosía', 'tijera'],
  ),
  TradeTerm(
    'Cordón superior / inferior',
    'Elementos estructurales',
    'Barras longitudinales de una cercha: el superior suele trabajar a compresión y el inferior a tracción.',
  ),
  TradeTerm(
    'Diagonal y montante',
    'Elementos estructurales',
    'Barras interiores de una celosía (inclinadas y verticales).',
  ),
  TradeTerm(
    'Jabalcón',
    'Elementos estructurales',
    'Pieza inclinada que une pilar y viga para acortar la luz o rigidizar el nudo.',
    ['tornapunta'],
  ),
  TradeTerm('Tirante', 'Elementos estructurales', 'Barra que trabaja solo a tracción.', ['tensor']),
  TradeTerm(
    'Cruz de San Andrés',
    'Elementos estructurales',
    'Arriostramiento en X con tirantes o angulares que estabiliza frente a viento y pandeo.',
    ['arriostramiento', 'contraviento', 'cruceta'],
  ),
  TradeTerm(
    'Pilarillo de hastial',
    'Elementos estructurales',
    'Pilar intermedio de la fachada frontal de una nave que recoge el viento.',
  ),
  TradeTerm('Viga carrilera', 'Elementos estructurales', 'Viga por la que rueda un polipasto o puente grúa.', [
    'monorraíl',
  ]),
  TradeTerm('Vigueta', 'Elementos estructurales', 'Viga secundaria de un forjado o pasarela.'),
  TradeTerm('Zuncho', 'Elementos estructurales', 'Viga de atado perimetral.'),
  TradeTerm('Ménsula', 'Elementos estructurales', 'Voladizo empotrado en un extremo.', ['voladizo']),
  TradeTerm('Puntal', 'Elementos estructurales', 'Elemento corto a compresión.'),

  // Uniones y soldadura
  TradeTerm(
    'Placa de anclaje',
    'Uniones y soldadura',
    'Chapa soldada a la base del pilar que se fija a la zapata con pernos.',
    ['placa base'],
  ),
  TradeTerm('Cartela', 'Uniones y soldadura', 'Chapa triangular que refuerza un nudo o una placa.', ['escuadra']),
  TradeTerm(
    'Rigidizador',
    'Uniones y soldadura',
    'Chapa soldada al alma de un perfil para evitar abolladura o transmitir cargas puntuales.',
    ['nervio'],
  ),
  TradeTerm('Casquillo', 'Uniones y soldadura', 'Trozo de angular o chapa que une dos piezas atornilladas.'),
  TradeTerm('Cubrejuntas', 'Uniones y soldadura', 'Chapa que da continuidad a un empalme de perfiles.'),
  TradeTerm('Orejeta', 'Uniones y soldadura', 'Pequeña chapa soldada para atornillar tirantes o arriostramientos.'),
  TradeTerm(
    'Soldadura en ángulo',
    'Uniones y soldadura',
    'Cordón triangular entre dos chapas en T o en solape. Se define por la garganta «a».',
    ['cordón'],
  ),
  TradeTerm(
    'Soldadura a tope',
    'Uniones y soldadura',
    'Une chapas en prolongación, con preparación de bordes (bisel en V, X…).',
  ),
  TradeTerm('Garganta (a)', 'Uniones y soldadura', 'Espesor útil del cordón en ángulo (≈ 0,7 × lado).'),
  TradeTerm('Punteado', 'Uniones y soldadura', 'Puntos de soldadura provisionales para presentar piezas.', ['puntear']),
  TradeTerm(
    'MIG / MAG, electrodo, TIG',
    'Uniones y soldadura',
    'Procesos de soldadura: hilo con gas (135), electrodo revestido (111) y TIG (141).',
  ),
  TradeTerm(
    'Tornillo 8.8 / 10.9',
    'Uniones y soldadura',
    'Tornillos de alta resistencia. Los 10.9 pretensados se usan en uniones resistentes al deslizamiento.',
  ),
  TradeTerm(
    'Unión rígida / articulada',
    'Uniones y soldadura',
    'Rígida: transmite momento (pórticos). Articulada: solo cortante y axil (vigas simplemente apoyadas).',
  ),
  TradeTerm(
    'EXC2',
    'Uniones y soldadura',
    'Clase de ejecución habitual según EN 1090-2 para estructuras de edificación.',
  ),

  // Cerrajería y herrajes
  TradeTerm('Hoja', 'Cerrajería y herrajes', 'Parte móvil de una puerta o cancela.'),
  TradeTerm('Bastidor', 'Cerrajería y herrajes', 'Marco perimetral de tubo que forma la hoja.', ['cerco', 'marco']),
  TradeTerm('Barrote', 'Cerrajería y herrajes', 'Elemento vertical de relleno de rejas, cancelas y barandillas.'),
  TradeTerm('Pernio / bisagra', 'Cerrajería y herrajes', 'Herraje de giro de una hoja abatible.', ['gozne']),
  TradeTerm(
    'Corredera autoportante',
    'Cerrajería y herrajes',
    'Puerta corredera que vuela sobre un carro de rodillos, sin guía en el suelo.',
  ),
  TradeTerm('Guía y rueda', 'Cerrajería y herrajes', 'Carril en el suelo y ruedas de una puerta corredera.'),
  TradeTerm(
    'Cerradero / pasador',
    'Cerrajería y herrajes',
    'Pieza que recibe el pestillo, y cerrojo de fijación de la hoja.',
    ['cerrojo'],
  ),
  TradeTerm('Tope', 'Cerrajería y herrajes', 'Pieza que limita el recorrido de la hoja.'),
  TradeTerm('Pilar de cuelgue', 'Cerrajería y herrajes', 'Poste del que cuelga la hoja abatible.'),
  TradeTerm(
    'Malla electrosoldada / simple torsión',
    'Cerrajería y herrajes',
    'Rellenos de valla: paneles rígidos soldados o malla de alambre trenzado.',
  ),

  // Cubiertas, suelos y cerramientos
  TradeTerm(
    'Chapa grecada',
    'Cubiertas, suelos y cerramientos',
    'Chapa de acero perfilada en grecas para cubiertas y fachadas.',
    ['chapa trapezoidal', 'chapa perfilada'],
  ),
  TradeTerm(
    'Panel sándwich',
    'Cubiertas, suelos y cerramientos',
    'Dos chapas con núcleo aislante (PUR, PIR o lana de roca).',
    ['panel aislante'],
  ),
  TradeTerm('Policarbonato', 'Cubiertas, suelos y cerramientos', 'Placa translúcida para lucernarios y pérgolas.'),
  TradeTerm(
    'Tramex',
    'Cubiertas, suelos y cerramientos',
    'Rejilla electrosoldada (pletina + varilla) para suelos y peldaños.',
    ['trames', 'emparrillado'],
  ),
  TradeTerm('Chapa lagrimada', 'Cubiertas, suelos y cerramientos', 'Chapa antideslizante con relieve en lágrima.', [
    'chapa estriada',
    'chapa damero',
  ]),
  TradeTerm(
    'Chapa colaborante',
    'Cubiertas, suelos y cerramientos',
    'Chapa grecada que hace de encofrado y armadura de una losa de hormigón.',
  ),
  TradeTerm('Cumbrera', 'Cubiertas, suelos y cerramientos', 'Línea más alta de una cubierta a dos aguas.'),
  TradeTerm(
    'Alero',
    'Cubiertas, suelos y cerramientos',
    'Borde inferior de la cubierta; en naves, la altura al alero es la de los pilares.',
  ),
  TradeTerm('Hastial', 'Cubiertas, suelos y cerramientos', 'Fachada frontal de una nave a dos aguas.', ['piñón']),
  TradeTerm('Canalón / bajante', 'Cubiertas, suelos y cerramientos', 'Recogida y bajada de aguas pluviales.'),
  TradeTerm('Faldón', 'Cubiertas, suelos y cerramientos', 'Cada uno de los planos inclinados de una cubierta.', [
    'agua',
  ]),

  // Escaleras y barandillas
  TradeTerm('Zanca', 'Escaleras y barandillas', 'Viga inclinada que soporta los peldaños.'),
  TradeTerm('Huella', 'Escaleras y barandillas', 'Profundidad del peldaño (CTE: ≥ 280 mm).'),
  TradeTerm(
    'Contrahuella',
    'Escaleras y barandillas',
    'Altura de cada escalón (CTE: 130–185 mm). Se cumple 540 ≤ 2C + H ≤ 700 mm.',
    ['tabica'],
  ),
  TradeTerm(
    'Tramo',
    'Escaleras y barandillas',
    'Serie de peldaños seguidos; como máximo 3,20 m de altura en uso general.',
  ),
  TradeTerm('Meseta', 'Escaleras y barandillas', 'Descanso entre tramos.', ['descansillo', 'rellano']),
  TradeTerm('Ojo de escalera', 'Escaleras y barandillas', 'Hueco central entre tramos.'),
  TradeTerm('Pasamanos', 'Escaleras y barandillas', 'Elemento superior donde se apoya la mano (0,90–1,10 m).'),
  TradeTerm(
    'Rodapié',
    'Escaleras y barandillas',
    'Pletina o chapa inferior de la barandilla que evita la caída de objetos.',
    ['zócalo'],
  ),
  TradeTerm(
    'Barandilla no escalable',
    'Escaleras y barandillas',
    'Sin puntos de apoyo entre 0,20 y 0,70 m y huecos < 10 cm (CTE DB-SUA 1).',
  ),
  TradeTerm('Escala de gato', 'Escaleras y barandillas', 'Escalera vertical fija con aros (EN ISO 14122-4).'),

  // Geometría y cálculo
  TradeTerm('Luz', 'Geometría y cálculo', 'Distancia libre entre apoyos de una viga o cercha.', ['vano', 'claro']),
  TradeTerm('Crujía / intereje', 'Geometría y cálculo', 'Separación entre pórticos o líneas de pilares.', [
    'separación entre ejes',
    'modulación',
  ]),
  TradeTerm('Canto', 'Geometría y cálculo', 'Altura de la sección de una viga.'),
  TradeTerm('Flecha', 'Geometría y cálculo', 'Deformación vertical de una viga (límites L/300, L/350…).'),
  TradeTerm('Pandeo', 'Geometría y cálculo', 'Inestabilidad de una pieza comprimida (χ según EC3).'),
  TradeTerm('Pandeo lateral', 'Geometría y cálculo', 'Vuelco de una viga flectada no arriostrada.', ['vuelco lateral']),
  TradeTerm(
    'Aprovechamiento (η)',
    'Geometría y cálculo',
    'Esfuerzo de cálculo dividido por la resistencia; debe ser ≤ 1.',
  ),
  TradeTerm('Sobrecarga de uso', 'Geometría y cálculo', 'Carga variable por uso (kN/m²), CTE DB-SE-AE tabla 3.1.'),
  TradeTerm('Carga permanente', 'Geometría y cálculo', 'Peso propio y elementos fijos.'),
  TradeTerm(
    'ELU / ELS',
    'Geometría y cálculo',
    'Estados límite último (resistencia) y de servicio (flechas, vibraciones).',
  ),
  TradeTerm('Despiece', 'Geometría y cálculo', 'Lista de piezas con marca, perfil, longitud, cantidad y peso.'),
  TradeTerm('Marca', 'Geometría y cálculo', 'Código que identifica cada pieza en planos y taller.'),

  // Cimentación y anclajes
  TradeTerm('Zapata', 'Cimentación y anclajes', 'Cimiento de hormigón bajo el pilar.'),
  TradeTerm('Dado', 'Cimentación y anclajes', 'Prisma de hormigón sobre el que apoya un poste o pilar ligero.'),
  TradeTerm('Perno de anclaje', 'Cimentación y anclajes', 'Barra roscada embebida en el hormigón que fija la placa.', [
    'espárrago',
  ]),
  TradeTerm('Anclaje químico', 'Cimentación y anclajes', 'Varilla roscada pegada con resina en un taladro.', [
    'taco químico',
  ]),
  TradeTerm('Anclaje mecánico', 'Cimentación y anclajes', 'Taco expansivo de acero.', ['taco de expansión']),
  TradeTerm('Mortero de nivelación', 'Cimentación y anclajes', 'Mortero sin retracción bajo la placa de anclaje.', [
    'grout',
  ]),

  // Acabados y protección
  TradeTerm(
    'Galvanizado en caliente',
    'Acabados y protección',
    'Inmersión en zinc fundido (EN ISO 1461). Muy durable en exterior.',
    ['galva'],
  ),
  TradeTerm('Imprimación', 'Acabados y protección', 'Primera capa anticorrosiva antes del esmalte.', [
    'minio',
    'antioxidante',
  ]),
  TradeTerm('Lacado', 'Acabados y protección', 'Pintura en polvo polimerizada al horno.', ['termolacado', 'epoxi']),
  TradeTerm('Granallado', 'Acabados y protección', 'Limpieza por proyección de granalla (grado Sa 2½).', ['chorreado']),
  TradeTerm(
    'Ignifugado',
    'Acabados y protección',
    'Pintura intumescente o mortero para resistencia al fuego (R30, R60…).',
  ),
];
