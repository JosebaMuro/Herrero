# Historial de versiones

## 4.3.0-e (sin publicar)

- **FreeLLMAPI integrado** ([tashfeenahmed/freellmapi](https://github.com/tashfeenahmed/freellmapi),
  MIT): los paquetes de Windows, Linux x64/ARM64 y Android traen FreeLLMAPI con su Node.js, y Herrero
  lo arranca solo en 127.0.0.1 para razonar la ficha con los planes gratis de muchos proveedores. Sin
  cuenta ni contraseña: la clave unificada se saca sola; botón para abrir su panel y añadir claves.
- **Ajustes → Endpoint de IA**: integrado o externo (FreeLLMAPI de otro equipo, pasarela de Infinito /
  9000 tokens, cualquier servidor OpenAI): URL, clave, modelo (`auto`), detección de Infinito,
  **Probar conexión** y vuelta al modelo local si falla. La IA local sigue igual.

## 4.3.0-d (2026-11-26)

- **Catálogo de materiales** (`engine/material_catalog.dart`): 36 materiales con sinónimos y
  regionalismos (calaminón, calamina, onduline, chapa estriada, policarbonato alveolar, llanta,
  IPN…), usos, medidas, pesos, aspecto de render y frase para la foto IA. Pestaña *Materiales* con
  buscador. Cubiertas nuevas: chapa ondulada, placa asfáltica ondulada, policarbonato compacto.
- **Comprensión**: las secciones de perfil («llanta de 30x5 mm», «tubo 80x80», «170 mm de llanta»)
  ya no se leen como medidas de la estructura; la IA recibe «Materiales citados» y las secciones
  marcadas; «4 m de hueco», «a 2,8 m» (altillos), rejas «ancho x alto», «listones horizontales».
  Banco de 42 descripciones: 92,8 % → 100 % de datos bien.
- **Barandilla sobre el peto** del balcón: montantes de llanta en U invertida, listones horizontales
  y soporte de tiestos, con el peto dibujado en el render.

## 4.3.0 (2026-11-24)

- **Gestor de proyectos**: guardar el proyecto (nombre, cliente, obra, notas), abrirlo, duplicarlo,
  borrarlo, buscarlo y cambiar su estado (borrador, presupuestado, aceptado, en fabricación, en
  montaje, terminado, descartado). Cada proyecto lleva su historial. Se guarda solo la ficha y el
  texto pedido (unos kB) y el diseño se recalcula al abrir; la foto IA se guarda aparte.
- **Presupuesto** (pestaña nueva): materiales según las barras del plan de corte, chapa con un 15 %
  de recortes, tornillería y cerramientos; horas de fabricación, soldadura y montaje con tus
  precios por hora y rendimientos ajustables; galvanizado o pintura; transporte, margen e IVA. Cada
  línea dice de dónde sale su precio (factura, tarifa, web o fijado a mano, con proveedor, fecha y
  distancia) y las que no tienen precio se marcan y no suman. PDF para el cliente o con detalle.
- **Base de precios**: importar facturas y tarifas en PDF o foto (OCR local), con proveedor, CIF,
  dirección, fecha, nº de factura y líneas con material reconocido (IPE, HEB, tubo, chapa,
  tornillería, hilo, galvanizado…) y precio unitario neto con descuento. Solo se aceptan líneas en
  las que cantidad × precio cuadra con el importe; todo se revisa antes de guardar.
- **Ubicación y radio**: GPS (Android, Windows, Linux con GeoClue, iPhone) o población escrita; el
  presupuesto solo usa proveedores dentro del radio y precios de los últimos meses elegidos, con
  mediana, el más barato o el más reciente.
- **Distribuidores cercanos** desde OpenStreetMap, con teléfono, web y correo cuando los hay;
  «Pedir precio» abre un correo o SMS con el pedido de material del proyecto, y se pueden leer los
  precios de la página de tarifas de un distribuidor si la publica.
- **Apartados aislados**: resumen, cálculo, materiales, fabricación, soldadura, montaje, planos y
  presupuesto, cada uno con su cabecera, su destinatario y su numeración; en un PDF o uno por
  apartado.
- **Memoria**: con menos de 6 GB de RAM (o si se elige en Modelos), los modelos de IA se cargan por
  turnos según el paso del flujo (ficha, planos, foto, facturas): al cambiar de paso se cancelan los
  que no tocan y se sueltan las cachés. Caché de imágenes limitada en el móvil y vaciado al avisar
  el sistema de poca memoria. Los PDF por apartado solo generan las imágenes que usan.
- **Linux** (x86-64, Ubuntu 22.04 LTS o posterior): app de escritorio y **TUI de terminal**
  (`herrero-tui`) en `Herrero-linux-x64.tar.gz`, con ONNX Runtime 1.20.
- **TUI de terminal**: petición en lenguaje natural, ficha «Lo que he entendido» con el origen de
  cada dato, resultado por pestañas (resumen, despiece, comprobaciones con barras de η, uniones,
  montaje, normativa) y exportación a CSV, DXF y memoria en Markdown. Pantalla «IA y GPU»
  (Ctrl+G): motor, paquete CUDA, descarga de modelos y prueba de velocidad CPU frente a GPU.
  También sin pantalla: `herrero-tui --calcular "…"`, `--gpu`, `--instalar-cuda`.
- **NVIDIA CUDA en Linux** (p. ej. RTX 4050 Laptop de 6 GB): paquete descargable con ONNX
  Runtime 1.20.1 GPU y las librerías de NVIDIA (cudart, cuBLAS, cuFFT, cuRAND, NVRTC, cuDNN 9),
  que se precargan al arrancar porque LD_LIBRARY_PATH no puede cambiarse con el proceso en marcha.
  Funciona sin escritorio (modo texto).
- **La gráfica NVIDIA se despierta al arrancar** (Linux): si faltan `nvidia_uvm` o
  `/dev/nvidia-uvm` (sin escritorio nadie los crea) se crean con `nvidia-modprobe`, y `cuInit`
  saca la gráfica del reposo antes de la primera petición. Si no se puede, se avisa con los
  comandos exactos para arreglarlo y la IA sigue en CPU.
- CUDA afinado para gráficas de poca memoria: reserva que crece solo lo pedido, cuDNN por
  heurística y sin espacio de trabajo máximo (`HERRERO_CUDA_MEM_MB` limita cada sesión).
- DirectML (Windows) elige la gráfica de **alto rendimiento** en portátiles con dos gráficas
  (antes podía usar la integrada).
- `scripts/instalar-ubuntu.sh`: instala Herrero en Ubuntu LTS con el controlador NVIDIA headless,
  arranque sin X11 e inicio de sesión automático en tty1 que abre la TUI. Con `--preparar` deja en
  una carpeta o USB todo lo necesario (`.deb` del controlador y del firmware, paquete CUDA,
  modelos) para instalar **sin conexión** con `--desde`.
- **Cambiar de modo y reiniciar**: en la TUI, Ctrl+R (o «r» en «IA, GPU y sistema») reinicia con el
  escritorio (X11); en la app de escritorio de Linux, el botón de terminal reinicia en modo TUI.
  El instalador deja `herrero-modo` y una regla de sudo para hacerlo sin contraseña (si falta, la
  app la pide con pkexec y la TUI muestra el comando).
- La release incluye manual de usuario, documentación técnica y código fuente.

## 4.2.0 (2026-11-20)

- **Gestor de modelos de IA** renovado: tarjeta «Instalados» con lo que ocupa cada modelo y el
  total, cuál está en uso, con qué motor se ejecuta, si se importó a mano y las descargas a medias
  (con su tamaño, para reanudarlas o borrarlas). Usar o eliminar cada modelo desde ahí.
- Con varios modelos de visión de croquis instalados (SmolVLM 256M y 500M) se elige cuál usar,
  igual que en la foto IA.
- **Motor de inferencia según el hardware, por tarea**: la app detecta el equipo (gráficas en
  Windows; versión de Android y chip del móvil) y elige para cada tarea CPU, NNAPI, DirectML, CUDA
  u OpenVINO, explicando por qué. Se puede fijar a mano para una tarea concreta (p. ej. solo CPU
  para el razonamiento) sin tocar el resto. Avisa si una NVIDIA o Intel iría más rápido con su
  paquete.
- **Importar un modelo descargado** (icono de carpeta arriba, o «Importar» en cada modelo): elige
  los ficheros bajados por tu cuenta y la app reconoce a qué modelo pertenecen (por nombre o por
  las entradas del modelo), comprueba el formato (rechaza GGUF, safetensors, PyTorch o TFLite con
  una explicación), la versión IR y el opset que admite ONNX Runtime 1.20, que no use pesos en un
  fichero aparte, que el motor de la app lo abre y si es idéntico al oficial (SHA-256). Si es una
  versión distinta pero compatible, pregunta antes de instalarla.

## 4.1.0 (2026-11-19)

- **Optimizador de corte de perfiles** en el pedido de materiales (pestaña «Despiece»): por cada
  perfil dice cuántas barras comerciales pedir («3 × 12 m + 1 × 6 m»), el plan de corte de cada
  barra dibujado a escala, con las barras iguales agrupadas, y los retales que sobran.
- Busca para cada barra la combinación de piezas que más la aprovecha (no solo «la primera que
  quepa») y la compara con el mínimo teórico; si se alcanza, lo indica.
- Ajustes guardados: ancho de corte de la sierra (3 mm por defecto), despunte de cada extremo,
  retal mínimo aprovechable (500 mm), longitud de barra (según perfil, solo 6 m o solo 12 m) y
  mezclar longitudes para no comprar una barra larga para media pieza.
- Las piezas más largas que la barra salen en tramos con aviso de empalme.
- El PDF del proyecto y el CSV del despiece incluyen el pedido y el plan de corte.

## 4.0.1 (2026-11-18)

- **Barandillas como se piden**: «doble pasamanos» (también «dos pasamanos», «pasamanos a dos
  alturas») añade un segundo pasamanos a 0,70 m sobre soportes por la cara interior (CTE DB-SUA 1
  §4.2.4), con sus soldaduras, en barandillas, escaleras y pasarelas.
- **Barandillas de inox o aluminio de tubo redondo**: montantes, pasamanos y larguero de tubo CHS y
  barrotes de redondo macizo, en lugar de tubo cuadrado. También al pedir «tubo redondo» o «tubular».
- **Render**: los tubos y redondos se dibujan redondos (antes eran cajas) y el inox y el aluminio
  reflejan el cielo, así que se ven metálicos aunque estén a la sombra.
- **Foto IA**: encuadre más cerrado y «Equilibrada» parte de un paso menos ruidoso (t = 374 en
  lugar de 499), con el mismo tiempo. Antes las piezas finas se deformaban (una barandilla podía
  salir como un puente). El texto para la IA pone primero la forma y quita lo que no aplica.

## 4.0.0

- **Formación reglada** de calderería, soldadura y estructuras metálicas: nueva pestaña «Formación»
  en «Qué entiende Herrero», con buscador y enlaces a las fuentes oficiales (TodoFP, INCUAL, SEPE,
  BOE, Procomún, RUCT, ESCO, CESOL/IIW, Fundación del Metal):
  - FP: Grado Básico en Fabricación y Montaje, Técnico en Soldadura y Calderería (módulos 0006,
    0007, 0091–0095), Técnico Superior en Construcciones Metálicas, ciclos afines y cursos de
    especialización.
  - Certificados profesionales vigentes de soldadura (FMEC0119_2 MIG/MAG, FMEC0219_2 TIG,
    FMEC0319_2 electrodo, RD 569/2023) con la equivalencia de los derogados FMEC0110 y FMEC0210,
    y los de tubería, producción y diseño de calderería y estructuras (FMEC0108/0109/0208/0209/0309).
  - Cualificaciones del INCUAL (FME035_2, FME350_2, FME351_2, FME354_3, FME355_3, FME357_3,
    FME684_2–686_2), grados A–E de la Ley 3/2022 y acreditación de la experiencia.
  - Homologación del soldador (UNE-EN ISO 9606, 14732, 14731, 9712, ASME IX / AWS D1.1),
    diplomas IIW/EWF y formación de prevención del convenio del metal (TPC/TPM).
  - Los enlaces se abren en el navegador; mantenerlos pulsados los copia. Resúmenes propios,
    sin copiar textos oficiales.
- **Paquete NVIDIA CUDA (Windows)**: fallaba con «Error HTTP 404» porque Microsoft retiró de
  GitHub el zip de ONNX Runtime 1.20.1 para GPU. Ahora se descarga del paquete oficial de Microsoft
  en NuGet (mismas librerías, ≈250 MB). La CI descarga, instala y carga de verdad los paquetes CUDA
  y OpenVINO en Windows.
- **Foto IA**: debajo de la foto se muestra cuánto tarda cada paso (texto, render, cargar el
  generador, generar, revelar) y con qué motor (CPU, NNAPI, DirectML…). En Android, NNAPI no puede
  ejecutar el generador int8 de SD-Turbo: esa parte va en CPU elijas lo que elijas, por eso CPU y
  NPU tardan lo mismo. Con estos tiempos se decidirá si merece la pena un modelo para la NPU.

## 3.5.0

- **Aceleración por GPU y NPU** para toda la IA local (foto realista, croquis, razonamiento, OCR y
  comprensión). Nuevo apartado «Aceleración de la IA» en Modelos IA con Automático, motores manuales
  y «Solo CPU». Si el motor elegido no admite un modelo o falla, ese paso sigue en CPU solo.
- **Windows**:
  - ONNX Runtime 1.20.1 con **DirectML** de serie (DirectX 12): acelera con gráficas NVIDIA, AMD e
    Intel, también las integradas. El instalador añade DirectML.dll (unos 18 MB).
  - **NVIDIA CUDA** como descarga opcional: ONNX Runtime GPU de Microsoft y, si el equipo no tiene
    CUDA 12 / cuDNN 9, las librerías oficiales de NVIDIA. Se guarda en %LOCALAPPDATA%\Herrero\gpu.
  - **Intel OpenVINO** como descarga opcional (paquete oficial de Intel con el runtime de OpenVINO),
    para Iris Xe, Arc y la NPU de Core Ultra. Guarda en caché los modelos compilados.
  - En Automático se usa CUDA u OpenVINO si su paquete está instalado y está esa gráfica; si no,
    DirectML. Cambiar de paquete pide reiniciar la app (un proceso solo puede cargar un ONNX Runtime).
  - Se mantiene la carga del ONNX Runtime por ruta completa (nunca el de System32).
  - **AMD ROCm** y **Vulkan** no existen como motores de ONNX Runtime en Windows: las Radeon van por
    DirectML.
- **Android**: además de NNAPI, motor **XNNPACK** (CPU ARM optimizada). Automático conserva el
  reparto fiable (NNAPI solo en los modelos que lo admiten).
- En PC, Automático pasa a usar la GPU (antes siempre CPU). Los modelos pequeños (comprensión y
  OCR) siguen en CPU en Automático porque arrancan antes y rinden igual.
- Compilación: las descargas de ONNX Runtime se reintentan si Maven Central o NuGet limitan la
  velocidad, y la CI de Windows comprueba que la app trae DirectML y vuelve a CPU sin GPU.

## 3.4.1

- **Windows**: el razonamiento con IA local (Qwen3) fallaba con «Unrecognized attribute: softcap for
  operator GroupQueryAttention». Windows trae su propio ONNX Runtime antiguo en System32 y a veces
  la app acababa usando ese en lugar del 1.20 que va con Herrero. Ahora se carga siempre el de la
  carpeta de la app.

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
