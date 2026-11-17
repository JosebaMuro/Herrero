# Herrero · Oficina técnica de estructuras metálicas

App ligera para **Android y Windows** que, a partir de una descripción en lenguaje natural
("nave a dos aguas de 30 x 15 m, 6 m al alero, panel sándwich, en Vitoria"), predimensiona la
estructura según **CTE DB-SE-A / Eurocódigo 3** y genera:

- **Despiece** con marcas, perfiles, longitudes, cantidades, pesos y optimización de barras comerciales.
- **Chapas, tornillería y soldaduras** (garganta, longitud, proceso, consumible estimado).
- **Memoria de cálculo** con hipótesis, cargas y comprobaciones (aprovechamiento η).
- **Vista isométrica** y **secuencia de montaje**.
- **Planos tipo CAD** en A3: cajetín ISO 7200, líneas normalizadas, acotación ISO, alzados, planta,
  detalles de uniones con símbolos de soldadura ISO 2553 y despiece. Exportables a **PDF vectorial**
  (color o plotter) y **DXF**.
- **Modelo 3D** exportable a **DXF** y a **SketchUp 2017** (COLLADA .dae: Archivo > Importar).
- **Render 3D** con z-buffer y sombras, y **foto realista con IA local** (sin internet).
- **Importar plano**: PDF de CAD, PDF escaneado, foto o croquis a mano (OCR y visión IA locales).

## Novedades de la v3.1

- Ficha «Lo que he entendido» antes de calcular: tipología, medidas y materiales con el origen de cada
  dato (de tu texto, deducido, leído por la IA, valor habitual o cambiado por ti), editable.
- Razonamiento de oficio: «para 3 coches», «guardar el tractor», «cuadra para 10 caballos», «pasar con
  carretillas»… dan medidas y cargas razonadas aunque no escribas números.
- IA local de comprensión (multilingual-e5-small) y de razonamiento (Qwen3 0.6B), descargables desde
  Modelos IA. La IA solo aporta lo que respalda tu texto; sin modelos funciona igual con las reglas.

## Novedades de la v3

- Planos tipo CAD (pestaña Planos, PDF del proyecto y menú Exportar) y exportación DXF.
- Exportación del modelo 3D a DXF y a SketchUp 2017.
- Render 3D refinado: z-buffer por píxel y mapa de sombras; solo policarbonato, vidrio y malla son translúcidos.
- Visión IA local para croquis (SmolVLM 256M en móvil, 500M en PC), descargable desde Modelos IA.
- Motor ONNX Runtime 1.20, revisión de código y APK `arm64` más ligero para móviles actuales.
- 3.0.1: arreglada la descarga de modelos IA en Android (faltaba el permiso de internet); las descargas
  se reintentan solas y siguen donde se quedaron. Historial completo en [CHANGELOG.md](CHANGELOG.md).

> ⚠️ Los resultados son un **predimensionado orientativo**. Deben ser revisados y firmados por un técnico competente antes de fabricar o montar.

## Descargas

Los binarios se generan con GitHub Actions y se publican en *Releases*:
- `Herrero-android-arm64.apk` — Android de 64 bits (casi todos los móviles desde 2017), más ligero.
- `Herrero-android.apk` — Android universal (también móviles antiguos de 32 bits).
- `Herrero-windows-setup.exe` — instalador para Windows 10/11 x64.
- `Herrero-windows-portable.zip` — versión portable (descomprimir y ejecutar `herrero.exe`).

## Tipos de estructura soportados

| Tipo | Palabras clave |
|---|---|
| Nave de pórticos a dos aguas | nave, pórtico, almacén, taller, hangar |
| Marquesina / pérgola / cobertizo | marquesina, pérgola, porche, carport, cochera |
| Entreplanta / altillo | altillo, entreplanta, plataforma, forjado |
| Escalera, pasarela, barandilla | escalera, zanca, pasarela, barandilla, pasamanos |
| Cercha, torre, estantería | cercha, celosía, torre, estantería, rack |
| Cancela, valla, pórtico, poste | cancela, puerta, valla, pórtico, poste, báculo |

## Desarrollo

```
flutter pub get
flutter test
flutter run -d windows   # o un dispositivo Android
```
