// Catálogo de materiales del oficio (repositorio versionado en el código).
//
// Cada material reúne en un solo sitio lo que antes estaba repartido:
//  - cómo lo llama la gente (sinónimos, regionalismos y faltas habituales),
//  - qué es, para qué se usa y medidas o perfiles habituales,
//  - peso orientativo (kN/m² en cubiertas y suelos, kg/m en perfiles),
//  - aspecto para el render 3D (color, brillo, transparencia y dibujo),
//  - frase en inglés para la foto IA (SD-Turbo / CLIP),
//  - y en qué campo de la ficha va (cubierta, suelo, cerramiento, relleno o perfil).
//
// Lo usan el intérprete (cubierta y cerramiento), la IA (bloque de materiales
// citados en la petición), el cálculo (peso propio de cubiertas nuevas), el
// render, la foto IA y la pestaña «Materiales» del catálogo.
//
// Para ampliarlo basta con añadir un [BuildMaterial] a [materialCatalog]: los
// sinónimos van en minúsculas y sin tildes (como deja el texto [normalize]).
import 'parser.dart' show normalize;
import 'profiles.dart';

/// Dónde va el material en la estructura.
enum MatGroup { perfil, chapa, cubierta, suelo, cerramiento, vidrio, relleno }

extension MatGroupLabel on MatGroup {
  String get label => switch (this) {
        MatGroup.perfil => 'Perfiles y barras',
        MatGroup.chapa => 'Chapas',
        MatGroup.cubierta => 'Cubiertas',
        MatGroup.suelo => 'Suelos y peldaños',
        MatGroup.cerramiento => 'Cerramientos y fachadas',
        MatGroup.vidrio => 'Vidrio y cristal',
        MatGroup.relleno => 'Rellenos de barandilla, valla y cancela',
      };

  /// Campo de la ficha en el que se escribe.
  String get fichaField => switch (this) {
        MatGroup.perfil => 'perfil por partes (pilares, vigas, correas…)',
        MatGroup.chapa => 'cubierta, suelo o relleno según dónde vaya',
        MatGroup.cubierta => 'cubierta',
        MatGroup.suelo => 'cubierta (en altillos, pasarelas y escaleras es el suelo)',
        MatGroup.cerramiento => 'cerramiento',
        MatGroup.vidrio => 'cubierta o relleno de barandilla',
        MatGroup.relleno => 'variante (relleno)',
      };
}

/// Dibujo de la superficie en el render (mismos valores que ZPattern).
enum MatPattern { none, grating, ribbed, sandwich, tile, solar, checker, wood, concrete }

/// Aspecto en el render: color (0–1), brillo especular, opacidad y dibujo.
class MatLook {
  final double r, g, b;
  final double specular;
  final double alpha;
  final MatPattern pattern;
  const MatLook(this.r, this.g, this.b, {this.specular = 0.3, this.alpha = 1, this.pattern = MatPattern.none});

  /// Color en 0xAARRGGBB (para la pantalla del catálogo).
  int get argb => 0xFF000000 | ((r * 255).round() << 16) | ((g * 255).round() << 8) | (b * 255).round();
}

/// Un material del catálogo.
class BuildMaterial {
  final String id;
  final String name;
  final MatGroup group;

  /// Formas de nombrarlo (minúsculas, sin tildes). La primera coincidencia gana.
  final List<String> aka;
  final String description;
  final List<String> uses;

  /// Medidas, espesores o perfiles habituales.
  final String sizes;

  /// Peso orientativo en texto (para pantalla y LLM).
  final String weight;

  /// Peso propio superficial típico (kN/m²) si es cubierta, suelo o cerramiento.
  final double? kNm2;

  /// Aspecto en el render; null = color del acero de la estructura.
  final MatLook? look;

  /// Frase en inglés para la foto IA.
  final String photo;

  /// Texto que se escribe en la ficha (spec.roofing / spec.cladding) al elegirlo.
  final String? fichaText;

  /// Familia de perfiles de la app, si es un perfil (para medidas y pesos).
  final ProfileFamily? family;

  const BuildMaterial({
    required this.id,
    required this.name,
    required this.group,
    required this.aka,
    required this.description,
    this.uses = const [],
    this.sizes = '',
    this.weight = '',
    this.kNm2,
    this.look,
    required this.photo,
    this.fichaText,
    this.family,
  });

  /// Medidas habituales; en perfiles, la serie y el peso que trae la app.
  String get sizesText {
    final f = family;
    if (f == null) return sizes;
    final t = tableFor(f);
    if (t.isEmpty) return sizes;
    String kg(double v) => v.toStringAsFixed(v < 10 ? 1 : 0).replaceAll('.', ',');
    final w = t.map((p) => p.kgm).toList()..sort();
    final range = 'En la app: ${t.first.name} … ${t.last.name} (${kg(w.first)}–${kg(w.last)} kg/m).';
    return sizes.isEmpty ? range : '$sizes $range';
  }

  /// Línea corta para el LLM.
  String get llmLine {
    final d = description.split(RegExp(r'(?<=\.)\s')).first;
    final w = weight.isEmpty ? '' : ' Peso: $weight.';
    return '$name: $d Va en «${group.fichaField}».$w';
  }
}

// Colores de referencia (coinciden con los que ya usaba el render).
const _steelGrey = MatLook(0.78, 0.79, 0.80, pattern: MatPattern.ribbed);

const List<BuildMaterial> materialCatalog = [
  // ---------------------------------------------------------------- Perfiles
  BuildMaterial(
    id: 'ipe',
    name: 'IPE',
    group: MatGroup.perfil,
    aka: ['ipe', 'viga doble t', 'doble t', 'perfil i'],
    description: 'Perfil laminado en doble T de alas estrechas y paralelas. Trabaja muy bien a flexión en su plano.',
    uses: ['vigas', 'correas de nave', 'dinteles de pórtico', 'viguetas de altillo'],
    sizes: 'IPE 80 a IPE 600.',
    weight: '6–122 kg/m',
    photo: 'steel I-beams',
    family: ProfileFamily.ipe,
  ),
  BuildMaterial(
    id: 'ipn',
    name: 'IPN',
    group: MatGroup.perfil,
    aka: ['ipn', 'doble t normal', 'perfil normal'],
    description: 'Perfil en doble T de alas inclinadas (serie antigua). La app lo calcula con el IPE equivalente.',
    uses: ['vigas carril de polipasto', 'dinteles', 'refuerzos en obra de rehabilitación'],
    sizes: 'IPN 80 a IPN 400 (5,9–92 kg/m).',
    weight: '6–92 kg/m',
    photo: 'tapered flange steel I-beams',
    family: ProfileFamily.ipe,
  ),
  BuildMaterial(
    id: 'heb',
    name: 'HEB / HEA / HEM',
    group: MatGroup.perfil,
    aka: ['heb', 'hea', 'hem', 'perfil h', 'viga h', 'pilar h'],
    description: 'Perfil en H de alas anchas: HEB macizo, HEA aligerado y HEM reforzado. Pilares y vigas muy cargadas.',
    uses: ['pilares de nave', 'jácenas', 'vigas de altillo con mucha carga', 'pilares de pórtico grúa'],
    weight: '10–270 kg/m',
    photo: 'wide flange steel H-beam columns',
    family: ProfileFamily.heb,
  ),
  BuildMaterial(
    id: 'upn',
    name: 'UPN / UPE',
    group: MatGroup.perfil,
    aka: ['upn', 'upe', 'uap', 'perfil u', 'perfil en u', 'canal u', 'u de hierro'],
    description: 'Perfil en U (UPN con alas inclinadas, UPE con alas paralelas). Se suelda y atornilla por el alma plana.',
    uses: ['zancas de escalera', 'bastidores', 'cercos de cancela', 'vigas de borde', 'pilares en cajón (2 UPN)'],
    weight: '8–60 kg/m',
    photo: 'steel U-channel profiles',
    family: ProfileFamily.upn,
  ),
  BuildMaterial(
    id: 'tubo',
    name: 'Tubo cuadrado / rectangular',
    group: MatGroup.perfil,
    aka: ['tubo cuadrado', 'tubo rectangular', 'tubo estructural', 'shs', 'rhs', 'cuadradillo hueco', 'perfil tubular'],
    description: 'Perfil hueco conformado en frío o en caliente. Mucha rigidez a torsión y fácil de soldar.',
    uses: ['pilares de marquesina', 'montantes', 'postes', 'correas ligeras', 'bastidores de cancela', 'cerchas'],
    sizes: 'De 20x20x1,5 a 300x300x10; rectangular de 40x20 a 400x200.',
    weight: '0,9–90 kg/m',
    photo: 'square hollow section steel tubes',
    family: ProfileFamily.shs,
  ),
  BuildMaterial(
    id: 'tubo-redondo',
    name: 'Tubo redondo',
    group: MatGroup.perfil,
    aka: ['tubo redondo', 'tubo circular', 'chs', 'tuberia estructural'],
    description: 'Perfil hueco circular. Mismo comportamiento en todas las direcciones.',
    uses: ['pasamanos', 'mástiles y báculos', 'cordones de celosía', 'columnas vistas'],
    weight: '1–40 kg/m',
    photo: 'round steel tubes',
    family: ProfileFamily.chs,
  ),
  BuildMaterial(
    id: 'angular',
    name: 'Angular (L)',
    group: MatGroup.perfil,
    aka: ['angular', 'angulo', 'perfil l', 'cantonera', 'ele de hierro'],
    description: 'Perfil en L de alas iguales o desiguales.',
    uses: ['arriostramientos', 'casquillos de unión', 'cercos', 'montantes ligeros', 'bastidor de tramex'],
    weight: '1–30 kg/m',
    photo: 'steel angle profiles',
    family: ProfileFamily.angle,
  ),
  BuildMaterial(
    id: 'llanta',
    name: 'Llanta / pletina',
    group: MatGroup.perfil,
    aka: ['llanta', 'pletina', 'platabanda', 'fleje', 'barra plana', 'planchuela'],
    description: 'Barra plana laminada de sección rectangular maciza.',
    uses: ['cartelas y orejetas', 'casquillos', 'barrotes planos de barandilla', 'zancas ligeras', 'refuerzos'],
    sizes: 'Anchos de 20 a 200 mm y espesores de 4 a 20 mm.',
    weight: '0,6–31 kg/m (40x5 = 1,57 kg/m)',
    photo: 'flat steel bars',
    family: ProfileFamily.flat,
  ),
  BuildMaterial(
    id: 'redondo',
    name: 'Redondo macizo / varilla',
    group: MatGroup.perfil,
    aka: ['redondo macizo', 'varilla', 'redondo', 'barra redonda', 'tirante'],
    description: 'Barra maciza de sección circular.',
    uses: ['tirantes y cruces de San Andrés', 'barrotes', 'pernos de anclaje', 'aros de escala de gato'],
    sizes: 'Ø 8 a Ø 30 mm.',
    weight: 'Ø12 = 0,89 kg/m · Ø16 = 1,58 kg/m · Ø20 = 2,47 kg/m',
    photo: 'solid round steel bars',
    family: ProfileFamily.round,
  ),
  BuildMaterial(
    id: 'cuadradillo',
    name: 'Cuadradillo macizo',
    group: MatGroup.perfil,
    aka: ['cuadradillo', 'cuadrado macizo', 'barra cuadrada'],
    description: 'Barra maciza de sección cuadrada, típica de cerrajería y forja.',
    uses: ['barrotes de reja y barandilla', 'forja artística', 'balaustres'],
    sizes: '10x10 a 30x30 mm.',
    weight: '12x12 = 1,13 kg/m · 16x16 = 2,01 kg/m · 20x20 = 3,14 kg/m',
    photo: 'solid square wrought iron bars',
  ),
  BuildMaterial(
    id: 'perfil-t',
    name: 'Perfil T',
    group: MatGroup.perfil,
    aka: ['perfil t', 'te de hierro', 'perfil en t'],
    description: 'Perfil laminado en T de alas iguales.',
    uses: ['marcos de vidrio y claraboyas', 'soportes de peldaño', 'cercos de cerrajería'],
    sizes: 'T 20 a T 100.',
    weight: '0,9–16 kg/m',
    photo: 'steel T-profiles',
  ),
  BuildMaterial(
    id: 'perfil-conformado',
    name: 'Perfil conformado C / Z',
    group: MatGroup.perfil,
    aka: ['perfil c', 'perfil z', 'correa z', 'correa c', 'conformado', 'omega'],
    description: 'Perfil de chapa galvanizada plegada en frío (C, Z u omega). Ligero para correas de nave.',
    uses: ['correas de cubierta', 'correas de fachada', 'rastreles'],
    sizes: 'C/Z 100 a 300, espesor 1,5–3 mm.',
    weight: '2,5–10 kg/m',
    photo: 'cold formed galvanized Z purlins',
  ),

  // ------------------------------------------------------------------ Chapas
  BuildMaterial(
    id: 'chapa-lisa',
    name: 'Chapa lisa',
    group: MatGroup.chapa,
    aka: ['chapa lisa', 'chapa negra', 'chapa galvanizada', 'plancha', 'palastro', 'chapon'],
    description: 'Chapa de acero laminada lisa, negra (laminada en caliente) o galvanizada.',
    uses: ['placas de anclaje', 'cartelas', 'forros', 'cancelas ciegas', 'remates'],
    sizes: 'Espesores de 0,8 a 30 mm; formatos 1000x2000, 1250x2500, 1500x3000.',
    weight: '7,85 kg/m² por mm de espesor',
    kNm2: 0.24,
    look: MatLook(0.62, 0.63, 0.64, specular: 0.35),
    photo: 'flat steel sheet panels',
    fichaText: 'chapa lisa',
  ),
  BuildMaterial(
    id: 'chapa-lagrimada',
    name: 'Chapa lagrimada',
    group: MatGroup.suelo,
    aka: ['chapa lagrimada', 'lagrimada', 'chapa estriada', 'chapa antideslizante', 'chapa de lagrima', 'chapa damero',
      'chapa diamante'],
    description: 'Chapa antideslizante con relieve en lágrima. Suelos, peldaños y tapas.',
    uses: ['peldaños de escalera', 'suelo de altillo', 'mesetas', 'tapas de foso', 'rampas'],
    sizes: 'Espesor 3+2 a 8+2 mm (espesor base + relieve).',
    weight: '5 mm ≈ 42 kg/m² (0,40 kN/m²)',
    kNm2: 0.44,
    look: MatLook(0.70, 0.71, 0.72, specular: 0.35, pattern: MatPattern.checker),
    photo: 'diamond checker plate steel floor',
    fichaText: 'chapa lagrimada',
  ),
  BuildMaterial(
    id: 'chapa-perforada',
    name: 'Chapa perforada',
    group: MatGroup.relleno,
    aka: ['chapa perforada', 'chapa agujereada', 'chapa microperforada'],
    description: 'Chapa con agujeros redondos o cuadrados en malla regular. Deja pasar luz y aire.',
    uses: ['relleno de barandilla', 'celosías de fachada', 'cancelas', 'protección de máquinas'],
    sizes: 'Espesor 1,5–4 mm; agujero 5–20 mm.',
    weight: '2 mm ≈ 10 kg/m²',
    kNm2: 0.10,
    look: MatLook(0.66, 0.67, 0.68, specular: 0.3, alpha: 0.6),
    photo: 'perforated metal sheet panels',
    fichaText: 'chapa perforada',
  ),
  BuildMaterial(
    id: 'deploye',
    name: 'Metal desplegado (deployé)',
    group: MatGroup.relleno,
    aka: ['deploye', 'metal desplegado', 'chapa desplegada', 'chapa estirada'],
    description: 'Chapa cortada y estirada que forma rombos. Rígida y ligera.',
    uses: ['suelos ligeros y pasarelas', 'rellenos de valla y cancela', 'falsos techos', 'protecciones'],
    sizes: 'Rombo 10x20 a 60x150 mm; espesor 1,5–6 mm.',
    weight: '6–25 kg/m²',
    kNm2: 0.15,
    look: MatLook(0.60, 0.61, 0.62, specular: 0.3, alpha: 0.5, pattern: MatPattern.grating),
    photo: 'expanded metal mesh panels',
    fichaText: 'metal desplegado',
  ),

  // ---------------------------------------------------------------- Cubiertas
  BuildMaterial(
    id: 'panel-sandwich',
    name: 'Panel sándwich',
    group: MatGroup.cubierta,
    aka: ['panel sandwich', 'sandwich', 'panel aislante', 'panel tipo sandwich', 'chapa sandwich'],
    description: 'Dos chapas de acero prelacado con núcleo aislante (PUR/PIR o lana de roca). Cubierta y fachada aislada.',
    uses: ['cubierta de nave', 'marquesinas aisladas', 'cerramientos de fachada', 'cámaras y casetas'],
    sizes: 'Espesores 30, 40, 50, 60, 80 y 100 mm; ancho útil 1000 mm. Cubierta de 3 o 5 grecas.',
    weight: '40 mm PUR ≈ 11 kg/m² (0,11 kN/m²); lana de roca 50 mm ≈ 16 kg/m²',
    kNm2: 0.11,
    look: MatLook(0.84, 0.85, 0.86, pattern: MatPattern.sandwich),
    photo: 'insulated sandwich panel roof',
    fichaText: 'panel sándwich',
  ),
  BuildMaterial(
    id: 'panel-sandwich-teja',
    name: 'Panel sándwich imitación teja',
    group: MatGroup.cubierta,
    aka: ['sandwich teja', 'sandwich imitacion teja', 'panel teja', 'panel imitacion teja', 'sandwich tipo teja'],
    description: 'Panel sándwich con la chapa exterior conformada y lacada como teja árabe.',
    uses: ['porches y casetas en zona residencial', 'rehabilitación de tejados'],
    sizes: 'Espesor 30–60 mm; color teja.',
    weight: '≈ 12 kg/m² (0,12 kN/m²)',
    kNm2: 0.12,
    look: MatLook(0.55, 0.25, 0.17, specular: 0.1, pattern: MatPattern.tile),
    photo: 'terracotta tile effect sandwich panel roof',
    fichaText: 'panel sándwich imitación teja',
  ),
  BuildMaterial(
    id: 'chapa-grecada',
    name: 'Chapa grecada (calaminón)',
    group: MatGroup.cubierta,
    aka: ['chapa grecada', 'chapa trapezoidal', 'chapa perfilada', 'calaminon', 'calaminones', 'greca', 'chapa nervada',
      'cobertura metalica', 'tr4', 'tr6'],
    description: 'Chapa de acero galvanizada o prelacada con grecas trapezoidales. En Perú y Bolivia se llama calaminón.',
    uses: ['cubierta de nave sin aislar', 'marquesinas', 'cobertizos', 'fachadas y cerramientos ligeros', 'muro de chapa'],
    sizes: 'Espesor 0,5–0,8 mm; greca 30–45 mm de alto; ancho útil 1000–1100 mm.',
    weight: '0,6 mm ≈ 6 kg/m² (0,12 kN/m² con fijaciones)',
    kNm2: 0.12,
    look: _steelGrey,
    photo: 'trapezoidal corrugated metal roof sheets',
    fichaText: 'chapa grecada',
  ),
  BuildMaterial(
    id: 'chapa-ondulada',
    name: 'Chapa ondulada (calamina)',
    group: MatGroup.cubierta,
    aka: ['chapa ondulada', 'calamina', 'calaminas', 'chapa de onda', 'minionda', 'chapa minionda', 'zinc ondulado'],
    description: 'Chapa galvanizada de onda sinusoidal (calamina). Cubierta económica y fachada de estilo industrial.',
    uses: ['cobertizos y tejavanas', 'casetas de obra', 'fachadas de estilo industrial'],
    sizes: 'Espesor 0,4–0,6 mm; onda 76/18 o minionda 27/8.',
    weight: '≈ 5 kg/m² (0,10 kN/m² con fijaciones)',
    kNm2: 0.10,
    look: MatLook(0.74, 0.76, 0.78, specular: 0.35, pattern: MatPattern.ribbed),
    photo: 'galvanized corrugated wavy metal roof sheets',
    fichaText: 'chapa ondulada',
  ),
  BuildMaterial(
    id: 'policarbonato-celular',
    name: 'Policarbonato celular',
    group: MatGroup.cubierta,
    aka: ['policarbonato celular', 'policarbonato alveolar', 'celular', 'alveolar', 'policarbonato'],
    description: 'Placa de policarbonato con alvéolos interiores: translúcida, ligera y algo aislante.',
    uses: ['pérgolas y porches', 'lucernarios', 'invernaderos', 'marquesinas'],
    sizes: 'Espesor 6, 8, 10, 16, 20 y 32 mm; transparente, opal o bronce. Perfilería de aluminio.',
    weight: '16 mm ≈ 2,7 kg/m² (0,03 kN/m²)',
    kNm2: 0.03,
    look: MatLook(0.75, 0.82, 0.86, specular: 0.4, alpha: 0.45),
    photo: 'translucent multiwall polycarbonate roof sheets',
    fichaText: 'policarbonato celular',
  ),
  BuildMaterial(
    id: 'policarbonato-compacto',
    name: 'Policarbonato compacto',
    group: MatGroup.cubierta,
    aka: ['policarbonato compacto', 'policarbonato macizo', 'policarbonato liso', 'metacrilato'],
    description: 'Placa maciza de policarbonato, transparente como el vidrio y casi irrompible.',
    uses: ['marquesinas de entrada', 'cubiertas transparentes', 'protecciones', 'paradas de autobús'],
    sizes: 'Espesor 3–12 mm.',
    weight: '6 mm ≈ 7 kg/m² (0,07 kN/m²)',
    kNm2: 0.07,
    look: MatLook(0.78, 0.86, 0.90, specular: 0.7, alpha: 0.35),
    photo: 'clear solid polycarbonate roof panels',
    fichaText: 'policarbonato compacto',
  ),
  BuildMaterial(
    id: 'policarbonato-grecado',
    name: 'Policarbonato grecado',
    group: MatGroup.cubierta,
    aka: ['policarbonato grecado', 'policarbonato ondulado', 'traslucido grecado', 'placa traslucida', 'lucernario'],
    description: 'Placa traslúcida con la misma greca que la chapa: se intercala para dar luz a la nave.',
    uses: ['lucernarios en cubierta de chapa', 'franjas de luz en fachada'],
    sizes: 'Espesor 0,8–1,5 mm; greca igual a la de la chapa.',
    weight: '≈ 1,5 kg/m²',
    kNm2: 0.02,
    look: MatLook(0.80, 0.86, 0.88, specular: 0.4, alpha: 0.5, pattern: MatPattern.ribbed),
    photo: 'translucent corrugated polycarbonate skylight sheets',
    fichaText: 'policarbonato celular',
  ),
  BuildMaterial(
    id: 'fibrocemento',
    name: 'Fibrocemento sin amianto',
    group: MatGroup.cubierta,
    aka: ['fibrocemento', 'uralita', 'placa ondulada de fibrocemento', 'eternit'],
    description: 'Placa ondulada de cemento con fibras (sin amianto). La «uralita» antigua tiene amianto: no se manipula.',
    uses: ['naves agrícolas', 'cobertizos', 'sustitución de cubiertas antiguas'],
    sizes: 'Espesor 6 mm; onda 177/51.',
    weight: '≈ 18 kg/m² (0,20 kN/m²)',
    kNm2: 0.20,
    look: MatLook(0.70, 0.70, 0.68, specular: 0.05, pattern: MatPattern.ribbed),
    photo: 'grey fiber cement corrugated roof sheets',
    fichaText: 'placa de fibrocemento sin amianto',
  ),
  BuildMaterial(
    id: 'placa-asfaltica',
    name: 'Placa asfáltica ondulada',
    group: MatGroup.cubierta,
    aka: ['onduline', 'placa asfaltica', 'placa bituminosa', 'ondulado asfaltico', 'chapa asfaltica'],
    description: 'Placa ondulada de fibras con betún. Muy ligera, silenciosa y no se oxida.',
    uses: ['casetas y cobertizos', 'bajo teja', 'leñeros', 'naves ganaderas'],
    sizes: 'Placa 2000x950 mm, espesor 2,6–3 mm.',
    weight: '≈ 3,5 kg/m² (0,05 kN/m²)',
    kNm2: 0.05,
    look: MatLook(0.30, 0.20, 0.17, specular: 0.05, pattern: MatPattern.ribbed),
    photo: 'dark bitumen corrugated roof sheets',
    fichaText: 'placa asfáltica ondulada',
  ),
  BuildMaterial(
    id: 'teja',
    name: 'Teja',
    group: MatGroup.cubierta,
    aka: ['teja', 'tejas', 'teja arabe', 'teja mixta', 'teja ceramica', 'teja de hormigon'],
    description: 'Teja cerámica o de hormigón sobre panel o rastrel.',
    uses: ['porches y tejadillos de vivienda', 'casetas', 'rehabilitación'],
    sizes: 'Árabe o mixta sobre panel sándwich o tablero con rastreles.',
    weight: '≈ 50–65 kg/m² con soporte (0,65 kN/m²)',
    kNm2: 0.65,
    look: MatLook(0.55, 0.25, 0.17, specular: 0.1, pattern: MatPattern.tile),
    photo: 'terracotta tiled roof',
    fichaText: 'teja sobre panel',
  ),
  BuildMaterial(
    id: 'fotovoltaica',
    name: 'Paneles fotovoltaicos',
    group: MatGroup.cubierta,
    aka: ['fotovoltaica', 'fotovoltaico', 'fotovoltaicos', 'placas solares', 'paneles solares', 'modulos solares'],
    description: 'Módulos solares que forman la cubierta (pérgola o marquesina solar).',
    uses: ['marquesinas de aparcamiento solares', 'pérgolas fotovoltaicas', 'cubiertas de nave'],
    sizes: 'Módulo ≈ 1,13 x 2,28 m, 25–30 kg.',
    weight: '≈ 12 kg/m² + perfilería (0,25 kN/m²)',
    kNm2: 0.25,
    look: MatLook(0.08, 0.12, 0.25, specular: 0.6, pattern: MatPattern.solar),
    photo: 'solar photovoltaic panels on the roof',
    fichaText: 'paneles fotovoltaicos',
  ),
  BuildMaterial(
    id: 'lamas',
    name: 'Lamas de aluminio (bioclimática)',
    group: MatGroup.cubierta,
    aka: ['lamas', 'lamas orientables', 'pergola bioclimatica', 'bioclimatica', 'lamas de aluminio', 'celosia'],
    description: 'Lamas de aluminio fijas u orientables que dan sombra y dejan pasar el aire.',
    uses: ['pérgolas bioclimáticas', 'celosías de fachada', 'sombrajes'],
    sizes: 'Lama 150–250 mm, aluminio lacado.',
    weight: '≈ 15 kg/m² (0,15 kN/m²)',
    kNm2: 0.15,
    look: MatLook(0.85, 0.85, 0.84, specular: 0.4, alpha: 0.85, pattern: MatPattern.ribbed),
    photo: 'aluminium louvered pergola roof',
    fichaText: 'sin cubierta (pérgola abierta)',
  ),

  // ------------------------------------------------------------------ Suelos
  BuildMaterial(
    id: 'tramex',
    name: 'Tramex (rejilla electrosoldada)',
    group: MatGroup.suelo,
    aka: ['tramex', 'rejilla', 'rejilla electrosoldada', 'emparrillado', 'trames', 'tramex galvanizado', 'pletina dentada'],
    description: 'Rejilla de pletinas portantes y varilla soldadas, galvanizada. Suelo que no acumula agua ni suciedad.',
    uses: ['suelos de pasarela y altillo', 'peldaños', 'tapas de foso', 'plataformas de mantenimiento'],
    sizes: 'Malla 30x30 o 34x38 mm; pletina portante 25x2 a 40x3 mm.',
    weight: '30x2 ≈ 20–30 kg/m² (0,40 kN/m² con bastidor)',
    kNm2: 0.40,
    look: MatLook(0.58, 0.59, 0.60, pattern: MatPattern.grating),
    photo: 'galvanized steel grating deck',
    fichaText: 'rejilla tramex',
  ),
  BuildMaterial(
    id: 'chapa-colaborante',
    name: 'Chapa colaborante + losa',
    group: MatGroup.suelo,
    aka: ['chapa colaborante', 'colaborante', 'forjado colaborante', 'losa mixta', 'steel deck'],
    description: 'Chapa grecada que sirve de encofrado perdido y armadura de una losa de hormigón.',
    uses: ['forjados de entreplanta con mucha carga', 'oficinas sobre altillo', 'forjados mixtos'],
    sizes: 'Chapa 0,75–1,2 mm; losa total 10–14 cm.',
    weight: 'Losa de 12 cm ≈ 260 kg/m² (2,60 kN/m²)',
    kNm2: 2.60,
    look: MatLook(0.66, 0.65, 0.62, specular: 0.05, pattern: MatPattern.concrete),
    photo: 'composite steel deck concrete floor slab',
    fichaText: 'chapa colaborante + losa de hormigón',
  ),
  BuildMaterial(
    id: 'tablero',
    name: 'Tablero fenólico / madera',
    group: MatGroup.suelo,
    aka: ['tablero fenolico', 'fenolico', 'tablero', 'osb', 'aglomerado hidrofugo', 'tarima', 'madera', 'tablones'],
    description: 'Tablero de madera (fenólico, OSB o aglomerado hidrófugo) o tarima atornillada a las viguetas.',
    uses: ['suelo de altillo de vivienda u oficina', 'trasteros', 'peldaños de madera', 'tarimas'],
    sizes: 'Espesor 18–30 mm.',
    weight: '22 mm ≈ 15 kg/m² (0,20 kN/m²)',
    kNm2: 0.20,
    look: MatLook(0.62, 0.46, 0.30, specular: 0.05, pattern: MatPattern.wood),
    photo: 'wooden board floor',
    fichaText: 'tablero fenólico/madera',
  ),

  // ------------------------------------------------------------ Cerramientos
  BuildMaterial(
    id: 'bloque',
    name: 'Bloque de hormigón',
    group: MatGroup.cerramiento,
    aka: ['bloque de hormigon', 'bloque', 'bloques', 'termoarcilla', 'muro de bloque'],
    description: 'Fábrica de bloque de hormigón (normalmente hasta media altura) con chapa o panel encima.',
    uses: ['zócalo de nave', 'cerramiento de parcela', 'muros cortafuegos'],
    sizes: 'Bloque 40x20x20 cm.',
    weight: '≈ 2,5 kN/m² (no carga sobre el acero si va al suelo)',
    look: MatLook(0.70, 0.69, 0.66, specular: 0.05, pattern: MatPattern.concrete),
    photo: 'concrete block walls',
    fichaText: 'bloque de hormigón',
  ),
  BuildMaterial(
    id: 'ladrillo',
    name: 'Ladrillo',
    group: MatGroup.cerramiento,
    aka: ['ladrillo', 'ladrillos', 'ladrillo caravista', 'caravista', 'fabrica de ladrillo'],
    description: 'Fábrica de ladrillo cerámico.',
    uses: ['cerramientos de caseta y garaje', 'zócalos'],
    weight: '≈ 1,5–2 kN/m²',
    look: MatLook(0.62, 0.36, 0.25, specular: 0.05, pattern: MatPattern.concrete),
    photo: 'red brick walls',
    fichaText: 'ladrillo',
  ),
  BuildMaterial(
    id: 'panel-fachada',
    name: 'Panel sándwich de fachada',
    group: MatGroup.cerramiento,
    aka: ['panel de fachada', 'panel sandwich de fachada', 'fachada de panel', 'panel tapajuntas'],
    description: 'Panel sándwich liso o microperfilado con fijación oculta para fachadas.',
    uses: ['cerramiento de nave', 'oficinas modulares', 'cámaras'],
    sizes: 'Espesor 40–100 mm.',
    weight: '≈ 12 kg/m²',
    kNm2: 0.12,
    look: MatLook(0.84, 0.85, 0.86, pattern: MatPattern.sandwich),
    photo: 'insulated sandwich panel facade walls',
    fichaText: 'panel sándwich',
  ),

  // ------------------------------------------------------------------ Vidrio
  BuildMaterial(
    id: 'vidrio-laminado',
    name: 'Vidrio laminado de seguridad',
    group: MatGroup.vidrio,
    aka: ['vidrio laminado', 'vidrio de seguridad', 'vidrio', 'cristal', 'cristales', 'vidrios', 'cristal laminado',
      'vidrio templado', 'cristal templado', 'butiral', 'stadip'],
    description: 'Dos o más vidrios unidos con lámina de butiral: si se rompe no se cae. Obligatorio en barandillas y '
        'cubiertas sobre zonas de paso.',
    uses: ['barandillas de vidrio', 'marquesinas de entrada', 'pérgolas acristaladas', 'claraboyas'],
    sizes: 'Barandilla 6+6 a 10+10 mm; cubierta 5+5 a 8+8 mm. Pinzas, perfil U de suelo o montantes.',
    weight: '6+6 ≈ 30 kg/m² (0,30 kN/m²)',
    kNm2: 0.30,
    look: MatLook(0.70, 0.85, 0.88, specular: 0.8, alpha: 0.30),
    photo: 'laminated safety glass panels',
    fichaText: 'vidrio laminado de seguridad',
  ),

  // ---------------------------------------------------- Rellenos de barandilla
  BuildMaterial(
    id: 'malla-electrosoldada',
    name: 'Malla electrosoldada / panel rígido',
    group: MatGroup.relleno,
    aka: ['malla electrosoldada', 'panel rigido', 'malla rigida', 'malla de varilla', 'mallazo', 'malla'],
    description: 'Paneles de varilla soldada en cuadrícula, galvanizados y plastificados.',
    uses: ['vallas de parcela', 'cerramientos industriales', 'cancelas ligeras'],
    sizes: 'Varilla Ø4–5 mm, cuadro 200x50 mm.',
    weight: '≈ 5 kg/m²',
    kNm2: 0.05,
    look: MatLook(0.55, 0.56, 0.57, specular: 0.2, alpha: 0.35),
    photo: 'welded wire mesh fence panels',
    fichaText: 'malla',
  ),
  BuildMaterial(
    id: 'malla-simple-torsion',
    name: 'Malla de simple torsión',
    group: MatGroup.relleno,
    aka: ['malla de simple torsion', 'simple torsion', 'malla ciclonica', 'malla gallinera', 'tela metalica'],
    description: 'Malla de alambre trenzado en rombo, tensada entre postes con alambre tensor.',
    uses: ['cercados rústicos y deportivos', 'vallas de obra'],
    sizes: 'Alambre Ø2–3 mm, rombo 50 mm.',
    weight: '≈ 1,5 kg/m²',
    kNm2: 0.02,
    look: MatLook(0.60, 0.61, 0.62, specular: 0.2, alpha: 0.25),
    photo: 'chain link wire fence',
    fichaText: 'malla',
  ),
  BuildMaterial(
    id: 'cables',
    name: 'Cable de acero inoxidable',
    group: MatGroup.relleno,
    aka: ['cable inox', 'cables', 'cable de acero', 'tensores', 'cables tensados'],
    description: 'Cables de inox tensados en horizontal entre montantes.',
    uses: ['barandillas de terraza de diseño', 'antepechos'],
    sizes: 'Ø4–6 mm a ≤ 10 cm, con tensores en cada tramo.',
    weight: 'Ø5 ≈ 0,1 kg/m',
    photo: 'horizontal stainless steel cables',
  ),
  BuildMaterial(
    id: 'barrotes',
    name: 'Barrotes',
    group: MatGroup.relleno,
    aka: ['barrotes', 'barrote', 'balaustres', 'barrotillos'],
    description: 'Barras verticales de tubo, cuadradillo o redondo a menos de 10 cm (CTE DB-SUA).',
    uses: ['barandillas', 'rejas', 'cancelas', 'vallas'],
    sizes: 'Tubo 20x20 o cuadradillo 12–16 mm, separación ≤ 10 cm.',
    weight: '≈ 10–15 kg/m de barandilla',
    photo: 'thin vertical steel bars',
  ),
];

/// Material por su id.
BuildMaterial? materialById(String id) {
  for (final m in materialCatalog) {
    if (m.id == id) return m;
  }
  return null;
}

/// Posición en [text] (ya normalizado) del primer sinónimo de [m], o -1.
int _findIn(BuildMaterial m, String text) {
  var best = -1;
  for (final a in m.aka) {
    final i = RegExp('(?<![a-z0-9])${RegExp.escape(a)}(?![a-z0-9])').firstMatch(text)?.start ?? -1;
    if (i >= 0 && (best < 0 || i < best)) best = i;
  }
  return best;
}

/// Longitud del sinónimo más largo de [m] que aparece en [text] (0 si ninguno).
int _matchLen(BuildMaterial m, String text) {
  var best = 0;
  for (final a in m.aka) {
    if (a.length > best && RegExp('(?<![a-z0-9])${RegExp.escape(a)}(?![a-z0-9])').hasMatch(text)) best = a.length;
  }
  return best;
}

/// Materiales que nombra [text], en el orden en que aparecen. Si dos se pisan
/// («policarbonato» y «policarbonato compacto») queda el nombre más largo.
List<BuildMaterial> materialsIn(String text, {Set<MatGroup>? groups}) {
  final t = normalize(text);
  final found = <(BuildMaterial, int, int)>[]; // material, posición, largo
  for (final m in materialCatalog) {
    if (groups != null && !groups.contains(m.group)) continue;
    final at = _findIn(m, t);
    if (at >= 0) found.add((m, at, _matchLen(m, t)));
  }
  // quita el genérico cuando un sinónimo más largo de otro material lo contiene
  final keep = found.where((f) {
    final mine = f.$1.aka.where((a) => RegExp('(?<![a-z0-9])${RegExp.escape(a)}(?![a-z0-9])').hasMatch(t));
    return !found.any((o) =>
        !identical(o.$1, f.$1) &&
        o.$3 > f.$3 &&
        mine.every((a) => o.$1.aka.any((b) => b.length > a.length && b.contains(a) && t.contains(b))));
  }).toList()
    ..sort((a, b) => a.$2.compareTo(b.$2));
  return [for (final f in keep) f.$1];
}

/// Material del catálogo que corresponde al texto de la ficha (spec.roofing,
/// spec.cladding…). Gana el sinónimo más largo.
BuildMaterial? materialFor(String fichaText, {Set<MatGroup>? groups}) {
  final t = normalize(fichaText);
  if (t.trim().isEmpty || t.contains('sin cubierta')) return null;
  BuildMaterial? best;
  var len = 0;
  for (final m in materialCatalog) {
    if (groups != null && !groups.contains(m.group)) continue;
    // el texto exacto de la ficha manda
    if (m.fichaText != null && normalize(m.fichaText!) == t.trim()) return m;
    final l = _matchLen(m, t);
    if (l > len) {
      len = l;
      best = m;
    }
  }
  return best;
}

/// Grupos que sirven como cubierta o suelo.
const roofGroups = {MatGroup.cubierta, MatGroup.suelo, MatGroup.vidrio, MatGroup.chapa};

/// Bloque de materiales citados en la petición para el LLM (vacío si no hay).
String materialsForLlm(String prompt, {int max = 4}) {
  final ms = materialsIn(prompt).take(max).toList();
  return ms.isEmpty ? '' : '\nMateriales citados:\n${ms.map((m) => '- ${m.llmLine}').join('\n')}';
}

/// Frase en inglés para la foto IA del material de [fichaText] (o null).
String? photoOf(String fichaText, {Set<MatGroup>? groups}) => materialFor(fichaText, groups: groups)?.photo;
