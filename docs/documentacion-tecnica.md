# Herrero · Documentación técnica (v4.3)

## 1. Visión general

App Flutter 3.50 (Dart 3) para Android, iOS, Windows y Linux. Todo el cálculo es local y
determinista (reglas + catálogos de perfiles); la IA local (ONNX Runtime 1.20) solo ayuda a
entender la petición, leer planos/facturas y generar la foto realista.

```
Texto / plano ──► parser + comprensión ──► StructureSpec (ficha)
                                              │
                                    designFromSpec()
                                              ▼
                     Design: barras, chapas, tornillos, soldaduras, comprobaciones,
                             montaje, normativa, despiece, plan de corte
                                              │
       ┌───────────────┬──────────────┬───────┴────────┬───────────────┐
   Pantallas      PDF por apartados   CAD (PDF/DXF)    Presupuesto     3D (DXF/DAE)
```

## 2. Estructura del código

| Carpeta | Contenido |
|---|---|
| `lib/engine/` | Motor: `parser.dart` (texto → ficha), `designer*.dart` (diseño por tipología), `profiles.dart` (catálogos y materiales), `cutting.dart` (optimizador de corte), `normativa.dart`, `bom.dart`, **`pricing.dart`**, **`invoice_parser.dart`**, **`budget.dart`**, **`spec_json.dart`** |
| `lib/cad/` | Láminas CAD (cajetín ISO 7200, cotas, soldadura ISO 2553), PDF vectorial, DXF R12, COLLADA |
| `lib/plans/` | Lector de PDF propio, OCR PP-OCRv4, análisis de planos |
| `lib/ai/` | Modelos locales: e5-small, Qwen3, jina-es, Qwen3-4B-Thinking, SmolVLM, SD-Turbo; aceleración (DirectML, CUDA, OpenVINO, NNAPI; `ort_core.dart` y `download.dart` en Dart puro, compartidos con la TUI; `comprehension_core.dart`); **`model_gate.dart`** |
| `lib/services/` | Exportación, **`project_store.dart`**, **`price_store.dart`**, **`geo.dart`**, **`sections_pdf.dart`** |
| `lib/screens/` | Pantallas; nuevas: `projects_screen.dart`, `prices_screen.dart`, `invoice_screen.dart`, `budget_tab.dart` |
| `linux/` | Ejecutable GTK (nuevo en 4.3) |
| `bin/herrero_tui.dart`, `lib/tui/` | TUI de terminal (Dart puro, sin Flutter), compilada con `scripts/build_tui.sh` |
| `lib/system/boot_mode.dart` | Cambio de arranque escritorio ↔ TUI (`herrero-modo`, pkexec) |
| `scripts/` | `instalar-ubuntu.sh` (instalador de Ubuntu en modo texto con NVIDIA), `build_tui.sh`, `ort_runtime.py` (cambia ORT 1.15 del paquete por 1.20 en cada plataforma), conversión de modelos |

## 3. Gestor de proyectos (`services/project_store.dart`)

- Carpeta `datos/proyectos/` dentro de `getApplicationSupportDirectory()`.
- Un subdirectorio por proyecto: `proyecto.json` (ficha `StructureSpec` serializada con
  `spec_json.dart`, texto pedido, cliente, obra, notas, estado, acabado, historial ≤ 200 apuntes,
  ajustes del presupuesto, total) y `foto.png` opcional.
- `index.json` con el resumen de todos (nombre, cliente, tipo, medidas, kg, total, estado, fechas):
  la lista no abre ningún proyecto. Si falta o está dañado, se reconstruye recorriendo las carpetas.
- Escrituras atómicas (`.tmp` + `rename`).
- El `Design` **no se guarda**: se recalcula con `designFromSpec` al abrir (pocos kB por proyecto y
  siempre con el motor vigente).

## 4. Precios (`engine/pricing.dart`)

### 4.1 Materiales normalizados
`parseMaterial(texto)` → `MaterialRef(familia, medida, aleación)` con clave estable:
`IPE 200`, `HEB 220`, `SHS 80x3`, `RHS 100x50x3`, `CHS 48,3x3`, `L 50x5`, `PLETINA 50x8`,
`REDONDO 16`, `CHAPA 10`, `TORNILLO M16`, `ANCLAJE M20`, `HILO`, `GALVANIZADO`, `SANDWICH`… con
prefijo `INOX`/`ALU` para inoxidable y aluminio. Reconoce las formas habituales de factura
(«VIGA IPE-200», «TUBO EST. 80X80X3», «80.40.2», «CHAPA LAM. 10MM 3000X1500», «DIN 931 M16X40 8.8»).
Cada familia pertenece a una categoría (laminado, tubo, chapa, tornillería, consumibles,
cerramientos, acabados).

### 4.2 Base de precios
`PriceBook` = proveedores (`Supplier`: nombre, CIF, dirección, coordenadas, teléfono, correo, web,
URL de tarifa, origen factura/mapa/manual) + precios (`PriceEntry`: proveedor, clave, unidad
€/kg·m·ud·m²·l, precio neto sin IVA, fecha, origen factura/tarifa/web/manual, documento). Se guarda
en `datos/precios.json`. Al añadir se deduplica (mismo proveedor, material, unidad y día) y se
conservan como mucho 6 precios por proveedor y material.

### 4.3 Búsqueda (`PriceBook.lookup`)
1. Filtra por antigüedad (`maxAgeMonths`) y por radio (haversine desde la ubicación; los
   proveedores sin coordenadas cuentan si `includeUnlocated`).
2. Busca por niveles: **exacto** (misma clave) → **familia** (otra medida, solo €/kg) →
   **categoría** (laminado/tubo/chapa, solo €/kg). El inoxidable y el aluminio nunca toman precios
   de acero al carbono.
3. Convierte €/m ↔ €/kg con el kg/m del perfil (corregido por densidad).
4. Toma el precio más reciente de cada proveedor y elige mediana, el más barato o el más reciente.
5. Devuelve `PriceQuote` con proveedor, distancia, nivel y nº de proveedores, para mostrar el origen.

## 5. Lectura de facturas (`engine/invoice_parser.dart`)

- Texto: PDF con texto → `PdfTextReader`; PDF escaneado o foto → rasterizado + OCR PP-OCRv4
  (`ModelGate.run(ModelTask.plans, …)`); los trozos se unen en líneas con `tokensToText`.
- Cabecera: CIF (`[A-W]\d{7}[0-9A-J]` o NIF), proveedor (primera línea con forma jurídica en el
  tercio superior que no sea del cliente), dirección (calle/polígono/CP), teléfono, correo, fecha
  (preferida la línea con «FECHA»), número de factura; detecta si es tarifa.
- Líneas: se prueban los 3 o 4 últimos números como cantidad, precio, (dto %), importe y solo se
  acepta si `cantidad × precio × (1 − dto) ≈ importe` (±1,5 %). Unidad por la palabra junto a la
  cantidad (KG, M, UD…). Tarifas: «descripción … precio €/unidad». Números en formato español o
  inglés (`parseNumber`).
- La pantalla de revisión permite corregirlo todo antes de guardar; la dirección se geocodifica
  con Nominatim para el filtro por radio.

## 6. Ubicación y distribuidores (`services/geo.dart`)

- Posición: `geolocator` (Android, iOS, Windows) + `geolocator_linux` (GeoClue por D-Bus), precisión
  baja y 20 s de límite; si falla, población escrita → Nominatim.
- Distribuidores: consulta Overpass (`distributorsQuery`) con `shop=trade` (metal, steel,
  building_supplies…), nombres de almacén de hierros/aceros/perfiles/ferralla/galvanizado en
  `shop`, `industrial`, `office=company`, `shop=wholesale`; `around` ≤ 150 km; tres servidores de
  respaldo. Resultado → `Supplier` con origen *mapa*. Atribución ODbL en la pantalla.
- Tarifa web: descarga la URL, quita el HTML (`htmlToText`) y la pasa por el lector de tarifas.
- Datos enviados: solo coordenadas o población, y las URL que el usuario pide leer. User-Agent
  genérico de la app.

## 7. Presupuesto (`engine/budget.dart`)

`buildBudget(design, book, query, rates, project:)` → `Budget` con `BudgetLine`s por apartado:

| Apartado | Cantidad | Precio |
|---|---|---|
| Materiales | kg comprados por perfil (`StockPlan.purchasedKg` × densidad), chapa por espesor +15 %, tornillos por ud, superficies de cubierta/cerramiento/tramex/vidrio +5 % (m²) | `PriceBook.lookup` |
| Fabricación | kg × h/kg | €/h taller |
| Soldadura | m de cordón × h/m; consumible kg | €/h; `HILO`/`ELECTRODO` |
| Acabados | galvanizado kg; pintura m² o litros (m² × manos ÷ rendimiento) | `GALVANIZADO`, `PINTURA` |
| Montaje | kg × h/kg | €/h montaje |

Precio fijado en el proyecto (`ProjectBudgetSettings.manualPrices[clave]`) > precio de la base >
sin precio. Totales: coste directo + extras (transporte, medios) + margen % = base; IVA aparte. Las
líneas sin precio no suman y se listan. `quoteRequestText` genera la petición de precio.
`WorkshopRates` (€/h, rendimientos, margen, IVA) y `GeoSettings` (ubicación, radio, antigüedad,
política) van en `SharedPreferences`.

## 8. Apartados imprimibles (`services/sections_pdf.dart`)

`ProjectSection`: resumen, cálculo, materiales, fabricación, soldadura, montaje, planos, presupuesto.
`buildSectionsPdf(design, secciones, …)` añade cada apartado como un `MultiPage` propio con
cabecera (apartado, proyecto, cliente, obra, «Para: destinatario») y pie con numeración del apartado
(se registra la primera y última página de cada uno durante la maquetación). Las láminas CAD se
reparten por título (`sheetsFor`). El render y la isométrica solo se generan si algún apartado
elegido los usa. `exportSections(separate: true)` genera un PDF por apartado, de uno en uno, para
no tener varios documentos en memoria. `buildPdf` (proyecto completo) usa todos los apartados.

## 9. Memoria y turnos de modelos (`ai/model_gate.dart`)

- Cada trabajo de IA abre su sesión ONNX en un isolate y la libera al terminar; el riesgo está en
  los trabajos que siguen en segundo plano (LLM de la ficha, visión, foto).
- `ModelGate`: `WorkflowStep` (inicio, comprensión, proyecto, planos, foto, facturas, presupuesto)
  con los modelos de cada paso (`stepTasks`). Modo `MemoryMode` automático (< 6 GB de RAM, leída de
  `/proc/meminfo` o del sistema), siempre o nunca, guardado en `ai.memoryMode`.
- En modo ahorro: `enter(paso)` cancela los trabajos de modelos que el paso no usa y llama a las
  funciones de `onDropCaches` (índice de embeddings, caché de imágenes); `hold(tarea, cancel)`
  registra trabajos largos y cancela los de otro modelo (uno cargado cada vez); `run(tarea, f)` pone
  en fila los trabajos cortos (OCR, embeddings).
- `main.dart`: caché de imágenes de 48 MB / 60 imágenes en móvil y 160 MB en escritorio, y vaciado de
  cachés en `didHaveMemoryPressure`.

### 9.1 Comprensión de la petición (`engine/comprehension_aids.dart`, `engine/understanding.dart`)

- Modelos: e5-small + Qwen3 0.6B (release `models-reason-v1`) o, como alternativa en castellano,
  jina-embeddings-v2-base-es + Qwen3-4B-Thinking q4 (release `models-reason-es-v1`, carpeta
  `reason-es`, `scripts/prepare_reason_es.py`). Elección en `ai.active.understand` /
  `ai.active.reason`. El 4B piensa 384 tokens empezando por `llmThinkStart` y luego se fuerza la ficha.
- Dos pasos: `readFacts` lee cifras con su sentido por reglas (luz → ancho, fondo → largo, alero,
  cumbrera, «a N m del suelo», kg/m², pendiente…); entran en la ficha como dato del texto y se pasan
  al LLM («Datos ya leídos por la app»), junto con el glosario de oficio (`glossaryFor`, que reutiliza
  `vocabulary.dart`).
- Ejemplos few-shot: `pickExamples` sobre `llmExamplePool` + correcciones guardadas
  (`ai/learned_examples.dart`, `learned_examples.json`, máx. 30), por parecido de embeddings
  (`ComprehensionEngine.examplesFor`) o por palabras sin modelo.
- `coherenceWarnings` y `clarifyingQuestions` dan los avisos y preguntas de la ficha; al calcular con
  la ficha corregida se guarda (petición, `fichaJson`) como ejemplo.
- Precedencia de los datos: usuario > texto > deducción de oficio > IA > valor habitual.

## 10. Plataformas, compilación y publicación

- `flutter pub get`, `python3 scripts/ort_runtime.py <android|windows|linux|ios>`, `flutter build …`.
- Linux: se compila en Ubuntu 22.04 (glibc 2.35) con `clang cmake ninja-build pkg-config
  libgtk-3-dev`; el paquete lleva `libonnxruntime` 1.20 con el nombre que espera el paquete pub
  (`libonnxruntime.so.1.15.1`), `herrero-tui` y el instalador. CUDA: paquete GPU descargable
  (ONNX Runtime 1.20.1 GPU, cudart, cuBLAS, cuDNN 9…) que se precarga al arrancar; al iniciar se
  despierta la gráfica (`nvidia-modprobe`, `cuInit`); `HERRERO_CUDA_MEM_MB` limita cada sesión.
- Permisos: Android `INTERNET`, `ACCESS_COARSE_LOCATION`, `ACCESS_FINE_LOCATION`; iOS
  `NSCameraUsageDescription`, `NSLocationWhenInUseUsageDescription`.
- CI (`.github/workflows/build.yml`): pruebas → Android (APK universal y arm64), Windows (instalador
  y portable), **Linux (tar.gz con app, TUI e instalador; la TUI se prueba en un pty)**, instalador en Ubuntu 24.04, iOS (IPA sin firmar). Un commit en `main` con `[release]` publica
  la release con binarios, manual de usuario, documentación técnica y `Herrero-codigo-fuente.zip`
  (`git archive`).

## 11. Pruebas

`flutter test` (incluye `test/tui_test.dart`, `accel_test`, `gpu_pack_test`). Nuevas en 4.3:
- `test/pricing_test.dart`: normalización de materiales, números, lectura de factura y tarifa,
  radio, conversión €/m↔€/kg, niveles de coincidencia, antigüedad, presupuesto sin inventar precios,
  almacén de proyectos (guardar, índice, duplicar, búsqueda, reconstrucción, borrado).
- `test/sections_test.dart`: cada apartado aislado con destinatario y numeración propia (leyendo el
  PDF generado), presupuesto con líneas sin precio, turnos de modelos, consulta y lectura de
  OpenStreetMap, texto de tarifas web.
