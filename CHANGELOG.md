# Historial de versiones

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
