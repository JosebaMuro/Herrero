# Herrero · Oficina técnica de estructuras metálicas

App ligera para **Android, iPhone, Windows y Linux** (también **TUI de terminal**) que, a partir de una descripción en lenguaje natural
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

## Novedades de la v4.1

- **Linux y TUI de terminal** (`herrero-tui`), también en modo texto sin escritorio.
- **NVIDIA CUDA en Linux** (p. ej. RTX 4050 de 6 GB) y la gráfica se despierta sola al arrancar.
- Instalador para Ubuntu LTS que arranca directamente en la TUI, con modo sin conexión.

### Ubuntu en modo texto con Herrero

```bash
# con internet
sudo ./instalar-ubuntu.sh
# sin conexión: preparar en el mismo Ubuntu (mejor en el propio equipo) y luego instalar
./instalar-ubuntu.sh --preparar /media/usb/herrero-offline
sudo /media/usb/herrero-offline/instalar-ubuntu.sh --desde /media/usb/herrero-offline
# volver al escritorio
sudo /opt/herrero/instalar-ubuntu.sh --deshacer
```

El instalador pone el controlador NVIDIA *headless* (módulos firmados de Ubuntu, válidos con
Secure Boot), carga `nvidia`/`nvidia_uvm` al arrancar, activa `nvidia-persistenced`, deja el
sistema en `multi-user.target` (sin X11) y abre Herrero en tty1 con inicio de sesión automático.
Para alternar: **Ctrl+R** en la TUI reinicia con el escritorio, y el botón de terminal de la app de
escritorio reinicia en modo TUI (`sudo herrero-modo escritorio|tui --reiniciar` a mano).

### TUI sin pantalla

```bash
herrero-tui --calcular "marquesina para 3 coches en Burgos" --exportar   # CSV, DXF y memoria
herrero-tui --gpu                                                        # diagnóstico CUDA
```

## Novedades de la v4

- Formación reglada de soldadura, calderería y estructuras (FP, certificados, cualificaciones y
  homologaciones) con enlaces oficiales.
- Tiempos por paso en la foto IA y paquete CUDA arreglado.

## Novedades de la v3.5

- **IA acelerada por GPU / NPU** (Modelos IA → «Aceleración de la IA»), con vuelta a CPU automática:
  - **Windows**: DirectML de serie (cualquier gráfica NVIDIA, AMD o Intel con DirectX 12). Descargas
    opcionales: **NVIDIA CUDA** (≈250 MB, más ≈1,2 GB de librerías NVIDIA si no tienes CUDA 12 y
    cuDNN 9) e **Intel OpenVINO** (≈36 MB, gráficas Intel y NPU Core Ultra).
  - **Android**: NNAPI (GPU, DSP o NPU del móvil) y XNNPACK (CPU ARM optimizada).
  - AMD ROCm/MIGraphX solo existe para Linux en ONNX Runtime y Vulkan no es un motor de ONNX Runtime:
    en Windows las gráficas AMD van por DirectML.

## Novedades de la v3.3

- Diccionario de castellano: entiende faltas, diminutivos, plurales y regionalismos («escalra»,
  «varandilla», «escalerita»), y vocabulario de escaleras, barandillas, pasamanos, rejas y vallas.
- Nuevas formas: escalera en L, en U, de zanca central y de caracol; escala de gato con jaula;
  barandillas de vidrio, cables, chapa perforada o lamas con rodapié; pasamanos a pared; reja de ventana.
- Autocompletar en el campo de la petición.

## Novedades de la v3.2

- **App para iPhone y iPad** (iOS 15 o posterior): `Herrero-ios.ipa`, gratis con tu Apple ID (instrucciones
  en Descargas). Incluye la IA local; los modelos no ocupan tu copia de iCloud.

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
- `Herrero-linux-x64.tar.gz` — Linux x86-64 (Ubuntu 22.04 o posterior): app y `herrero-tui`.
- `instalar-herrero-ubuntu.sh` — instalador para Ubuntu LTS en modo texto (ver arriba).
- `Herrero-ios.ipa` — iPhone y iPad con iOS 15 o posterior, sin firmar (ver abajo).

### Instalar en iPhone gratis (sin cuenta de desarrollador)

El `.ipa` va sin firmar: lo firma tu propio Apple ID gratuito al instalarlo desde un ordenador.

1. En el ordenador (Windows o Mac) instala [Sideloadly](https://sideloadly.io). En Windows necesita
   además iTunes e iCloud descargados de la web de Apple (no de Microsoft Store).
2. Conecta el iPhone por cable, desbloquéalo y acepta «Confiar en este ordenador».
3. Abre Sideloadly, arrastra `Herrero-ios.ipa`, escribe tu Apple ID y pulsa **Start**.
4. En el iPhone: *Ajustes > General > VPN y gestión de dispositivos* > tu Apple ID > **Confiar**.
5. Con iOS 16 o posterior: *Ajustes > Privacidad y seguridad > Modo de desarrollador* > activar
   (el iPhone se reinicia).

La firma gratuita dura **7 días**: después la app no abre hasta que la vuelvas a instalar con
Sideloadly; tus proyectos y modelos se conservan. Como alternativa, [AltStore](https://altstore.io)
la renueva sola por wifi si el ordenador tiene AltServer abierto. Con un Apple ID gratuito caben
3 apps instaladas así a la vez.

## Tipos de estructura soportados

| Tipo | Palabras clave |
|---|---|
| Nave de pórticos a dos aguas | nave, pórtico, almacén, taller, hangar |
| Marquesina / pérgola / cobertizo | marquesina, pérgola, porche, carport, cochera |
| Entreplanta / altillo | altillo, entreplanta, plataforma, forjado |
| Escalera (recta, en L, en U, zanca central, caracol, escala de gato), pasarela, barandilla, pasamanos | escalera, peldaños, caracol, escala de gato, pasarela, barandilla, pasamanos, guardacuerpos |
| Cercha, torre, estantería | cercha, celosía, torre, estantería, rack |
| Cancela, valla, reja de ventana, pórtico, poste | cancela, puerta, valla, reja, pórtico, poste, báculo |

## Desarrollo

```
flutter pub get
flutter test
flutter run -d windows   # o un dispositivo Android
```
