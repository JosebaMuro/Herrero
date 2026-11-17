import 'model.dart';

/// Ficha de una tipología: qué es, cómo se la llama, qué se calcula y qué
/// datos conviene dar. La usa el intérprete (sinónimos) y la pantalla de
/// tipologías de la app.
class Typology {
  final StructureType type;
  final String description;

  /// Palabras clave (texto normalizado, sin tildes) con su peso: las palabras
  /// específicas pesan más que las genéricas ("cubierta", "soporte"…).
  final Map<String, int> keywords;
  final List<String> computes;
  final String data;
  final String example;
  final String norm;
  const Typology({
    required this.type,
    required this.description,
    required this.keywords,
    required this.computes,
    required this.data,
    required this.example,
    required this.norm,
  });
}

const typologies = <Typology>[
  Typology(
    type: StructureType.nave,
    description: 'Edificio de pórticos de alma llena a dos aguas (o a un agua) con correas, '
        'arriostramientos en cruz, pilarillos de hastial y cimentación por zapatas.',
    keywords: {
      'nave': 10, 'naves': 10, 'almacen': 6, 'hangar': 10, 'taller': 7, 'granja': 8, 'establo': 9,
      'cuadra': 8, 'pabellon': 9, 'polideportivo': 9, 'portico a dos aguas': 10, 'porticos': 6,
      'portico': 4, 'cubierta a dos aguas': 7, 'edificio industrial': 10, 'industrial': 3,
      'garaje': 5, 'cochera cerrada': 8, 'invernadero': 7, 'caseta': 5, 'cobertizo cerrado': 8,
      'picadero': 9, 'nave industrial': 10, 'nave almacen': 10, 'nave agricola': 10, 'almacen agricola': 10, 'gallinero': 7, 'aprisco': 8,
      'cuadra de caballos': 9, 'nave ganadera': 10,
    },
    computes: ['Correas (IPE) y cubierta', 'Dinteles y pilares (IPE/HEB) con acartelamiento', 'Viga de atado y cruces de San Andrés',
      'Pilarillos de hastial', 'Placas de anclaje, pernos y zapatas', 'Soldaduras y pedido de barras'],
    data: 'Largo x luz, altura al alero, separación de pórticos, cubierta (chapa, sándwich…), ciudad o altitud (nieve/viento).',
    example: 'Nave a dos aguas de 30 x 15 m, 6 m al alero, pórticos cada 6 m, panel sándwich, en Vitoria',
    norm: 'CTE DB-SE-AE (nieve, viento), DB-SE-A / EC3',
  ),
  Typology(
    type: StructureType.marquesina,
    description: 'Cubierta ligera sobre pilares en voladizo: marquesinas de aparcamiento, pérgolas, '
        'porches, cocheras abiertas, tejavanas y sombrajes.',
    keywords: {
      'marquesina': 10, 'pergola': 10, 'porche': 10, 'cobertizo': 7, 'carport': 10, 'cochera': 8,
      'parking': 7, 'aparcamiento': 7, 'tejavana': 10, 'sombraje': 10, 'toldo': 6, 'techado': 5,
      'tejadillo': 8, 'cubierta': 2, 'tejado': 3, 'voladizo': 4, 'cenador': 9, 'gazebo': 9,
      'terraza cubierta': 8, 'cubierta de terraza': 8, 'sombra': 3, 'parasol': 6, 'cubierta solar': 8,
      'pergola fotovoltaica': 10, 'marquesina solar': 10, 'pergola bioclimatica': 10, 'leñero': 8, 'lenero': 8, 'porche de entrada': 10,
    },
    computes: ['Correas (tubo) y cubierta', 'Vigas principales y de borde', 'Pilares en ménsula (tubo) con jabalcones',
      'Placas de anclaje y zapatas'],
    data: 'Largo x ancho, altura libre, cubierta (chapa, policarbonato, sin cubierta, fotovoltaica), ciudad.',
    example: 'Marquesina para 2 coches de 5,5 x 5 m y 2,4 m de alto, chapa grecada, galvanizada',
    norm: 'CTE DB-SE-AE, DB-SE-A / EC3',
  ),
  Typology(
    type: StructureType.entreplanta,
    description: 'Forjado metálico intermedio sobre pilares: altillos, entreplantas de almacén u oficina, '
        'plataformas técnicas, con barandilla perimetral.',
    keywords: {
      'altillo': 10, 'entreplanta': 10, 'entre planta': 10, 'forjado': 7, 'plataforma': 6, 'mezzanine': 10,
      'altell': 10, 'tarima elevada': 9, 'desvan': 6, 'piso intermedio': 10, 'doble altura': 6, 'buhardilla': 6,
      'sobrado': 8, 'planta intermedia': 10, 'plataforma de almacenaje': 10, 'forjado metalico': 10,
      'suelo elevado': 7, 'plataforma tecnica': 9,
    },
    computes: ['Viguetas y vigas (IPE/HEB)', 'Pilares (tubo/HEB) y cruces', 'Barandilla CTE DB-SUA', 'Placas y anclajes químicos'],
    data: 'Largo x ancho, altura del forjado, uso (almacén, oficina, vivienda…) o carga en kg/m², tipo de suelo.',
    example: 'Altillo de 8 x 4 m a 3 m de altura para almacén, suelo de tramex',
    norm: 'CTE DB-SE-AE tabla 3.1, DB-SUA 1, EC3',
  ),
  Typology(
    type: StructureType.escalera,
    description: 'Escalera de zancas metálicas con peldaños de chapa o tramex: recta, en L o en U con meseta, '
        'de zanca central, de caracol (mástil central) y escala de gato con aros.',
    keywords: {
      'escalera': 10, 'escaleras': 10, 'escalinata': 10, 'peldaños': 7, 'peldanos': 7, 'peldano': 7, 'zanca': 9,
      'zancas': 9, 'escalera de caracol': 10, 'caracol': 6, 'escalera de incendios': 10, 'escalera de emergencia': 10,
      'escala': 5, 'escala de gato': 10, 'escalera exterior': 10, 'escalera de acceso': 10, 'escalera en l': 10,
      'escalera en u': 10, 'escalera de zanca central': 10, 'contrahuella': 6, 'mamperlan': 6,
    },
    computes: ['Número de peldaños, huella y contrahuella (CTE DB-SUA)', 'Zancas (UPN / tubo rectangular) o mástil central',
      'Apoyos de peldaño y meseta', 'Barandilla y pasamanos', 'Aros de protección (escala de gato)', 'Placas de apoyo y soldaduras'],
    data: 'Altura a salvar, ancho de paso, forma (recta, en L, en U, caracol, escala de gato), uso, acabado.',
    example: 'Escalera metálica de 3,2 m de altura y 1 m de ancho con barandilla, galvanizada',
    norm: 'CTE DB-SUA 1 §4, DB-SE-AE, EC3',
  ),
  Typology(
    type: StructureType.pasarela,
    description: 'Pasarela elevada o puente peatonal de vigas metálicas con suelo de tramex o chapa, '
        'apoyada en pilares, con barandillas a ambos lados.',
    keywords: {
      'pasarela': 10, 'puente peatonal': 10, 'puente': 6, 'pasillo elevado': 10, 'pasarela de mantenimiento': 10,
      'rampa': 6, 'acceso elevado': 8, 'plataforma de acceso': 8, 'paso elevado': 10, 'pasillo': 3,
    },
    computes: ['Vigas principales y travesaños', 'Pilares y arriostramientos', 'Barandillas a ambos lados',
      'Placas y anclajes'],
    data: 'Longitud, ancho útil, altura, uso (mantenimiento o público), separación de apoyos.',
    example: 'Pasarela de mantenimiento de 12 m de largo y 1 m de ancho a 4 m de altura, tramex',
    norm: 'CTE DB-SE-AE, EN ISO 14122-2/3, EC3',
  ),
  Typology(
    type: StructureType.barandilla,
    description: 'Barandilla o antepecho de protección (montantes, pasamanos, larguero y relleno de barrotes, '
        'vidrio, cables, chapa perforada o lamas, con rodapié si se pide) y pasamanos a pared sobre soportes.',
    keywords: {
      'barandilla': 10, 'barandillas': 10, 'baranda': 10, 'antepecho': 10, 'pasamanos': 9, 'quitamiedos': 9,
      'guardacuerpos': 10, 'barandilla de escalera': 10, 'barandilla de vidrio': 10, 'peto': 6, 'proteccion de borde': 9,
      'barandal': 10, 'pasamanos a pared': 10, 'pasamanos de escalera': 10, 'rodapie': 5, 'barrotes': 3,
    },
    computes: ['Montantes (tubo) y separación', 'Pasamanos y largueros', 'Relleno: barrotes cada ≤ 10 cm, vidrio, cables, chapa',
      'Rodapié', 'Pasamanos a pared: tubo redondo y soportes', 'Placas y anclajes'],
    data: 'Longitud, altura (0,9 / 1,1 m), relleno, uso (vivienda, público), anclaje (sobre losa o lateral).',
    example: 'Barandilla de 15 m de largo y 1,1 m de altura para terraza pública, lacada en negro',
    norm: 'CTE DB-SUA 1 §3.2, DB-SE-AE §3.2',
  ),
  Typology(
    type: StructureType.cercha,
    description: 'Cubierta de cerchas de celosía (tipo Pratt / a dos aguas o de cordones paralelos) '
        'apoyadas sobre muros o pilares, con correas y arriostramiento.',
    keywords: {
      'cercha': 10, 'cerchas': 10, 'celosia': 7, 'armadura': 7, 'viga en celosia': 10, 'viga celosia': 10,
      'cubierta de cerchas': 10, 'tejado de cerchas': 10, 'warren': 10, 'pratt': 10, 'howe': 10,
      'cercha triangular': 10, 'cercha plana': 10, 'cordones paralelos': 9, 'cordon superior': 8, 'estructura de cubierta': 7, 'tejado': 3,
    },
    computes: ['Cordones superior e inferior (tubo)', 'Diagonales y montantes', 'Correas', 'Arriostramiento de cubierta',
      'Apoyos y soldaduras de nudos'],
    data: 'Luz de la cercha, longitud de la cubierta, separación, pendiente, cubierta, apoyo (muros o pilares), ciudad.',
    example: 'Cubierta de cerchas de 10 m de luz y 15 m de largo sobre muros a 3 m, chapa sándwich, en Burgos',
    norm: 'CTE DB-SE-AE, DB-SE-A / EC3',
  ),
  Typology(
    type: StructureType.torre,
    description: 'Estructura de cuatro patas arriostradas: soportes de depósito o aljibe, castilletes, '
        'bancadas de maquinaria y torres ligeras.',
    keywords: {
      'torre': 10, 'castillete': 10, 'deposito': 8, 'aljibe': 9, 'tanque': 8, 'silo': 8, 'soporte de deposito': 10,
      'bancada': 9, 'soporte de maquina': 10, 'soporte de maquinaria': 10, 'mesa de trabajo': 7, 'banco de trabajo': 7,
      'atalaya': 9, 'mirador': 7, 'torreta': 10, 'soporte': 2, 'andamio': 6, 'estructura para placas': 5,
    },
    computes: ['Patas (tubo/HEB) a compresión y pandeo', 'Vuelco por viento', 'Cruces en todas las caras',
      'Emparrillado superior', 'Placas, pernos y zapatas'],
    data: 'Planta (lado x lado), altura, carga (litros de depósito, kg de máquina), ciudad.',
    example: 'Soporte para depósito de agua de 5000 litros a 4 m de altura, base de 2 x 2 m, galvanizado',
    norm: 'CTE DB-SE-AE (viento), EC3',
  ),
  Typology(
    type: StructureType.estanteria,
    description: 'Estantería o rack de carga de bastidores (puntales + celosía) y largueros por niveles.',
    keywords: {
      'estanteria': 10, 'estanterias': 10, 'rack': 10, 'racks': 10, 'paletizacion': 10, 'baldas': 6, 'balda': 6,
      'estante': 8, 'almacenaje': 5, 'cantilever': 8, 'palets': 4, 'paletas': 4,
    },
    computes: ['Largueros por nivel (flecha L/200)', 'Puntales a pandeo', 'Celosía de bastidor', 'Anclajes'],
    data: 'Largo, fondo, altura, nº de niveles y carga por nivel (kg o palés).',
    example: 'Estantería de 8 m de largo, 1,1 m de fondo y 4,5 m de alto, 3 niveles de 2 palés de 800 kg',
    norm: 'EN 15512 (simplificado), EC3',
  ),
  Typology(
    type: StructureType.cancela,
    description: 'Cancela, puerta o portón de una o dos hojas (abatible o corredera) con bastidor de tubo, '
        'barrotes o chapa y pilares de cuelgue.',
    keywords: {
      'cancela': 10, 'puerta': 8, 'porton': 10, 'portalon': 10, 'verja': 8, 'portillo': 9, 'puerta corredera': 10,
      'puerta abatible': 10, 'puerta de garaje': 10, 'puerta peatonal': 10, 'porton corredero': 10, 'cancilla': 10,
    },
    computes: ['Pilares de cuelgue (flexión por peso y viento)', 'Bastidor y diagonal antidescuelgue', 'Barrotes o chapa',
      'Herrajes: pernios, guía, ruedas', 'Placas y soldaduras'],
    data: 'Hueco libre, altura, nº de hojas o corredera, relleno (barrotes, chapa, malla).',
    example: 'Cancela corredera de 4 m de hueco y 2 m de altura con barrotes, lacada en negro',
    norm: 'EN 13241 (orientativo), CTE DB-SE-AE (viento), EC3',
  ),
  Typology(
    type: StructureType.valla,
    description: 'Valla o cerramiento de parcela (postes anclados, largueros y relleno de barrotes, chapa o malla) '
        'y reja de ventana (bastidor y barrotes con garras al muro).',
    keywords: {
      'valla': 10, 'vallado': 10, 'cerramiento': 4, 'cerca': 7, 'reja': 8, 'rejas': 8, 'enrejado': 9, 'reja de ventana': 10,
      'cerramiento de parcela': 10, 'malla de simple torsion': 9, 'malla electrosoldada': 7, 'muro de chapa': 8, 'empalizada': 8,
    },
    computes: ['Postes en ménsula por viento', 'Largueros', 'Barrotes / chapa / malla', 'Placas y anclajes'],
    data: 'Longitud, altura, relleno (barrotes, chapa ciega, malla), ciudad (viento).',
    example: 'Valla de 30 m de largo y 2 m de alto con barrotes, en Cádiz',
    norm: 'CTE DB-SE-AE (viento), EC3',
  ),
  Typology(
    type: StructureType.portico,
    description: 'Pórtico de elevación o de taller con viga carril para polipasto, patas en A arriostradas.',
    keywords: {
      'polipasto': 10, 'portico de elevacion': 10, 'portico grua': 10, 'grua portico': 10, 'cabria': 10,
      'puente grua': 9, 'monorrail': 10, 'viga carril': 10, 'portico de carga': 10, 'diferencial': 7, 'grua': 6,
      'portico': 3,
    },
    computes: ['Viga carril (impacto 1,25, flecha L/500)', 'Patas en A a pandeo', 'Tirante y placas', 'Soldaduras'],
    data: 'Luz entre patas, altura bajo viga, carga a elevar (kg o t).',
    example: 'Pórtico para polipasto de 1000 kg, 4 m de luz y 3 m de altura',
    norm: 'EN 1991-3 / EN 1993-6 (simplificado), EC3',
  ),
  Typology(
    type: StructureType.poste,
    description: 'Poste, mástil o soporte de cartel en ménsula, dimensionado frente al viento sobre el panel.',
    keywords: {
      'poste': 9, 'mastil': 10, 'cartel': 9, 'letrero': 10, 'valla publicitaria': 10, 'monoposte': 10,
      'soporte de cartel': 10, 'baculo': 10, 'farola': 9, 'bandera': 8, 'señal': 7, 'senal': 7, 'rotulo': 9,
      'totem': 10, 'senaletica': 8, 'banderola': 9, 'antena': 7, 'pantalla': 4,
    },
    computes: ['Poste(s) en ménsula por viento', 'Bastidor del cartel', 'Placa de anclaje y pernos', 'Zapata orientativa'],
    data: 'Medidas del cartel (ancho x alto), altura libre bajo el cartel, ciudad (viento).',
    example: 'Soporte para cartel de 4 x 2 m a 3 m de altura, en Tarifa',
    norm: 'CTE DB-SE-AE (viento), EC3',
  ),
];

Typology typologyOf(StructureType t) => typologies.firstWhere((e) => e.type == t);

/// Peticiones que no tienen tipología propia: se proponen con la más parecida.
const unsupportedHints = <String, (StructureType, String)>{
  'puente grua': (StructureType.portico,
      'Puente grúa sobre carriles: fuera de alcance (EN 1993-6). Se predimensiona un pórtico de elevación con la misma carga.'),
  'invernadero': (StructureType.nave,
      'Invernadero: se predimensiona como nave ligera; los invernaderos comerciales siguen EN 13031-1.'),
  'andamio': (StructureType.torre,
      'Andamio: debe ser un sistema homologado (EN 12810/12811). Se propone una torre arriostrada solo como referencia.'),
  'silo': (StructureType.torre, 'Silo: se dimensiona solo la estructura soporte; el silo (EN 1993-4-1) no se calcula.'),
  'rampa': (StructureType.pasarela, 'Rampa: se calcula como pasarela; pendiente máxima 10 % (6 % si es itinerario accesible, CTE DB-SUA 9).'),
  'balcon': (StructureType.entreplanta, 'Balcón: se propone una plataforma apoyada; un balcón en voladizo necesita cálculo de anclajes al forjado.'),
  'caseta': (StructureType.nave, 'Caseta: se predimensiona como nave pequeña de pórticos.'),
  'mesa': (StructureType.torre, 'Mesa / banco: se predimensiona como bancada de cuatro patas.'),
  'antena': (StructureType.poste, 'Antena: se trata como mástil en ménsula; las torres de telecomunicación requieren EN 1993-3-1.'),
  'chimenea': (StructureType.poste, 'Chimenea metálica: fuera de alcance (EN 1993-3-2). Se propone un mástil como referencia.'),
};
