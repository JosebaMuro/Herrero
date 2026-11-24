# Herrero · Manual de usuario (v4.3)

Herrero es una oficina técnica de bolsillo para talleres de estructura metálica, herrería y
calderería. Funciona en Android, iPhone, Windows y Linux, sin conexión salvo para descargar modelos,
buscar distribuidores o situar direcciones en el mapa.

> Los resultados son un **predimensionado orientativo**. Un técnico competente debe revisarlos y
> firmarlos antes de fabricar o montar.

## 1. Calcular una estructura

1. En la pantalla principal, describe lo que necesitas: tipo, medidas, altura, cubierta o uso,
   material, acabado y población. Ejemplo: *«Marquesina para 2 coches de 5,5 x 5 m y 2,4 m de alto,
   panel sándwich, galvanizada»*. Mientras escribes salen sugerencias del vocabulario del oficio.
2. Pulsa **Calcular estructura**. Aparece la ficha **«Lo que he entendido»** con cada dato y de dónde
   sale (lo has dicho tú, deducción de oficio, IA o valor habitual). Corrige lo que haga falta.
3. Pulsa **Calcular**. Se abre el proyecto con sus pestañas: Resumen, Despiece, Soldadura,
   Isométrica, Planos, Montaje, Render y **Presupuesto**.

También puedes empezar desde un plano: **Importar plano** (PDF de CAD, PDF escaneado, foto o croquis).

## 2. Guardar y gestionar proyectos

- En el proyecto, pulsa el **disquete** (arriba). Escribe nombre, cliente, obra, estado y notas.
  Desde entonces los cambios (ajustar parámetros, acabado, foto IA, presupuesto) se guardan solos;
  el icono de la nube indica que está guardado.
- Toca el **título** del proyecto para cambiar sus datos o su estado.
- **Proyectos guardados** (icono de carpeta o botón de la pantalla principal): busca por nombre,
  cliente o tipo y filtra por estado. En el menú de cada proyecto: *Datos y estado*, *Duplicar*
  (para una variante o un trabajo parecido), *Historial* y *Borrar*.
- Los últimos proyectos aparecen también en la pantalla principal.
- Al abrir un proyecto se recalcula con la versión actual de la app, así que siempre está al día.

Estados: Borrador → Presupuestado → Aceptado → En fabricación → En montaje → Terminado (o Descartado).
Al imprimir el presupuesto de un borrador, pasa a *Presupuestado* automáticamente.

## 3. Precios: facturas, tarifas y proveedores

Icono **€** de la pantalla principal (o desde la pestaña Presupuesto).

### 3.1 Importar una factura o tarifa
1. Pestaña **Precios** → **Importar factura o tarifa** (PDF o imagen) o **Foto de factura**.
2. Herrero lee el texto en el propio equipo (los PDF escaneados y las fotos usan el OCR local; la
   primera vez se descarga, unos 16 MB). La factura no sale de tu dispositivo.
3. Revisa: proveedor, CIF, dirección, fecha y nº de factura. Pulsa el globo junto a la dirección
   para situar al proveedor en el mapa (necesario para filtrar por radio).
4. Cada línea muestra el material reconocido (por ejemplo *IPE 200*, *SHS 80x3*, *CHAPA 10*,
   *TORNILLO M16*), cantidad, precio neto con descuento e importe. Solo se leen las líneas en las que
   cantidad × precio cuadra con el importe. Toca ✎ para corregir una línea y marca las que quieras
   guardar.
5. **Guardar**. Si el proveedor ya existía (mismo CIF o nombre) se reutiliza.

Las tarifas con líneas del tipo «IPE 200 …… 1,10 €/kg» o «Tubo 60x60x2 … 4,20 €/m» se leen igual.
También puedes añadir un **precio a mano** o borrar uno deslizándolo.

### 3.2 Ubicación y radio
Pestaña **Ubicación**:
- **Usar mi ubicación actual** (GPS o red) o escribe tu población.
- **Radio de alcance** de 5 a 300 km: el presupuesto solo usa proveedores dentro del radio.
- *Usar también proveedores sin ubicación*: facturas cuya dirección no se pudo situar.
- *Antigüedad máxima* de los precios (3, 6, 12 o 24 meses).
- *Si hay varios proveedores*: mediana, el más barato o el más reciente.

### 3.3 Distribuidores cercanos
Pestaña **Distribuidores** → **Buscar distribuidores**: lista almacenes de hierros, aceros,
perfiles, ferralla, galvanizadores y suministros industriales registrados en OpenStreetMap dentro
del radio. El mapa **no da precios**; desde cada uno puedes:
- **Pedir precio**: abre un correo (o SMS) con el pedido de material del proyecto.
- **Llamar** o abrir su **web**.
- **Leer precios de su web**: si publica una página de tarifas con «€/kg», «€/m»…, se leen y se
  revisan como una tarifa. Muchos almacenes no publican precios: en ese caso, pídeselos.
- **Guardar** como proveedor tuyo.

### 3.4 Tarifas del taller
Pestaña **Taller**: precio de la hora de taller y de montaje, gastos generales y beneficio, IVA, y
rendimientos (h/kg de fabricación, h/m de soldadura, h/kg de montaje, manos y rendimiento de la
pintura). Los rendimientos traen un valor de partida orientativo: ajústalos con tus tiempos reales.

## 4. Presupuesto del proyecto

Pestaña **Presupuesto** del proyecto:
- Partes: Materiales (barras del plan de corte con su merma, chapa +15 % de recortes, tornillería,
  cubierta y cerramientos), Fabricación, Soldadura (horas y consumible), Acabados (galvanizado por
  kg o pintura por m² o por litros) y Montaje.
- Debajo de cada línea se ve **de dónde sale el precio**: factura o tarifa, proveedor, fecha,
  distancia y si es de la misma medida o de otra medida de la misma familia (€/kg).
- Las líneas **sin precio** salen en rojo y no suman: toca la línea para fijar su precio en este
  proyecto (queda con una chincheta), o importa una factura.
- Toca *Transporte* o *Gastos generales* para poner el transporte, la grúa o un margen propio del
  proyecto.
- **Presupuesto en PDF** (versión para el cliente) y **Copiar petición de precio** (para pegar en un
  correo o WhatsApp).

## 5. Imprimir por apartados

Menú de exportar (icono de compartir) → **Apartados por separado (PDF)**. Elige los apartados:

| Apartado | Para | Contenido |
|---|---|---|
| Resumen | Dirección / cliente | Imagen, pesos, ratios y avisos |
| Memoria de cálculo | Oficina técnica | Materiales, hipótesis, comprobaciones, normativa |
| Materiales y pedido | Compras y almacén | Barras a pedir, chapa, tornillería, consumibles (sin precios) |
| Fabricación en taller | Taller | Despiece, chapas, plan de corte, isométrica y planos de detalle |
| Soldadura | Soldadores y calidad | Proceso, EXC, nivel de calidad, ensayos, uniones, normativa |
| Montaje en obra | Montadores | Secuencia, tornillería y anclajes, piezas, isométrica, planos de conjunto |
| Planos | Todos | Todas las láminas CAD |
| Presupuesto | Cliente | Con o sin precios unitarios y su origen |

Cada apartado empieza en página nueva, lleva en la cabecera el proyecto, el cliente, la obra y el
destinatario, y numera sus propias páginas («Soldadura · pág. 2 de 3»). Con **Un PDF por apartado**
se genera un archivo para cada uno, listo para enviar solo su parte a cada persona.

## 6. IA local y memoria

- Los modelos (comprensión, razonamiento, OCR, visión de croquis y foto IA) se descargan desde
  **Modelos de IA local** y funcionan sin conexión.
- **Carga de modelos** (en Modelos de IA local): en *Automático*, si el equipo tiene menos de 6 GB de
  RAM los modelos se cargan **por turnos** según el paso en que estés (ficha, planos, foto,
  facturas). Al pasar de un paso a otro se cancela lo que el nuevo paso no usa (por ejemplo, el
  razonamiento en segundo plano al ir a la foto IA) y se liberan las cachés. *Siempre* lo fuerza;
  *Nunca* permite varios modelos a la vez.

## 7. Dónde se guardan los datos

- Proyectos y precios: carpeta de datos de la app (Android: privada de la app; Windows:
  `%APPDATA%\…\herrero\datos`; Linux: `~/.local/share/es.herrero.herrero/datos`).
- PDF, DXF, CSV y modelos 3D exportados: *Documentos/Herrero* (en Android, la carpeta de la app en
  el almacenamiento externo; se comparten al generarlos).

## 8. Linux

Descomprime `Herrero-linux-x64.tar.gz` y ejecuta `herrero/herrero` (app de escritorio, necesita
GTK 3) o `herrero/herrero-tui` (**TUI de terminal**, también sin escritorio). La ubicación por GPS
usa GeoClue y la elección de archivos, zenity o kdialog. Ver `LEEME.txt` dentro del paquete.

- **TUI**: escribe la petición, revisa la ficha «Lo que he entendido» y recorre el resultado por
  pestañas (resumen, despiece, comprobaciones, uniones, montaje, normativa); exporta CSV, DXF y
  memoria en Markdown. Ctrl+G abre «IA y GPU» (motor, paquete CUDA, modelos y prueba de velocidad).
  Sin pantalla: `herrero-tui --calcular "…"`, `--gpu`, `--instalar-cuda`.
- **NVIDIA CUDA**: el paquete CUDA descargable acelera la IA en gráficas NVIDIA (también con poca
  memoria, p. ej. 6 GB). Si la gráfica no responde, se avisa con los comandos para arreglarlo y la
  IA sigue en CPU.
- **Instalador de Ubuntu** (`instalar-herrero-ubuntu.sh`): instala la app, el controlador NVIDIA y
  el arranque en modo texto con la TUI; `--preparar CARPETA` lo descarga todo para instalar sin
  conexión con `--desde CARPETA`, y `--deshacer` vuelve al escritorio.
- **Cambiar de modo**: en la TUI, Ctrl+R reinicia con escritorio; en la app de Linux, el botón de
  terminal reinicia en modo TUI.

## 9. Privacidad

Las facturas, planos y fotos se leen en tu equipo. Solo salen a internet: la posición o el nombre
de la población para el mapa (OpenStreetMap / Nominatim), la búsqueda de distribuidores (Overpass)
y la página de tarifas que pidas leer.
