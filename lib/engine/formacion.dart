/// Formación reglada y acreditación profesional en calderería, soldadura y
/// estructuras metálicas en España, con enlaces a las fuentes oficiales.
///
/// Los textos son resúmenes propios orientativos: títulos de FP (TodoFP y
/// BOE), estándares de competencia del INCUAL, certificados profesionales
/// (SEPE), homologación del soldador (UNE-EN ISO 9606 y afines), diplomas
/// IIW/EWF (CESOL) y formación de prevención del convenio del metal. Las horas
/// y los módulos pueden variar por comunidad autónoma y por cambios
/// normativos: manda siempre la fuente enlazada.
library;

class SourceLink {
  final String label;
  final String url;
  const SourceLink(this.label, this.url);
}

class Training {
  /// Código oficial (título, cualificación, certificado o norma) o nombre corto.
  final String code;
  final String area;
  final String title;

  /// Nivel: «Grado medio», «Nivel 2», «MECU 5A»…
  final String level;

  /// Duración orientativa, vacía si no aplica.
  final String hours;
  final String summary;
  final List<String> points;
  final List<SourceLink> links;
  const Training(this.code, this.area, this.title, this.summary,
      {this.level = '', this.hours = '', this.points = const [], this.links = const []});
}

const trainingAreas = [
  'Dónde consultar: fuentes oficiales',
  'FP del sistema educativo',
  'Certificados profesionales (empleo)',
  'Cualificaciones del INCUAL',
  'Homologación del soldador',
  'Diplomas internacionales de soldadura',
  'Prevención y acreditación de la experiencia',
  'Universidad',
];

const _todofpFme = SourceLink('TodoFP · Fabricación Mecánica',
    'https://www.todofp.es/que-estudiar/familias-profesionales/fabricacion-mecanica.html');
const _incualFme =
    SourceLink('INCUAL · Fabricación Mecánica', 'https://incual.educacion.gob.es/mecanica_cualificaciones');
const _rd569 = SourceLink('BOE · RD 569/2023 (tres certificados de soldadura)',
    'https://www.boe.es/buscar/doc.php?id=BOE-A-2023-17166');
const _ley3 = SourceLink('BOE · Ley Orgánica 3/2022 de FP', 'https://www.boe.es/eli/es/lo/2022/03/31/3');
const _cesol = SourceLink('CESOL', 'https://cesol.es');
const _iiw = SourceLink('IIW · Cualificación de personal',
    'https://iiwelding.org/iiw-qualification-and-certification-of-personnel/');

String _cp(String code) => 'https://www.todofp.es/buscadorcertificados/fichaCP?codCertificado=$code';

final trainingLibrary = <Training>[
  // --- Fuentes oficiales ------------------------------------------------------
  const Training('TodoFP', 'Dónde consultar: fuentes oficiales', 'Portal de FP del Ministerio de Educación',
      'Repositorio oficial de los títulos de FP: plan de formación, requisitos de acceso, salidas, enlaces al '
          'real decreto y a los currículos de cada comunidad, suplementos Europass, buscador de centros y '
          'buscador de certificados profesionales.',
      points: [
        'Familia profesional «Fabricación Mecánica», área de construcciones metálicas.',
        'Desde cada ficha: Real Decreto, Currículo Ministerio, Currículos CCAA y Perfiles profesionales.',
      ],
      links: [_todofpFme, SourceLink('TodoFP · inicio', 'https://www.todofp.es')]),
  const Training('INCUAL', 'Dónde consultar: fuentes oficiales',
      'Instituto Nacional de las Cualificaciones: Catálogo Nacional de Estándares de Competencias Profesionales',
      'Publica las cualificaciones (FMExxx_n) con sus unidades o estándares de competencia (UCxxxx_n), que son '
          'la base común de los títulos de FP, los certificados profesionales y la acreditación de la experiencia.',
      links: [_incualFme]),
  const Training('SEPE', 'Dónde consultar: fuentes oficiales', 'Servicio Público de Empleo Estatal',
      'Fichas de los certificados de profesionalidad con sus módulos, horas, prácticas en empresa y requisitos '
          'del profesorado y de las instalaciones. La oferta de cursos la gestionan las comunidades autónomas '
          '(Lanbide en Euskadi, SEPE en Ceuta y Melilla…).',
      links: [
        SourceLink('SEPE', 'https://www.sepe.es'),
        SourceLink('SEPE · ejemplo de ficha (FMEC0110)',
            'https://sede.sepe.gob.es/es/portaltrabaja/resources/pdf/especialidades/FMEC0110.pdf'),
      ]),
  const Training('BOE', 'Dónde consultar: fuentes oficiales', 'Boletín Oficial del Estado',
      'Texto legal de cada título, currículo y certificado (reales decretos y órdenes), con versión consolidada '
          'cuando ha habido modificaciones. Es la fuente que manda ante cualquier duda.',
      links: [SourceLink('BOE · buscador de legislación', 'https://www.boe.es/buscar/legislacion.php'), _ley3]),
  const Training('Procomún', 'Dónde consultar: fuentes oficiales', 'Repositorio de recursos educativos abiertos (INTEF)',
      'Repositorio del Ministerio con materiales didácticos de libre uso (licencias Creative Commons) subidos por '
          'docentes y administraciones: busca «soldadura», «calderería» o «construcciones metálicas».',
      links: [SourceLink('Procomún', 'https://procomun.intef.es')]),
  const Training('RUCT', 'Dónde consultar: fuentes oficiales', 'Registro de Universidades, Centros y Títulos',
      'Registro oficial de los grados y másteres universitarios verificados: sirve para comprobar que una '
          'titulación universitaria es oficial.',
      links: [SourceLink('RUCT', 'https://www.educacion.gob.es/ruct/home')]),
  const Training('ESCO', 'Dónde consultar: fuentes oficiales', 'Clasificación europea de ocupaciones y capacidades',
      'Catálogo de la Comisión Europea con las ocupaciones (soldador, calderero, montador de estructuras metálicas, '
          'delineante de estructuras) y las capacidades que piden; útil para trabajar en otros países de la UE.',
      links: [SourceLink('ESCO', 'https://esco.ec.europa.eu/es')]),

  // --- FP del sistema educativo ----------------------------------------------
  const Training('FP Básica · Fabricación y Montaje', 'FP del sistema educativo',
      'Título Profesional Básico en Fabricación y Montaje',
      'Puerta de entrada al oficio para quien no ha terminado la ESO: operaciones básicas de fabricación, '
          'soldadura y carpintería metálica sencillas, carpintería de aluminio y PVC, y montajes de fontanería y '
          'climatización. Da acceso directo al grado medio.',
      level: 'Grado Básico',
      hours: '2000 h',
      points: [
        'Regulado en el Real Decreto 127/2014 (anexo III), actualizado en 2023 y 2024.',
        'Salidas: ayudante en talleres de soldadura, carpintería metálica y montaje de instalaciones.',
      ],
      links: [
        SourceLink('TodoFP · ficha del título',
            'https://www.todofp.es/que-estudiar/familias-profesionales/fabricacion-mecanica/fabricacion-montaje.html'),
        SourceLink('BOE · RD 127/2014 consolidado', 'https://www.boe.es/buscar/act.php?id=BOE-A-2014-2360'),
      ]),
  const Training('Técnico en Soldadura y Calderería', 'FP del sistema educativo',
      'Ciclo de grado medio de la familia Fabricación Mecánica',
      'El título del oficio: trazar, cortar, conformar, mecanizar, soldar con todos los procesos y montar '
          'calderería, carpintería metálica, estructuras y tubería, interpretando planos y con control de calidad.',
      level: 'Grado medio',
      hours: '2000 h',
      points: [
        'Módulos: 0007 Interpretación gráfica · 0091 Trazado, corte y conformado · 0092 Mecanizado · '
            '0093 Soldadura en atmósfera natural (oxigás y electrodo) · 0094 Soldadura en atmósfera protegida '
            '(TIG, MIG/MAG) · 0095 Montaje · 0006 Metrología y ensayos.',
        'Además: inglés profesional, itinerario para la empleabilidad, sostenibilidad, proyecto intermodular, '
            'módulo optativo de la comunidad y formación en empresa.',
        'Salidas: soldador, calderero, montador de estructuras metálicas, tubero industrial, carpintero metálico.',
        'Regulado en el Real Decreto 1692/2007; horas por módulo según el currículo de cada comunidad.',
      ],
      links: [
        SourceLink('TodoFP · ficha del título',
            'https://www.todofp.es/que-estudiar/familias-profesionales/fabricacion-mecanica/soldadura-caldereria.html'),
        SourceLink('BOE · RD 1692/2007', 'https://www.boe.es/buscar/doc.php?id=BOE-A-2008-820'),
      ]),
  const Training('Técnico Superior en Construcciones Metálicas', 'FP del sistema educativo',
      'Ciclo de grado superior de la familia Fabricación Mecánica',
      'Oficina técnica de calderería y estructura: diseñar y calcular productos de construcciones metálicas, '
          'preparar la documentación y los planos de fabricación, definir procesos de fabricación y montaje, '
          'supervisar la programación de CNC y robots y programar la producción.',
      level: 'Grado superior · MECU 5A',
      hours: '2000 h',
      points: [
        'Módulos: Representación gráfica en fabricación mecánica · Diseño de construcciones metálicas · '
            'Definición de procesos de construcciones metálicas · Programación de sistemas automáticos · '
            'Programación de la producción · Procesos de mecanizado, corte y conformado · Procesos de unión y '
            'montaje · Gestión de la calidad, prevención y medio ambiente · Proyecto intermodular.',
        'Salidas: delineante proyectista y CAD de calderería y estructuras, técnico de procesos, jefe de taller '
            'o de montaje, desarrollo de tubería.',
        'Sigue con los cursos de especialización de Fabricación aditiva o BIM, o con un grado universitario '
            'de ingeniería con convalidaciones.',
        'Regulado en el Real Decreto 174/2008 (modificado por el RD 500/2024); currículo del Ministerio de 2009.',
      ],
      links: [
        SourceLink('TodoFP · ficha del título',
            'https://www.todofp.es/que-estudiar/familias-profesionales/fabricacion-mecanica/construcciones-metalicas.html'),
        SourceLink('BOE · RD 174/2008', 'https://www.boe.es/buscar/doc.php?id=BOE-A-2008-3867'),
        SourceLink('BOE · modificación RD 500/2024', 'https://www.boe.es/eli/es/rd/2024/05/21/500'),
        SourceLink('BOE · currículo del Ministerio', 'https://www.boe.es/buscar/doc.php?id=BOE-A-2009-13339'),
        SourceLink('Centros que lo imparten', 'https://www.educacion.gob.es/centros/buscarCentros?ensenanzaFP=122_0802'),
      ]),
  const Training('Otros ciclos relacionados', 'FP del sistema educativo', 'Fabricación Mecánica: diseño, producción y mecanizado',
      'Para la oficina técnica también encajan los grados superiores de Diseño en Fabricación Mecánica (planos y '
          'cálculo de piezas y utillajes) y de Programación de la Producción en Fabricación Mecánica; en taller, '
          'el grado medio de Mecanizado. Todos están en la familia Fabricación Mecánica de TodoFP.',
      links: [_todofpFme]),
  const Training('Cursos de especialización', 'FP del sistema educativo', 'Tras un grado superior',
      'Formación corta de especialización para titulados de grado superior. Desde Construcciones Metálicas, '
          'TodoFP indica los de Fabricación aditiva y de Modelado de la información en la construcción (BIM).',
      level: 'Grado E',
      links: [
        SourceLink('TodoFP · CE Fabricación aditiva',
            'https://www.todofp.es/que-estudiar/familias-profesionales/fabricacion-mecanica/ce-fabricacion-aditiva.html'),
        SourceLink('TodoFP · CE BIM',
            'https://www.todofp.es/que-estudiar/familias-profesionales/instalacion-mantenimiento/ce-modelado-informacion-construccion.html'),
      ]),

  // --- Certificados profesionales ---------------------------------------------
  const Training('Grados A–E (Ley 3/2022)', 'Certificados profesionales (empleo)', 'Cómo se ordena hoy la FP',
      'La Ley Orgánica 3/2022 une la FP del sistema educativo y la de empleo en un único sistema por grados: '
          'A (acreditación parcial de competencia), B (certificado de competencia), C (certificado profesional, '
          'el antiguo certificado de profesionalidad), D (ciclos formativos) y E (cursos de especialización).',
      points: [
        'Los certificados antiguos que se derogan tienen equivalencia con los nuevos y se pueden acreditar de oficio.',
        'Lo cursado en un grado se reconoce en los siguientes: los módulos se acumulan hacia el título.',
      ],
      links: [_ley3]),
  Training('FMEC0119_2', 'Certificados profesionales (empleo)',
      'Soldadura por arco bajo gas protector con electrodo consumible, soldeo «MIG/MAG»',
      'Certificado profesional de soldador de hilo: preparar, puntear y soldar chapas, perfiles y tubos de acero '
          'al carbono, inoxidable y aluminio con MIG/MAG según WPS, en distintas posiciones, con control visual del cordón.',
      level: 'Nivel 2',
      points: const [
        'Cualificación de referencia: FME684_2.',
        'Sustituye, junto con los dos siguientes, a los antiguos FMEC0110 y FMEC0210.',
      ],
      links: [_rd569, SourceLink('TodoFP · ficha', _cp('FMEC0119_2'))]),
  Training('FMEC0219_2', 'Certificados profesionales (empleo)',
      'Soldadura por arco bajo gas protector con electrodo no consumible, soldeo «TIG»',
      'Certificado profesional de soldador TIG: soldeo de acero al carbono, inoxidable y aluminio en chapa y tubo, '
          'con y sin aporte, protección del reverso y control de la deformación.',
      level: 'Nivel 2',
      points: const ['Cualificación de referencia: FME685_2.'],
      links: [_rd569, SourceLink('TodoFP · ficha', _cp('FMEC0219_2'))]),
  Training('FMEC0319_2', 'Certificados profesionales (empleo)', 'Soldadura por arco con electrodo revestido',
      'Certificado profesional de soldador de electrodo: soldeo de chapa, perfiles y tubo de acero al carbono e '
          'inoxidable en taller y obra, elección del electrodo, conservación y secado de consumibles.',
      level: 'Nivel 2',
      points: const ['Cualificación de referencia: FME686_2.'],
      links: [
        _rd569,
        SourceLink('TodoFP · ficha', _cp('FMEC0319_2')),
        const SourceLink('Lanbide · ficha', 'https://web.lanbide.eus/descargas/egailancas/certificados/ficha/FMEC0319_FIR.pdf'),
      ]),
  Training('FMEC0110 y FMEC0210 (derogados)', 'Certificados profesionales (empleo)',
      'Soldadura con electrodo revestido y TIG · Soldadura oxigás y MIG/MAG',
      'Los certificados de soldadura anteriores (680 h y 600 h). Quien los tenga conserva su valor: FMEC0110 '
          'equivale a FMEC0319_2 (electrodo) y FMEC0219_2 (TIG), y FMEC0210 a FMEC0119_2 (MIG/MAG).',
      level: 'Nivel 2',
      links: [
        SourceLink('TodoFP · FMEC0110', _cp('FMEC0110')),
        const SourceLink('SEPE · ficha FMEC0210',
            'https://www.sepe.es/SiteSepe/contenidos/personas/formacion/certificados_de_profesionalidad/pdf/fichasCertificados/FMEC0210_ficha.pdf'),
      ]),
  Training('FMEC0108', 'Certificados profesionales (empleo)', 'Fabricación y montaje de instalaciones de tubería industrial',
      'Calderero-tubero: trazar, cortar, curvar, preparar y montar tuberías y accesorios, con pruebas de presión y estanqueidad.',
      level: 'Nivel 2',
      hours: '530 h',
      points: const ['Cualificación de referencia: FME351_2.'],
      links: [SourceLink('TodoFP · ficha', _cp('FMEC0108'))]),
  Training('FMEC0109', 'Certificados profesionales (empleo)', 'Producción en construcciones metálicas',
      'Mando intermedio de taller: planificar y lanzar la fabricación y el montaje de calderería y estructura, '
          'aprovisionamiento, costes y control de la calidad de producción.',
      level: 'Nivel 3',
      hours: '490 h',
      points: const ['Cualificación de referencia: FME357_3.'],
      links: [SourceLink('TodoFP · ficha', _cp('FMEC0109'))]),
  Training('FMEC0208', 'Certificados profesionales (empleo)', 'Diseño de calderería y estructuras metálicas',
      'Oficina técnica: diseñar productos de calderería y estructura a partir de anteproyectos, calcularlos, hacer '
          'planos de conjunto y despiece y la documentación técnica de fabricación.',
      level: 'Nivel 3',
      hours: '660 h',
      points: const ['Cualificación de referencia: FME354_3. Es el certificado más cercano a lo que hace esta app.'],
      links: [SourceLink('TodoFP · ficha', _cp('FMEC0208'))]),
  Training('FMEC0209', 'Certificados profesionales (empleo)', 'Diseño de tubería industrial',
      'Diseño de redes de tubería: esquemas, trazado, isométricas, soportes, selección de materiales y cálculo básico.',
      level: 'Nivel 3',
      hours: '480 h',
      points: const ['Cualificación de referencia: FME355_3.'],
      links: [SourceLink('TodoFP · ficha', _cp('FMEC0209'))]),
  Training('FMEC0309', 'Certificados profesionales (empleo)', 'Diseño en la industria naval',
      'Desarrollo de estructura y armamento de buques: formas, planos de construcción y despiece de bloques.',
      level: 'Nivel 3',
      hours: '640 h',
      links: [SourceLink('TodoFP · ficha', _cp('FMEC0309'))]),

  // --- Cualificaciones INCUAL ---------------------------------------------------
  const Training('FME035_2', 'Cualificaciones del INCUAL', 'Soldadura',
      'Cualificación clásica del soldador con todos los procesos manuales.',
      level: 'Nivel 2',
      points: [
        'UC0098_2 Soldaduras y proyecciones térmicas por oxigás · UC0099_2 Soldaduras con arco y electrodo '
            'revestido · UC0100_2 Soldaduras con arco bajo gas protector y electrodo no consumible (TIG) · '
            'UC0101_2 Soldaduras con arco bajo gas protector y electrodo consumible (MIG/MAG).',
      ],
      links: [_incualFme]),
  const Training('FME684_2 · FME685_2 · FME686_2', 'Cualificaciones del INCUAL', 'Soldadura MIG/MAG · TIG · electrodo revestido',
      'Cualificaciones nuevas, una por proceso, en las que se basan los certificados FMEC0119_2, FMEC0219_2 y FMEC0319_2.',
      level: 'Nivel 2',
      links: [_incualFme]),
  const Training('FME350_2', 'Cualificaciones del INCUAL', 'Calderería, carpintería y montaje de construcciones metálicas',
      'Fabricar elementos de calderería, carpintería metálica y estructura (trazado, corte, conformado y unión) y '
          'montarlos en taller y obra. Se obtiene, sobre todo, con el título de Técnico en Soldadura y Calderería.',
      level: 'Nivel 2',
      links: [_incualFme]),
  const Training('FME351_2', 'Cualificaciones del INCUAL', 'Fabricación y montaje de instalaciones de tubería industrial',
      'Tubería industrial: preparación, montaje y pruebas. Certificado asociado FMEC0108.',
      level: 'Nivel 2',
      links: [_incualFme]),
  const Training('FME354_3', 'Cualificaciones del INCUAL', 'Definición de productos de calderería y estructuras metálicas',
      'Diseño y documentación técnica de calderería y estructura. Certificado asociado FMEC0208.',
      level: 'Nivel 3',
      links: [_incualFme]),
  const Training('FME355_3', 'Cualificaciones del INCUAL', 'Diseño de tubería industrial',
      'Diseño de redes de tubería. Certificado asociado FMEC0209.',
      level: 'Nivel 3',
      links: [_incualFme]),
  const Training('FME357_3', 'Cualificaciones del INCUAL', 'Producción en construcciones metálicas',
      'Planificación y control de la producción de calderería y estructura. Certificado asociado FMEC0109.',
      level: 'Nivel 3',
      links: [_incualFme]),

  // --- Homologación del soldador -------------------------------------------------
  const Training('UNE-EN ISO 9606-1', 'Homologación del soldador', 'Cualificación de soldadores: aceros',
      'La «homologación» que pide un taller con marcado CE (EN 1090-2) o un cliente: el soldador suelda una '
          'probeta según una WPS y un examinador u organismo de certificación la ensaya y emite el certificado.',
      points: [
        'El certificado vale solo para su rango: proceso, chapa o tubo, a tope o en ángulo, grupo de material, '
            'consumible, espesor, diámetro y posiciones.',
        'Ensayos: inspección visual y, según la probeta, rotura, doblado, macrografía o radiografía.',
        'El coordinador del soldeo confirma cada 6 meses que el soldador sigue trabajando en ese rango; la '
            'revalidación se hace por una de las tres vías de la norma (nuevo ensayo cada 3 años, o cada 2 '
            'años o de forma continua con ensayos de producción).',
        'Otras partes: ISO 9606-2 aluminio, -3 cobre, -4 níquel, -5 titanio y circonio.',
      ],
      links: [SourceLink('ENAC · entidades de certificación acreditadas', 'https://www.enac.es')]),
  const Training('UNE-EN ISO 14732', 'Homologación del soldador', 'Operadores de soldeo mecanizado y robotizado',
      'Cualificación de quien maneja y ajusta equipos de soldeo automático, mecanizado o robots.'),
  const Training('UNE-EN ISO 14731', 'Homologación del soldador', 'Coordinación del soldeo',
      'Tareas y responsabilidades del coordinador del soldeo del taller. EN 1090-2 exige un coordinador con '
          'conocimientos técnicos acordes a la clase de ejecución; en la práctica se acreditan con los diplomas '
          'IWE, IWT o IWS.'),
  const Training('UNE-EN ISO 9712', 'Homologación del soldador', 'Personal de ensayos no destructivos',
      'Certificación de inspectores de END (visual, líquidos penetrantes, partículas magnéticas, ultrasonidos, '
          'radiografía) en niveles 1, 2 y 3. Es la que se pide a quien firma los ensayos de los cordones.'),
  const Training('ASME IX · AWS D1.1', 'Homologación del soldador', 'Homologaciones para proyectos internacionales',
      'En calderería a presión con código ASME o en estructura con código americano se piden homologaciones '
          'según ASME sección IX o AWS D1.1, que no son equivalentes a las ISO.'),

  // --- Diplomas internacionales ---------------------------------------------------
  const Training('IIW / EWF', 'Diplomas internacionales de soldadura', 'Diplomas armonizados del Instituto Internacional de Soldadura',
      'Formación no reglada pero con reconocimiento internacional. En España la imparte y certifica CESOL '
          '(Asociación Española de Soldadura y Tecnologías de Unión), miembro del IIW.',
      points: [
        'IWE Ingeniero · IWT Técnico · IWS Especialista · IWP Practicante: coordinación del soldeo.',
        'IW Soldador internacional: por procesos y por tipo de producto.',
        'IWI Inspector internacional de soldadura.',
      ],
      links: [_cesol, _iiw]),

  // --- Prevención y acreditación ------------------------------------------------------
  const Training('Convenio del Metal: TPC y TPM', 'Prevención y acreditación de la experiencia',
      'Formación de prevención por oficio',
      'El Convenio Colectivo Estatal del Sector del Metal obliga a una formación de prevención según el puesto. '
          'Para trabajar en obras de construcción se acredita con la Tarjeta Profesional de la Construcción del '
          'Metal (TPC) y fuera de obras con la Tarjeta Profesional del Metal (TPM), ambas de la Fundación del Metal.',
      points: [
        'Hay módulos específicos para soldadura y para montaje de estructuras metálicas; la duración la fija el convenio.',
      ],
      links: [SourceLink('Fundación del Metal (FMF)', 'https://www.fmfce.com/')]),
  const Training('Acreditación de competencias', 'Prevención y acreditación de la experiencia',
      'Reconocer la experiencia laboral sin volver a estudiar',
      'Quien ya trabaja de soldador o calderero sin título puede acreditar sus estándares de competencia (UC) '
          'por experiencia o formación no formal. Con la Ley 3/2022 el procedimiento está abierto todo el año y lo '
          'gestionan las comunidades autónomas; las unidades acreditadas cuentan para el certificado y el título.',
      links: [_ley3, _incualFme]),

  // --- Universidad -----------------------------------------------------------------
  const Training('Grados de ingeniería', 'Universidad', 'Ingeniería mecánica, industrial y civil',
      'El cálculo y la firma de proyectos de estructura metálica corresponden a ingenieros y arquitectos. Los '
          'grados de Ingeniería Mecánica, Tecnologías Industriales o Civil (MECU 6) y el máster de Ingeniería '
          'Industrial (MECU 7) incluyen estructuras de acero y tecnología de la soldadura.',
      points: ['Desde el grado superior de Construcciones Metálicas se accede con posibles convalidaciones.'],
      links: [SourceLink('RUCT · títulos oficiales', 'https://www.educacion.gob.es/ruct/home')]),
];
