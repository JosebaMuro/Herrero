# Historial de versiones

## 3.4.0

- **Normativa de soldadura, herrería y calderería**: nueva pestaña «Normativa» en «Qué entiende
  Herrero» con unas 50 normas resumidas y buscables: CTE DB-SE-A y DB-SUA, Eurocódigo 3, EN 1090,
  procesos ISO 4063, símbolos ISO 2553, posiciones, preparación de bordes, cualificación de soldadores
  y procedimientos, niveles de calidad ISO 5817, ensayos (visual, penetrantes, partículas,
  ultrasonidos, radiografía), aceros y consumibles, galvanizado y pintura (ISO 1461, 12944, 9223),
  puertas EN 13241/12453, accesos ISO 14122 y calderería (equipos a presión, EN 13445, EN 14015,
  silos, bridas, fondos). Son resúmenes propios con la referencia de cada norma.
- **La descripción manda también en la soldadura**: entiende «soldado con TIG / hilo / electrodo /
  hilo tubular», «calidad B», «EXC3», «radiografiado», «ultrasonidos», «penetración completa»,
  «cordones continuos o discontinuos», «soldado en obra», «junto al mar», «piscina», «calderín a 8 bar»…
  - El proceso pedido pasa a la tabla de soldaduras con el consumible y el gas adecuados al material.
  - La clase de ejecución y el nivel de calidad salen en la memoria, el PDF y el cajetín de los planos.
  - Avisos de oficio: aluminio solo MIG/TIG, cordones discontinuos en exterior, ambiente costero
    (galvanizado o dúplex, inox 316), soldadura en obra, equipos a presión fuera de alcance, puertas
    motorizadas, partículas magnéticas en inox, etc.
  - Recomendaciones de taller en la memoria: venteos para galvanizar, decapado del inox…
- Cada proyecto muestra su **normativa aplicable** y el PDF añade la sección «Normativa de referencia».
- **Vocabulario**: unos 60 términos nuevos en «Procesos de soldadura», «Calidad, inspección y
  ensayos», «Herrería y forja» y «Calderería» (virola, tolva, brida, tubuladura, fondo Klöpper,
  mordedura, poro, saneado de raíz, voluta, garra…), y el diccionario corrige sus faltas.

## 3.3.1

- **Windows**: la foto realista, el lector de planos y la comprensión con IA local fallaban con
  «Load model from … failed. File doesn't exist» (la ruta salía en caracteres chinos). ONNX Runtime
  en Windows espera la ruta del modelo en UTF-16 y se le pasaba en UTF-8; ahora se pasa bien.

## 3.3.0

- **Diccionario de castellano**: entiende la petición aunque venga con faltas («escalra», «varandilla»,
  «canzela», «bentana», «yerro»), diminutivos («escalerita», «puertecita»), plurales, verbos y
  regionalismos. Avisa de lo que ha corregido y nunca toca palabras corrientes («plazas», «cuadrilla»,
  «cuatro»).
- **Vocabulario del oficio ampliado**: escaleras (zanca, peldaño, huella, tabica, mamperlán, meseta,
  descansillo), barandillas (pasamanos, balaustres, montantes, rodapié, guardacuerpos), rejas, vallas,
  cancelas, pérgolas, porches, altillos y desvanes, con sinónimos y formas coloquiales.
- Lo que se pide manda sobre el complemento: «escalera con barandilla» es una escalera y «plataforma
  para depósito» una torre.
- **Nuevas formas que la app calcula y dibuja**:
  - Escalera **en L** y **en U** con meseta de giro, de **zanca central** (tubo con ménsulas) y **de
    caracol** (mástil, peldaños en abanico, barandilla helicoidal y comprobaciones del CTE para uso
    restringido).
  - **Escala de gato** con jaula a partir de 3 m (EN ISO 14122-4).
  - Barandillas de **vidrio**, **cables**, **chapa perforada**, **lamas** o barras, con **rodapié** en
    zonas industriales, y aviso cuando el relleno es escalable.
  - **Pasamanos a pared** con soportes y anclajes, y segundo pasamanos para accesibilidad.
  - **Reja de ventana** con bastidor, barrotes a ≤ 10 cm y garras.
  - Perfiles nuevos: tubo redondo (CHS) y pletinas.
- En la ficha «Lo que he entendido» se elige la **forma** de la escalera, el **relleno** de la
  barandilla o el tipo de valla o reja.
- **Autocompletar** al escribir la petición: completa palabras y expresiones con tildes («escalera de
  car…» → «escalera de caracol»), corrige la palabra mal escrita y propone lo que suele seguir según
  la estructura.
- Glosario ampliado con todos estos términos y sus sinónimos.
- El título de la pantalla principal ya no se corta en móviles estrechos.

## 3.2.0

- **iPhone y iPad** (iOS 15 o posterior): nuevo `Herrero-ios.ipa` sin firmar en cada versión. Se
  instala gratis con Sideloadly o AltStore y un Apple ID normal (la firma dura 7 días). Incluye lo
  mismo que Android: cálculo, planos, exportación, importar plano con la cámara e IA local con ONNX
  Runtime 1.20.
- Los modelos IA quedan fuera de la copia de seguridad de iCloud.
- La carpeta Herrero con los ficheros exportados aparece en la app Archivos del iPhone.
- Pasos de instalación en el README, apartado «Instalar en iPhone gratis».

## 3.1.0

- **Comprensión de la petición**: antes de calcular, la app enseña la ficha «Lo que he entendido»
  (tipología, medidas, cubierta o suelo, sobrecarga, acero, acabado, ubicación y uso) con el origen de
  cada dato: de tu texto, deducido por oficio, leído por la IA, valor habitual o cambiado por ti. Toca
  un dato para corregirlo antes de calcular.
- **Razonamiento de oficio**: entiende para qué es la estructura aunque no traiga medidas. «Para 3
  coches» da 7,5 x 5 m y 2,5 m libres; «guardar el tractor», 4,2 m de altura; «cuadra para 10
  caballos», boxes en fila con pasillo; «pasar con carretillas», 2 m de paso y 5 kN/m². Cada número
  explica de dónde sale.
- **Tipología por finalidad**: «algo para subir al altillo» es una escalera, «que no se caigan los
  niños» una barandilla, «colgar un polipasto» un pórtico, «separar mi terreno del vecino» una valla.
- **IA local de comprensión**, descargable desde Modelos IA:
  - *Comprensión* (multilingual-e5-small, 118 MB): reconoce la tipología por el significado de la frase.
  - *Razonamiento* (Qwen3 0.6B, unos 620 MB): lee la petición y rellena la ficha en segundo plano.
    Solo se acepta lo que respalda tu texto; lo que la IA se inventa se descarta y se avisa.
  - Sin los modelos la app funciona igual, con las reglas del oficio.
- Números con letra («unos ocho metros», «cuatro alturas») y «7 metros libres» como altura.

## 3.0.1

- **Android: arreglada la descarga de modelos IA** (OCR, foto IA y visión IA). El APK no pedía el permiso
  de internet y todas las descargas fallaban en el móvil. La compilación comprueba ahora ese permiso.
- Si la conexión se corta o se cuelga (datos móviles), la descarga se reintenta sola y sigue donde se
  quedó. Mensajes de error claros (sin conexión, conexión segura, espacio libre).

## 3.0.0

- **Planos tipo CAD** en A3: cajetín ISO 7200, líneas normalizadas (gruesa, fina, trazos, trazo y punto),
  acotación ISO, alzados, planta, detalles de uniones con símbolos de soldadura ISO 2553 y despiece.
  Se ven en la pestaña Planos y se exportan a PDF vectorial (color o plotter en blanco y negro) y DXF R12.
- **Exportar el modelo 3D** a DXF (capas por función: pilares, vigas, correas, placas, cimentación,
  cubierta…) y a **SketchUp 2017** mediante COLLADA `.dae` (Archivo > Importar).
- **Render 3D refinado**: z-buffer por píxel y mapa de sombras. Solo policarbonato, vidrio y malla son
  translúcidos; se acabaron las transparencias y superposiciones falsas. Un único render de alta
  calidad a la vez para no saturar el móvil.
- **Visión IA local para croquis y planos sin texto**: SmolVLM 256M (móviles) o 500M (PC), descargable
  desde Modelos IA. Describe la tipología, las cotas escritas, los pilares y la cubierta, y lo traduce al
  vocabulario del oficio para completar el prompt.
- **ONNX Runtime 1.20** en Android y Windows (necesario para el VLM). La foto IA y el OCR siguen
  funcionando con el nuevo motor.
- **APK `arm64`** más ligero para móviles de 64 bits, además del APK universal.
- Revisión de código: análisis estático sin avisos, limpieza de código muerto y 101 pruebas.

## 2.0.0

- Catálogo de tipologías con descripción y vocabulario técnico del oficio.
- Catálogo de materiales (S235, S275, S355, corten, inoxidable, aluminio; acabados) y material por partes.
- Cubiertas y cerramientos con su peso propio (panel sándwich, chapa, policarbonato, teja, tramex…).
- Importar plano: PDF vectorial, PDF escaneado o foto, con OCR local y pantalla de revisión del prompt.
- Gestor de modelos IA y foto realista local (SD-Turbo int8 sobre el render 3D).

## 1.0.0

- Primera versión: predimensionado CTE DB-SE-A / EC3 a partir de lenguaje natural, despiece,
  chapas, tornillería y soldaduras, memoria de cálculo, vista isométrica y secuencia de montaje.
