# Historial de versiones

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
