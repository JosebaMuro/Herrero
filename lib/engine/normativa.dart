/// Biblioteca de normativa de soldadura, estructura metálica, herrería y
/// calderería, y lectura de los requisitos de fabricación que trae la
/// descripción («soldadura TIG», «calidad B», «EXC3», «radiografiado»,
/// «junto al mar»…).
///
/// Los textos son resúmenes propios orientativos con la referencia de cada
/// norma (UNE, EN, ISO, CTE, reales decretos); no reproducen el texto de las
/// normas, que deben consultarse en su edición vigente (AENOR, BOE).
library;

import 'model.dart';
import 'profiles.dart';

class Norm {
  final String code;
  final String title;
  final String area;
  final String summary;
  final List<String> points;

  /// Palabras (texto normalizado, sin tildes) que hacen pertinente la norma.
  final String? when;
  const Norm(this.code, this.area, this.title, this.summary, {this.points = const [], this.when});
}

const normAreas = [
  'Cálculo y reglamentación',
  'Ejecución y marcado CE',
  'Procesos y símbolos de soldadura',
  'Cualificación y calidad del soldeo',
  'Inspección y ensayos',
  'Materiales y consumibles',
  'Protección y acabados',
  'Herrería y cerrajería',
  'Calderería, depósitos y tubería',
];

const normLibrary = <Norm>[
  // --- Cálculo y reglamentación ---------------------------------------------
  Norm('CTE DB-SE-A', 'Cálculo y reglamentación', 'Código Técnico de la Edificación. Seguridad estructural: acero',
      'Reglamento español para estructuras de acero en edificación: bases de cálculo, estados límite, uniones '
          'soldadas y atornilladas, ejecución en taller y montaje, tolerancias y control de calidad.',
      points: [
        'Uniones soldadas: garganta, longitud eficaz y resistencia de cordones en ángulo y a tope.',
        'Ejecución: preparación de bordes, punteado, precalentamiento cuando proceda y secuencia de soldeo.',
        'Control de calidad de materiales, fabricación y montaje con su documentación.',
      ]),
  Norm('UNE-EN 1993-1-8 (Eurocódigo 3)', 'Cálculo y reglamentación', 'Proyecto de uniones',
      'Cálculo de uniones soldadas y atornilladas. Para cordones en ángulo: garganta eficaz a ≥ 3 mm, longitud '
          'eficaz ≥ máx(30 mm; 6·a) y resistencia por el método direccional o el simplificado con el factor βw del '
          'acero (0,80 S235; 0,85 S275; 0,90 S355).',
      points: [
        'Cordón en ángulo de resistencia completa: a ≈ 0,46·t (S235), 0,48·t (S275), 0,55·t (S355) con dos cordones.',
        'Los cordones discontinuos no se usan en ambientes corrosivos (se oxida el hueco entre tramos).',
        'Uniones rígidas, semirrígidas y articuladas según su rigidez al giro.',
      ]),
  Norm('UNE-EN 1993-1-1 / 1-4 / 1-6', 'Cálculo y reglamentación', 'Eurocódigo 3: reglas generales, inoxidable y láminas',
      'Comprobación de barras de acero (1-1), adaptación a aceros inoxidables (1-4) y resistencia de láminas y '
          'virolas cilíndricas o cónicas (1-6), base de silos y depósitos.',
      when: r'inox|deposito|silo|tolva|virola|chimenea|tanque'),
  Norm('UNE-EN 1999-1-1 (Eurocódigo 9)', 'Cálculo y reglamentación', 'Estructuras de aluminio',
      'Cálculo de aluminio: la zona afectada por el calor de la soldadura pierde hasta la mitad de la resistencia '
          'en aleaciones bonificadas (6061/6082 T6), y hay que contarlo.',
      when: r'aluminio'),
  Norm('Código Estructural (RD 470/2021)', 'Cálculo y reglamentación', 'Reglamento de estructuras de hormigón, acero y mixtas',
      'Sustituye a la instrucción EAE. Obligatorio en obra civil; en edificación convive con el CTE. Sigue los '
          'Eurocódigos e incorpora la clase de ejecución de EN 1090-2.',
      when: r'puente|obra civil|carretera|ferrocarril'),

  // --- Ejecución y marcado CE -------------------------------------------------
  Norm('UNE-EN 1090-1', 'Ejecución y marcado CE', 'Componentes estructurales de acero y aluminio: marcado CE',
      'El taller que vende componentes estructurales necesita control de producción en fábrica (CPF) certificado por '
          'un organismo notificado y emite la declaración de prestaciones (DoP) y el marcado CE de cada partida.',
      points: [
        'Afecta a vigas, pilares, cerchas, escaleras y barandillas con función estructural.',
        'El certificado de CPF indica la clase de ejecución máxima que puede fabricar el taller.',
      ]),
  Norm('UNE-EN 1090-2', 'Ejecución y marcado CE', 'Requisitos técnicos para la ejecución de estructuras de acero',
      'Fija todo lo que se pide en taller y obra según la clase de ejecución EXC1 a EXC4: trazabilidad, '
          'cualificación del soldeo, nivel de calidad de los cordones, ensayos, tolerancias y montaje.',
      points: [
        'EXC1: estructuras agrícolas y de poca consecuencia. Calidad D, EN ISO 3834-4.',
        'EXC2: lo habitual en edificación. Calidad C, EN ISO 3834-3, coordinador de soldeo con conocimientos básicos o específicos.',
        'EXC3: grandes luces, puentes, cargas de fatiga. Calidad B, EN ISO 3834-2, coordinador específico o completo.',
        'EXC4: consecuencias muy graves. Calidad B con requisitos adicionales.',
        'Inspección visual del 100 % de los cordones y END adicionales en un porcentaje que depende de la clase y del tipo de cordón.',
      ]),
  Norm('UNE-EN 1090-3', 'Ejecución y marcado CE', 'Ejecución de estructuras de aluminio',
      'Equivalente a EN 1090-2 para aluminio: soldeo MIG/TIG, cualificación según EN ISO 9606-2 y 15614-2.',
      when: r'aluminio'),
  Norm('UNE-EN ISO 13920', 'Ejecución y marcado CE', 'Tolerancias generales de construcciones soldadas',
      'Tolerancias de longitudes y ángulos (clases A a D) y de rectitud, planitud y paralelismo (clases E a H) '
          'cuando el plano no indica otra cosa. En calderería y bastidores se suele pedir B/F.'),

  // --- Procesos y símbolos ----------------------------------------------------
  Norm('UNE-EN ISO 4063', 'Procesos y símbolos de soldadura', 'Procesos de soldeo y números de referencia',
      'Numeración de los procesos que se pone en los planos y en las WPS.',
      points: [
        '111 electrodo revestido · 114 hilo tubular sin gas · 121 arco sumergido',
        '131 MIG (gas inerte: aluminio, inox) · 135 MAG hilo macizo · 136 MAG hilo tubular con fundente · 138 hilo tubular metálico',
        '141 TIG · 15 plasma · 311 oxiacetilénica · 21 por puntos de resistencia · 52 láser · 783 espárragos por arco',
      ]),
  Norm('UNE-EN ISO 2553', 'Procesos y símbolos de soldadura', 'Representación simbólica de soldaduras en planos',
      'Flecha que señala la unión, línea de referencia (continua y discontinua en el sistema A europeo) y símbolo '
          'del cordón: triángulo en ángulo, V, X, medio V (bisel), Y, U, J o I (bordes rectos).',
      points: [
        'Símbolo en la línea continua: cordón en el lado de la flecha; en la discontinua: en el otro lado.',
        'Cota delante del símbolo: «a5» garganta o «z7» lado. Detrás: longitud, o n × l (e) en cordones discontinuos.',
        'Banderita: soldadura en obra. Círculo en el codo: todo alrededor. Cola: proceso (135), WPS o nivel de calidad.',
      ]),
  Norm('UNE-EN ISO 6947', 'Procesos y símbolos de soldadura', 'Posiciones de soldeo',
      'PA plana · PB horizontal en ángulo · PC cornisa · PD bajo techo en ángulo · PE bajo techo · PF vertical '
          'ascendente · PG vertical descendente · H-L045 y J-L045 tubo inclinado.'),
  Norm('UNE-EN ISO 9692-1', 'Procesos y símbolos de soldadura', 'Preparación de bordes para soldar acero',
      'Recomendaciones de bisel según espesor y proceso: bordes rectos (I) en chapa fina, V de 40–60° en espesores '
          'medios, X o doble bisel en chapa gruesa para soldar por las dos caras, con talón y separación de raíz.'),
  Norm('UNE-EN ISO 17659 / ISO 4063', 'Procesos y símbolos de soldadura', 'Terminología multilingüe de uniones soldadas',
      'Vocabulario normalizado de tipos de unión y cordones (a tope, en T, en solape, en ángulo, de esquina, de borde).'),

  // --- Cualificación y calidad ------------------------------------------------
  Norm('UNE-EN ISO 3834', 'Cualificación y calidad del soldeo', 'Requisitos de calidad para el soldeo por fusión',
      'Sistema de calidad del taller de soldadura: parte 2 completos, parte 3 normales, parte 4 elementales. '
          'EN 1090-2 lo enlaza con la clase de ejecución.'),
  Norm('UNE-EN ISO 14731', 'Cualificación y calidad del soldeo', 'Coordinación del soldeo',
      'Tareas y responsabilidades del coordinador de soldeo (revisión de requisitos, WPS, soldadores, consumibles, '
          'inspección). El nivel de conocimientos exigido sube con la clase de ejecución.'),
  Norm('UNE-EN ISO 9606-1', 'Cualificación y calidad del soldeo', 'Cualificación de soldadores: aceros',
      'Homologación del soldador por proceso, producto (chapa o tubo), tipo de unión (a tope o en ángulo), grupo de '
          'material, espesor, diámetro y posición. Su validez se confirma cada seis meses y se revalida periódicamente.',
      points: ['Aluminio: EN ISO 9606-2. Operadores de soldeo mecanizado o robotizado: EN ISO 14732.']),
  Norm('UNE-EN ISO 15609-1 / 15614-1', 'Cualificación y calidad del soldeo', 'Especificación (WPS) y cualificación (WPQR) del procedimiento',
      'La WPS fija proceso, consumible, gas, parámetros, posición, precalentamiento y secuencia; la WPQR es el ensayo '
          'que la respalda. En EXC2 se admiten también procedimientos normalizados (EN ISO 15612) o probados (EN ISO 15613).'),
  Norm('UNE-EN ISO 5817', 'Cualificación y calidad del soldeo', 'Niveles de calidad de las imperfecciones en soldaduras de acero',
      'Tres niveles: B exigente, C intermedio y D moderado. Fija los límites de mordeduras, poros, falta de penetración, '
          'sobreespesor, desalineación, garganta insuficiente, salpicaduras y demás imperfecciones.',
      points: ['Aluminio: EN ISO 10042. Calidad habitual en edificación: C (EXC2).']),

  // --- Inspección y ensayos ---------------------------------------------------
  Norm('UNE-EN ISO 17637', 'Inspección y ensayos', 'Inspección visual de uniones soldadas',
      'Primer control, sobre el 100 % de los cordones: geometría, garganta, mordeduras, poros, grietas y salpicaduras.'),
  Norm('UNE-EN ISO 3452-1', 'Inspección y ensayos', 'Líquidos penetrantes (PT)',
      'Detecta grietas y poros abiertos a la superficie en cualquier metal, incluido inox y aluminio. Aceptación: EN ISO 23277.',
      when: r'penetrante|tinta'),
  Norm('UNE-EN ISO 17638', 'Inspección y ensayos', 'Partículas magnéticas (MT)',
      'Grietas superficiales y subsuperficiales en aceros ferríticos; muy usado en cordones en ángulo. Aceptación: EN ISO 23278.',
      when: r'magnet|particulas'),
  Norm('UNE-EN ISO 17640', 'Inspección y ensayos', 'Ultrasonidos (UT)',
      'Defectos internos en uniones a tope de penetración completa, normalmente desde 8 mm de espesor. Aceptación: EN ISO 11666.',
      when: r'ultrason|penetracion completa'),
  Norm('UNE-EN ISO 17636', 'Inspección y ensayos', 'Radiografía (RT)',
      'Poros, inclusiones y faltas de fusión internas en uniones a tope; habitual en calderería y tubería. Aceptación: EN ISO 10675-1.',
      when: r'radiograf|rayos x|gammagraf'),

  // --- Materiales y consumibles -----------------------------------------------
  Norm('UNE-EN 10025-2 a -6', 'Materiales y consumibles', 'Aceros estructurales laminados en caliente',
      'S235, S275 y S355 en grados JR, J0 y J2 (tenacidad de 27 J a +20, 0 y −20 °C). La parte 5 son aceros patinables '
          '(corten, «W») y las partes 3, 4 y 6 los normalizados, termomecánicos y templados.'),
  Norm('UNE-EN 10210 / 10219', 'Materiales y consumibles', 'Perfiles huecos estructurales',
      'Tubos redondos, cuadrados y rectangulares acabados en caliente (10210) o conformados en frío (10219).',
      when: r'tubo|perfil hueco|rectangular|cuadrado'),
  Norm('UNE-EN 10088', 'Materiales y consumibles', 'Aceros inoxidables',
      '1.4301 (AISI 304), 1.4307 (304L), 1.4404 (316L). Las versiones L (bajo carbono) evitan la corrosión '
          'intergranular junto a la soldadura.',
      when: r'inox'),
  Norm('UNE-EN 10204', 'Materiales y consumibles', 'Documentos de inspección de productos metálicos',
      'Certificados 2.1, 2.2, 3.1 y 3.2. En estructura se pide el 3.1 del fabricante del acero para la trazabilidad de las coladas.'),
  Norm('UNE-EN 10164', 'Materiales y consumibles', 'Aceros con resistencia mejorada en el espesor (calidad Z)',
      'Z15, Z25 y Z35 frente al desgarro laminar en chapas gruesas que reciben soldaduras perpendiculares de gran garganta.',
      when: r'desgarro|chapa gruesa|calidad z'),
  Norm('UNE-EN ISO 14341 / 2560 / 636 / 14343 / 18273', 'Materiales y consumibles', 'Consumibles de soldadura',
      'Hilo macizo MAG para acero (14341, p. ej. G 42 4 M21 3Si1 ≈ ER70S-6), electrodo revestido (2560, p. ej. '
          'E 42 4 B ≈ E7018 básico), varilla TIG (636), hilo e inox (14343, 308LSi / 316LSi) y aluminio (18273, ER5356 / ER4043).'),
  Norm('UNE-EN ISO 14175', 'Materiales y consumibles', 'Gases de protección',
      'I1 argón puro (TIG y MIG), M21 argón + 15–25 % CO₂ (MAG de acero), C1 CO₂ puro, M12/M13 mezclas para inox.'),

  // --- Protección y acabados --------------------------------------------------
  Norm('UNE-EN ISO 1461', 'Protección y acabados', 'Galvanizado en caliente por inmersión',
      'Espesor medio mínimo del recubrimiento según el espesor del acero: 85 µm por encima de 6 mm, 70 µm de 3 a 6 mm, '
          '55 µm de 1,5 a 3 mm y 45 µm por debajo. Las zonas dañadas o soldadas después se reparan con zinc proyectado o pintura rica en zinc.',
      when: r'galvaniz'),
  Norm('UNE-EN ISO 14713-2', 'Protección y acabados', 'Diseño de piezas para galvanizar',
      'Todo perfil cerrado necesita agujeros de venteo y drenaje en los extremos (el aire atrapado puede reventar la pieza en '
          'el baño) y conviene evitar solapes estancos de chapa. Soldar antes de galvanizar y quitar la escoria.',
      when: r'galvaniz'),
  Norm('UNE-EN ISO 12944', 'Protección y acabados', 'Protección con sistemas de pintura',
      'Elige el sistema según la corrosividad del ambiente (C1 a C5 y CX) y la durabilidad buscada: baja hasta 7 años, '
          'media 7–15, alta 15–25 y muy alta más de 25. La parte 3 da reglas de diseño (cordones continuos, sin rincones que acumulen agua).'),
  Norm('UNE-EN ISO 9223', 'Protección y acabados', 'Corrosividad atmosférica',
      'C1 interior seco · C2 rural · C3 urbano o costa poco salina · C4 industrial o costero · C5 industrial agresivo o '
          'marino · CX extremo (zona de salpicadura).'),
  Norm('UNE-EN ISO 8501-1', 'Protección y acabados', 'Grados de preparación de superficies',
      'Chorreado Sa 1, Sa 2, Sa 2½ (el habitual antes de pintar) y Sa 3; limpieza manual o mecánica St 2 y St 3.',
      when: r'granall|chorre|pint|lacad|imprim'),

  // --- Herrería y cerrajería --------------------------------------------------
  Norm('CTE DB-SUA 1', 'Herrería y cerrajería', 'Seguridad frente al riesgo de caídas',
      'Barandilla obligatoria con desnivel de más de 55 cm. Altura 0,90 m si la caída es ≤ 6 m y 1,10 m si es mayor; '
          'no escalable entre 30 y 50 cm de altura y sin huecos por los que pase una esfera de 10 cm.',
      points: [
        'Escaleras de uso general: huella ≥ 28 cm, contrahuella 13–18,5 cm y 54 ≤ 2C + H ≤ 70 cm.',
        'Pasamanos a 0,90–1,10 m, separado ≥ 4 cm del paramento y firme, sin interrupciones.',
      ],
      when: r'barandilla|pasamanos|escalera|antepecho|balcon|guardacuerpos|mirador|terraza|pasarela|entreplanta|altillo'),
  Norm('CTE DB-SE-AE §3.2', 'Herrería y cerrajería', 'Acciones sobre barandillas y elementos divisorios',
      'Empuje horizontal en el borde superior: 0,8 kN/m en general, 1,6 kN/m en zonas de público (C3, C4, E, F) y '
          '3,0 kN/m en zonas de aglomeración (C5).',
      when: r'barandilla|antepecho|guardacuerpos|pasamanos'),
  Norm('UNE-EN 13241', 'Herrería y cerrajería', 'Puertas industriales, comerciales, de garaje y portones',
      'Norma de producto con marcado CE para puertas de paso de vehículos y personas. Con UNE-EN 12604 (aspectos mecánicos) '
          'y, si son motorizadas, UNE-EN 12453 (fuerzas de cierre, bandas de seguridad y fotocélulas).',
      when: r'cancela|porton|puerta|corredera|abatible|motor|automatic'),
  Norm('UNE-EN ISO 14122-3 / -4', 'Herrería y cerrajería', 'Medios de acceso permanentes a máquinas e instalaciones',
      'Barandilla industrial de 1,10 m con listón intermedio y rodapié de 10 cm; escalas fijas con peldaños cada 225–300 mm, '
          'ancho libre 400–600 mm y jaula de protección cuando la altura de caída pasa de 3 m.',
      when: r'escala de gato|marinera|industrial|maquina|nave|plataforma|pasarela|tramex'),
  Norm('RD 486/1997', 'Herrería y cerrajería', 'Lugares de trabajo',
      'Barandillas de 90 cm mínimo, con protección intermedia y rodapié, en aberturas y desniveles de más de 2 m. Las escalas '
          'fijas de más de 4 m llevan protección circundante al menos desde los 3 m.',
      when: r'escala de gato|marinera|nave|taller|almacen|industrial|plataforma|pasarela|entreplanta'),

  // --- Calderería -----------------------------------------------------------------
  Norm('Directiva 2014/68/UE · RD 709/2015 · RD 809/2021', 'Calderería, depósitos y tubería', 'Equipos a presión',
      'Todo recipiente, caldera o tubería con presión máxima admisible de más de 0,5 bar es un equipo a presión: diseño '
          'por ingeniería, categoría según presión × volumen y fluido, marcado CE, prueba hidráulica e inscripción según el '
          'Reglamento de equipos a presión.',
      when: r'presion|caldera|calderin|autoclave|compresor|vapor|calderer'),
  Norm('UNE-EN 13445', 'Calderería, depósitos y tubería', 'Recipientes a presión no sometidos a llama',
      'Diseño, materiales, fabricación e inspección de recipientes a presión soldados: virolas, fondos, tubuladuras, bridas '
          'y refuerzos de aberturas. Alternativa habitual: código ASME VIII div. 1.',
      when: r'presion|recipiente|calderin|autoclave|calderer|virola|fondo toriesferico|fondo klopper'),
  Norm('UNE-EN 14015', 'Calderería, depósitos y tubería', 'Tanques verticales de fondo plano soldados in situ',
      'Tanques cilíndricos atmosféricos para líquidos a temperatura ambiente o superior: espesores de virolas por anillos, '
          'fondo, techo, prueba de llenado y estanqueidad. Equivalente americano: API 650.',
      when: r'deposito|tanque|aljibe|cisterna|calderer'),
  Norm('UNE-EN 1993-4-1 / 4-2', 'Calderería, depósitos y tubería', 'Eurocódigo 3: silos y depósitos',
      'Cálculo de silos, tolvas y depósitos de chapa: presiones del material ensilado (EN 1991-4), pandeo de virolas y apoyos.',
      when: r'silo|tolva|deposito|tanque'),
  Norm('UNE-EN 10028', 'Calderería, depósitos y tubería', 'Chapas de acero para aparatos a presión',
      'Aceros con propiedades garantizadas en caliente, como P265GH y P355GH, para virolas y fondos.',
      when: r'presion|caldera|calderin|calderer|virola'),
  Norm('UNE-EN 1092-1', 'Calderería, depósitos y tubería', 'Bridas de acero',
      'Bridas por presión nominal (PN 6, 10, 16, 25, 40…) y tipo: 01 plana para soldar, 05 ciega, 11 con cuello para soldar.',
      when: r'brida|tubuladura|tuberia|deposito|tanque|calderer'),
  Norm('UNE-EN 13480', 'Calderería, depósitos y tubería', 'Tuberías industriales metálicas',
      'Diseño, fabricación, soldeo e inspección de tuberías de proceso; tubos de acero sin soldadura según EN 10216 y soldados según EN 10217.',
      when: r'tuberia|colector|calderer'),
  Norm('DIN 28011 / 28013', 'Calderería, depósitos y tubería', 'Fondos toriesféricos para depósitos',
      'Fondo Klöpper: radio de bombeo R = D y radio de rebordeo r = 0,1·D. Fondo Korbbogen (más profundo y resistente): '
          'R = 0,8·D y r = 0,154·D. Otras opciones: semielíptico 2:1, semiesférico y plano rebordeado.',
      when: r'fondo|deposito|tanque|calderer|virola|klopper|korbbogen'),
];

/// Normas pertinentes para un texto (normalizado, sin tildes): las de alcance
/// general y las que se activan con las palabras de la petición.
List<Norm> normsFor(String t, {MaterialKind? material, String finish = ''}) {
  final ctx = '$t ${material == MaterialKind.stainless ? 'inox' : ''} '
      '${material == MaterialKind.aluminium ? 'aluminio' : ''} ${finish.toLowerCase().replaceAll('á', 'a')}';
  return [
    for (final n in normLibrary)
      if (n.when == null || RegExp(n.when!).hasMatch(ctx)) n,
  ];
}

// ---------------------------------------------------------------------------
// Requisitos de fabricación leídos de la descripción
// ---------------------------------------------------------------------------

class Fabrication {
  /// Proceso pedido (número ISO 4063 y nombre) o vacío.
  final String process;
  final String quality; // 'B', 'C', 'D' o ''
  final int exc; // 1..4, 0 si no se indica
  final List<String> ndt; // ensayos pedidos: VT, PT, MT, UT, RT
  final bool siteWelding;
  final bool fullPenetration;
  final bool continuous; // cordón continuo / estanco
  final bool intermittent;
  final String corrosivity; // C1..C5, CX o ''
  final String corrosivityWhy;
  final bool pressure; // recipiente o equipo a presión
  final bool vessel; // depósito, tanque, silo, tolva (calderería)
  final bool motorized;
  final List<String> notes; // lo que se ha entendido, para el usuario
  const Fabrication({
    this.process = '',
    this.quality = '',
    this.exc = 0,
    this.ndt = const [],
    this.siteWelding = false,
    this.fullPenetration = false,
    this.continuous = false,
    this.intermittent = false,
    this.corrosivity = '',
    this.corrosivityWhy = '',
    this.pressure = false,
    this.vessel = false,
    this.motorized = false,
    this.notes = const [],
  });

  bool get isEmpty =>
      process.isEmpty && quality.isEmpty && exc == 0 && ndt.isEmpty && !siteWelding && !fullPenetration &&
      !continuous && !intermittent && corrosivity.isEmpty && !pressure && !vessel && !motorized;

  /// Clase de ejecución efectiva (EXC2 por defecto en edificación).
  int get execClass => exc > 0 ? exc : (quality == 'B' ? 3 : (quality == 'D' ? 1 : 2));

  /// Nivel de calidad efectivo (EN 1090-2: EXC1 → D, EXC2 → C, EXC3/4 → B).
  String get qualityLevel => quality.isNotEmpty ? quality : (execClass >= 3 ? 'B' : (execClass == 1 ? 'D' : 'C'));
}

const ndtNames = {
  'VT': 'inspección visual (EN ISO 17637)',
  'PT': 'líquidos penetrantes (EN ISO 3452-1)',
  'MT': 'partículas magnéticas (EN ISO 17638)',
  'UT': 'ultrasonidos (EN ISO 17640)',
  'RT': 'radiografía (EN ISO 17636)',
};

/// Lee de la petición (texto normalizado, sin tildes) lo que dice de soldadura,
/// calidad, ensayos, ambiente y tipo de equipo.
Fabrication readFabrication(String t) {
  final notes = <String>[];
  bool has(String re) => RegExp(re).hasMatch(t);

  var process = '';
  if (has(r'(?<![a-z])(?:tig|141)(?![a-z0-9])|soldadura (?:de |con )?argon|gtaw')) {
    process = '141 (TIG)';
  } else if (has(r'hilo tubular|flux ?cored|fcaw|(?<![0-9])13[68](?![0-9])|(?<![0-9])114(?![0-9])')) {
    process = '136 (MAG hilo tubular)';
  } else if (has(r'(?<![a-z])(?:mag|135)(?![a-z0-9])|semiautomatica|soldadura (?:de|con) hilo|hilo continuo|gmaw')) {
    process = '135 (MAG)';
  } else if (has(r'(?<![a-z])(?:mig|131)(?![a-z0-9])')) {
    process = '131/135 (MIG/MAG)';
  } else if (has(r'electrodos?(?! de grafito)|(?<![0-9])111(?![0-9])|arco manual|smaw|varilla revestida')) {
    process = '111 (electrodo revestido)';
  } else if (has(r'arco sumergido|(?<![0-9])121(?![0-9])|saw(?![a-z])')) {
    process = '121 (arco sumergido)';
  } else if (has(r'soldadura (?:por )?laser|(?<![a-z])laser')) {
    process = '52 (láser)';
  } else if (has(r'oxiacetil|autogena|soplete de soldar')) {
    process = '311 (oxiacetilénica)';
  } else if (has(r'soldadura por puntos|puntos de resistencia')) {
    process = '21 (por puntos de resistencia)';
  }
  if (process.isNotEmpty) notes.add('Proceso de soldeo pedido: $process (EN ISO 4063).');

  var quality = '';
  final q = RegExp(r'(?:nivel|calidad)(?: de calidad)?(?: de soldadura)? ([bcd])(?![a-z])').firstMatch(t);
  if (q != null) quality = q[1]!.toUpperCase();
  if (quality.isNotEmpty) notes.add('Nivel de calidad $quality (EN ISO 5817).');

  var exc = 0;
  final e = RegExp(r'exc ?-?([1-4])(?![0-9])|clase de ejecucion ([1-4])').firstMatch(t);
  if (e != null) exc = int.parse(e[1] ?? e[2]!);
  if (exc > 0) notes.add('Clase de ejecución EXC$exc (EN 1090-2).');

  final ndt = <String>[
    if (has(r'inspeccion visual|control visual')) 'VT',
    if (has(r'penetrantes|tintas')) 'PT',
    if (has(r'particulas magneticas|magnetoscop')) 'MT',
    if (has(r'ultrasonid')) 'UT',
    if (has(r'radiograf|rayos x|gammagraf')) 'RT',
  ];
  if (ndt.isNotEmpty) notes.add('Ensayos pedidos: ${ndt.map((k) => ndtNames[k]).join(', ')}.');

  final site = has(r'(?:soldad[ao]s?|soldadura|soldar) (?:en|a pie de) obra|(?:soldad[ao]s?|soldadura|soldar) in situ');
  final fullPen = has(r'penetracion (?:completa|total)|a tope con penetracion');
  final continuous = has(r'cordon(?:es)? continuos?|soldadura continua|soldadura corrida|cordon corrido|estanc[ao]');
  final intermittent = !continuous && has(r'cordon(?:es)? discontinuos?|soldadura discontinua|a tramos|intermitente|cosid[ao]');

  var corr = '';
  var why = '';
  final c = RegExp(r'(?:ambiente|corrosividad|categoria|clase|exposicion|entorno)(?: de corrosividad| corrosiva)? (c[1-5]|cx)(?![0-9a-z])')
      .firstMatch(t);
  if (c != null) {
    corr = c[1]!.toUpperCase();
    why = 'indicado en la petición';
  } else if (has(r'primera linea|salpicadura|offshore|en el mar|plataforma marina|puerto deportivo|muelle|pantalan')) {
    (corr, why) = ('C5', 'ambiente marino');
  } else if (has(r'(?<![a-z])(?:playa|costa|costera|costero|junto al mar|cerca del mar|frente al mar|salitre|maritim[ao]|marin[ao])(?![a-z])')) {
    (corr, why) = ('C4', 'zona costera');
  } else if (has(r'piscina|depuradora|quimic|purin|granja|establo|cuadra|fertilizante|abono')) {
    (corr, why) = ('C4', 'ambiente húmedo o agresivo');
  } else if (has(r'industrial|fabrica|poligono')) {
    (corr, why) = ('C3', 'ambiente industrial moderado');
  }
  if (corr.isNotEmpty) notes.add('Corrosividad $corr ($why, EN ISO 9223 / 12944).');

  final pressure = has(r'(?:a|de|con|bajo) presion|recipiente a presion|caldera|calderin|autoclave|(?<![a-z])\d+(?:\.\d+)? ?bar(?![a-z])');
  final vessel = pressure || has(r'(?<![a-z])(?:deposito|tanque|silo|tolva|aljibe|cisterna|virola|chimenea|conducto)s?(?![a-z])');
  final motorized = has(r'motoriz|automatic[ao]|con motor|mando a distancia');

  return Fabrication(
    process: process,
    quality: quality,
    exc: exc,
    ndt: ndt,
    siteWelding: site,
    fullPenetration: fullPen,
    continuous: continuous,
    intermittent: intermittent,
    corrosivity: corr,
    corrosivityWhy: why,
    pressure: pressure,
    vessel: vessel,
    motorized: motorized,
    notes: notes,
  );
}

/// Proceso y consumible adecuados al material para el proceso pedido.
String weldProcessFor(String process, SteelGrade g) {
  final kind = g.kind;
  if (process.isEmpty) return g.weld;
  if (process.startsWith('141')) {
    return switch (kind) {
      MaterialKind.stainless => '141 (TIG) varilla ${g.name.contains('316') ? '19 12 3 L Si (ER316LSi)' : '19 9 L Si (ER308LSi)'}, gas I1 argón; decapado y pasivado',
      MaterialKind.aluminium => '141 (TIG) corriente alterna, varilla AlMg5 (ER5356), gas I1 argón',
      MaterialKind.weathering => '141 (TIG) varilla patinable (ER80S-Ni1), gas I1 argón',
      _ => '141 (TIG) varilla W 42 5 W3Si1 (ER70S-6), gas I1 argón',
    };
  }
  if (process.startsWith('131') || process.startsWith('135')) {
    return switch (kind) {
      MaterialKind.stainless || MaterialKind.aluminium => g.weld,
      MaterialKind.weathering => '135 (MAG) hilo patinable G 46 4 M21 Z (ER80S-Ni1), gas M21',
      _ => '135 (MAG) hilo G 42 4 M21 3Si1 (ER70S-6), gas M21 (Ar + 18 % CO₂)',
    };
  }
  if (process.startsWith('136')) {
    return kind == MaterialKind.carbon
        ? '136 (MAG hilo tubular) T 46 2 P M21 (E71T-1), gas M21; bueno en obra y en posición'
        : g.weld;
  }
  if (process.startsWith('111')) {
    return switch (kind) {
      MaterialKind.stainless => '111 (electrodo) E ${g.name.contains('316') ? '19 12 3 L R (E316L-16)' : '19 9 L R (E308L-16)'}; limpiar escoria y pasivar',
      MaterialKind.aluminium => g.weld,
      MaterialKind.weathering => '111 (electrodo) básico patinable E 46 5 Z B (E8018-W)',
      _ => '111 (electrodo revestido) E 42 4 B (E7018 básico), electrodos secos (estufa)',
    };
  }
  if (process.startsWith('121')) return '121 (arco sumergido) hilo S2Si + fundente; solo en taller y posición PA/PB';
  return '$process · ${g.weld}';
}

/// Texto de hipótesis de soldadura según la clase de ejecución y la calidad.
String weldingHypothesis(Fabrication f) {
  final exc = f.execClass;
  final iso3834 = exc >= 3 ? 'EN ISO 3834-2' : (exc == 2 ? 'EN ISO 3834-3' : 'EN ISO 3834-4');
  final coord = exc >= 3 ? 'coordinador de soldeo con conocimientos específicos o completos' : 'coordinador de soldeo';
  final ndt = f.ndt.where((k) => k != 'VT').map((k) => ndtNames[k]).join(', ');
  return 'Soldadura: ejecución EXC$exc (EN 1090-2), $iso3834, $coord (EN ISO 14731), soldadores cualificados '
      '(EN ISO 9606-1) y WPS cualificada (EN ISO 15614-1${exc <= 2 ? ' o 15612' : ''}). Calidad nivel ${f.qualityLevel} '
      '(EN ISO 5817). Inspección visual del 100 % (EN ISO 17637)'
      '${ndt.isNotEmpty ? ' y $ndt' : ' y END adicionales según EN 1090-2'}.';
}

/// Avisos y recomendaciones de oficio según lo pedido.
List<String> fabricationWarnings(Fabrication f, StructureSpec s) {
  final out = <String>[];
  final kind = s.grade.kind;
  final p = f.process;
  if (kind == MaterialKind.aluminium && (p.startsWith('111') || p.startsWith('135') || p.startsWith('136') || p.startsWith('121'))) {
    out.add('El aluminio no se suelda con ${p.split(' ').first}: se usa MIG (131) o TIG (141) con argón.');
  }
  if (p.startsWith('311')) {
    out.add('La soldadura oxiacetilénica (311) no se usa en uniones estructurales de acero: se recomienda MAG (135) o electrodo (111).');
  }
  if (p.startsWith('21')) {
    out.add('La soldadura por puntos de resistencia (21) es para chapa fina; en perfiles estructurales se usa MAG (135).');
  }
  if (p.startsWith('141') && kind == MaterialKind.carbon) {
    out.add('TIG en acero al carbono: buena calidad y aspecto pero lento; lo normal es MAG (135) y TIG solo en raíces o piezas vistas.');
  }
  if (f.siteWelding) {
    out.add('Soldadura en obra: proteger del viento (el MAG pierde el gas por encima de 2 m/s; en exterior mejor electrodo 111 o '
        'hilo tubular 136), precalentar con frío o humedad y reparar la protección anticorrosiva después.');
  }
  if (f.quality == 'D' && f.exc >= 2) {
    out.add('Calidad D (EN ISO 5817) no es suficiente para EXC${f.exc}: EN 1090-2 pide al menos nivel ${f.exc >= 3 ? 'B' : 'C'}.');
  }
  if (f.execClass >= 3) {
    out.add('EXC${f.execClass}: el taller necesita certificado EN 1090-1 para esa clase, EN ISO 3834-2 y coordinador de soldeo '
        'específico o completo; más ensayos no destructivos que en EXC2.');
  }
  if (f.intermittent) {
    out.add('Cordones discontinuos: solo en interior seco. En exterior o al galvanizar se recomiendan cordones continuos '
        '(EN ISO 12944-3) para que no entre agua ni ácido entre las piezas.');
  }
  if (f.ndt.contains('RT') || f.ndt.contains('UT')) {
    if (!f.fullPenetration) {
      out.add('Radiografía y ultrasonidos solo tienen sentido en uniones a tope de penetración completa: indicar qué uniones se ensayan.');
    }
  }
  if (f.ndt.contains('MT') && kind != MaterialKind.carbon && kind != MaterialKind.weathering) {
    out.add('Las partículas magnéticas no sirven en inox austenítico ni aluminio: usar líquidos penetrantes (EN ISO 3452-1).');
  }
  final galv = s.finish.contains('galvaniz');
  if (f.corrosivity.isNotEmpty) {
    final cIdx = f.corrosivity == 'CX' ? 6 : int.parse(f.corrosivity.substring(1));
    if (cIdx >= 4 && kind == MaterialKind.carbon && !galv) {
      out.add('Ambiente ${f.corrosivity} (${f.corrosivityWhy}): recomendable galvanizado en caliente (EN ISO 1461) o sistema '
          'dúplex galvanizado + pintura, o un sistema EN ISO 12944 de durabilidad alta (≥ 15 años).');
    } else if (cIdx >= 4 && galv && !s.finish.contains('lacad')) {
      out.add('Ambiente ${f.corrosivity} (${f.corrosivityWhy}): para más de 15–20 años, sistema dúplex (galvanizado + pintura).');
    }
    if (cIdx >= 5 && kind == MaterialKind.stainless && !s.grade.name.contains('316')) {
      out.add('Ambiente marino: usar inox 316L (1.4404) en lugar de 304, que se mancha con el salitre.');
    }
  }
  if (f.pressure) {
    out.add('Equipo a presión (más de 0,5 bar): fuera del alcance de este predimensionado. Requiere proyecto según UNE-EN 13445 '
        '(o ASME VIII), Directiva 2014/68/UE y Reglamento de equipos a presión (RD 809/2021): chapa EN 10028, '
        'WPS cualificadas, radiografía de cordones y prueba hidráulica.');
  } else if (f.vessel) {
    out.add('Depósitos, tanques, silos y tolvas: la estructura soporte se calcula aquí; la chapa del recipiente se dimensiona '
        'aparte (UNE-EN 14015 tanques, UNE-EN 1993-4 silos y depósitos) con cordones continuos estancos y prueba de llenado.');
  }
  if (f.motorized && s.type == StructureType.cancela) {
    out.add('Puerta motorizada: marcado CE según UNE-EN 13241 y seguridad de uso UNE-EN 12453 (limitación de fuerza, '
        'bandas sensibles, fotocélulas) y Directiva de máquinas.');
  }
  return out;
}

/// Recomendaciones de taller que van a la memoria (no son avisos).
List<String> fabricationHypotheses(Fabrication f, StructureSpec s) => [
      if (s.finish.contains('galvaniz'))
        'Diseño para galvanizar (EN ISO 14713-2): taladros de venteo y drenaje en los extremos de todos los tubos cerrados, '
            'cordones continuos y soldadura antes del baño; recubrimiento según EN ISO 1461.',
      if (s.grade.kind == MaterialKind.stainless)
        'Inox: herramientas y discos exclusivos (sin contacto con acero al carbono), decapado y pasivado de los cordones.',
      if (f.continuous) 'Cordones continuos en todo el perímetro de las uniones (estancos).',
      if (f.fullPenetration) 'Uniones a tope con penetración completa: preparación de bordes según EN ISO 9692-1 y saneado de raíz.',
      if (f.siteWelding) 'Soldaduras de obra marcadas con banderita en los planos (EN ISO 2553).',
      if (f.corrosivity.isNotEmpty)
        'Corrosividad ${f.corrosivity} (${f.corrosivityWhy}) según EN ISO 9223; protección según EN ISO 12944 / EN ISO 1461.',
    ];
