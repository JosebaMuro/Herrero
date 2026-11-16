# Herrero · Oficina técnica de estructuras metálicas

App ligera para **Android y Windows** que, a partir de una descripción en lenguaje natural
("nave a dos aguas de 30 x 15 m, 6 m al alero, panel sándwich, en Vitoria"), predimensiona la
estructura según **CTE DB-SE-A / Eurocódigo 3** y genera:

- **Despiece** con marcas, perfiles, longitudes, cantidades, pesos y optimización de barras comerciales.
- **Chapas, tornillería y soldaduras** (garganta, longitud, proceso, consumible estimado).
- **Memoria de cálculo** con hipótesis, cargas y comprobaciones (aprovechamiento η).
- **Vista isométrica**, **planos de montaje** (alzados, planta, detalle de placa) y **secuencia de montaje**.
- **Render 3D** de la estructura y exportación a **PDF**.

> ⚠️ Los resultados son un **predimensionado orientativo**. Deben ser revisados y firmados por un técnico competente antes de fabricar o montar.

## Descargas

Los binarios se generan con GitHub Actions y se publican en *Releases*:
- `Herrero-android.apk` — instalar en Android (permitir orígenes desconocidos).
- `Herrero-windows-setup.exe` — instalador para Windows 10/11 x64.
- `Herrero-windows-portable.zip` — versión portable (descomprimir y ejecutar `herrero.exe`).

## Tipos de estructura soportados

| Tipo | Palabras clave |
|---|---|
| Nave de pórticos a dos aguas | nave, pórtico, almacén, taller, hangar |
| Marquesina / pérgola / cobertizo | marquesina, pérgola, porche, carport, cochera |
| Entreplanta / altillo | altillo, entreplanta, plataforma, forjado |

## Desarrollo

```
flutter pub get
flutter test
flutter run -d windows   # o un dispositivo Android
```
