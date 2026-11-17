import 'model.dart';

/// Peticiones de ejemplo, en lenguaje de la calle, para reconocer la
/// tipología por similitud de significado (embeddings). Se comparan con lo
/// que escribe el usuario: cuanto más variadas, mejor.
const typeIntents = <StructureType, List<String>>{
  StructureType.nave: [
    'nave industrial para almacenar material',
    'un almacén grande con tejado a dos aguas',
    'un taller cubierto para trabajar con maquinaria',
    'un hangar para guardar una avioneta',
    'un pabellón para el ganado en la granja',
    'edificio metálico con cerramiento de chapa y portón',
    'cubrir una zona grande para guardar cosechas y aperos',
  ],
  StructureType.marquesina: [
    'un techado para aparcar el coche',
    'una cubierta para dar sombra en la terraza',
    'una pérgola en el jardín',
    'un porche a la entrada de casa',
    'un cobertizo abierto para guardar el tractor',
    'tejadillo sobre la puerta para que no entre la lluvia',
    'una cubierta para placas solares sobre las plazas de parking',
  ],
  StructureType.entreplanta: [
    'un altillo dentro de la nave para oficinas',
    'un piso intermedio para ganar espacio de almacén',
    'una plataforma elevada para poner máquinas encima',
    'un forjado metálico entre dos plantas',
    'una plataforma en la cubierta para los equipos de aire acondicionado',
    'aprovechar la doble altura del local con una entreplanta',
  ],
  StructureType.escalera: [
    'una escalera para subir al altillo',
    'escalera de caracol para subir a la azotea',
    'unos peldaños metálicos para salvar un desnivel',
    'escalera exterior de emergencia',
    'acceso para subir a la primera planta por fuera',
    'escalera de servicio para llegar a la máquina',
  ],
  StructureType.pasarela: [
    'una pasarela para cruzar por encima de la carretera',
    'un puente para pasar andando sobre el río',
    'pasillo elevado entre dos naves',
    'pasarela de mantenimiento sobre las máquinas',
    'paso peatonal sobre una zanja',
  ],
  StructureType.barandilla: [
    'una barandilla para el balcón',
    'protección en el borde del altillo para que nadie se caiga',
    'pasamanos para la escalera',
    'antepecho de vidrio en la terraza',
    'barandilla de seguridad alrededor del foso',
  ],
  StructureType.cercha: [
    'cerchas metálicas para el tejado de la casa',
    'vigas de celosía para cubrir una luz grande',
    'estructura triangular para sostener la cubierta',
    'armadura de cubierta sobre muros de carga',
  ],
  StructureType.torre: [
    'un soporte elevado para el depósito de agua',
    'una torre para poner un tanque en alto',
    'una bancada para apoyar una máquina pesada',
    'mesa de trabajo metálica muy resistente',
    'castillete para una antena o un silo',
  ],
  StructureType.estanteria: [
    'estanterías para palets en el almacén',
    'baldas metálicas para guardar cajas',
    'un rack de carga de varios niveles',
    'estantería cantilever para barras y perfiles',
    'almacenaje en altura para la mercancía',
  ],
  StructureType.cancela: [
    'una puerta corredera para la entrada de la finca',
    'un portón abatible de dos hojas',
    'puerta para el garaje',
    'una cancela peatonal en la valla',
    'portón para que entren los camiones',
  ],
  StructureType.valla: [
    'cerrar la parcela con postes y malla',
    'una valla de barrotes alrededor de la casa',
    'un cerramiento de chapa para la obra',
    'rejas para las ventanas',
    'vallado perimetral de la finca',
  ],
  StructureType.portico: [
    'una estructura para colgar un polipasto',
    'grúa pórtico para levantar motores en el taller',
    'viga carril para mover cargas con un diferencial',
    'un pórtico para elevar piezas pesadas',
    'puente grúa para la nave',
  ],
  StructureType.poste: [
    'un poste para poner un cartel publicitario',
    'mástil para una bandera',
    'una farola o báculo de alumbrado',
    'soporte para un letrero en la carretera',
    'un poste para la antena',
  ],
};
