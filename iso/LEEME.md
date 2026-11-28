# ISO de Ubuntu MATE con Herrero y Director de rol

`construir-iso.sh` parte de la ISO oficial de **Ubuntu MATE 24.04.5 LTS** y genera otra igual
pero con **Herrero** y **Director de rol** (Rol-master) ya instalados:

- **En la sesión live** («Probar Ubuntu MATE») las dos aplicaciones ya están en el menú
  (*Oficina* y *Juegos*) y funcionan sin instalar nada. Los modelos de IA de Herrero se pueden
  descargar desde la propia app (se pierden al apagar, como todo en live).
- **Al instalar** Ubuntu MATE desde esa ISO se copian al disco tal cual. En el primer arranque
  del sistema instalado, el servicio `suite-primer-arranque` termina la configuración para el
  usuario que se creó al instalar:
  - lo añade a los grupos `video` y `render`;
  - si hay gráfica NVIDIA y aún no tiene controlador, instala el recomendado
    (`ubuntu-drivers install`, el de escritorio) y, tras reiniciar, el paquete CUDA de Herrero;
  - descarga los modelos de IA de Herrero.

  Va en segundo plano (no retrasa el escritorio) y necesita internet; lo que no pueda hacer se
  reintenta en el siguiente arranque. Registro: `/var/log/suite-primer-arranque.log`.

Dónde queda todo: `/opt/suite/herrero` (con `herrero` y `herrero-tui` en `/usr/local/bin`),
`/opt/suite/director` (`director-de-rol`) y el instalador completo de la suite en
`/opt/suite/instalar-ubuntu.sh`, por si luego se quiere el modo terminal sin escritorio o el
resto de proyectos (`sudo /opt/suite/instalar-ubuntu.sh`).

## Descargar la ISO ya hecha

El workflow **ISO de Ubuntu MATE con la suite** (pestaña *Actions* → *Run workflow*) la construye
y la publica en la release
[`iso-ubuntu-mate`](https://github.com/JosebaMuro/Herrero/releases/tag/iso-ubuntu-mate) en
partes de 1,9 GB (GitHub no admite ficheros de más de 2 GB). Hay que unirlas:

```bash
cat ubuntu-mate-24.04.5-suite-amd64.iso.parte* > ubuntu-mate-24.04.5-suite-amd64.iso
sha256sum -c ubuntu-mate-24.04.5-suite-amd64.iso.sha256
```

En Windows: `copy /b fichero.parte0+fichero.parte1+fichero.parte2 fichero.iso` (todas las
partes, en orden). Después se graba en un USB con balenaEtcher, Ventoy o `dd`.

## Construirla en tu equipo

En Ubuntu o Debian x86-64, con ≈25 GB libres y conexión:

```bash
sudo apt install xorriso squashfs-tools curl
sudo ./iso/construir-iso.sh
```

Descarga la ISO oficial (comprueba su SHA256), la última versión de Herrero para Linux y la de
Director de rol, y deja `ubuntu-mate-24.04.5-suite-amd64.iso` en la carpeta actual. Tarda
entre 20 y 40 minutos, casi todo en comprimir el sistema live.

| Opción | Qué hace |
| --- | --- |
| `--iso FICHERO` | usar una ISO de Ubuntu MATE ya descargada |
| `--version V` | otra versión de Ubuntu MATE (con `casper/minimal.squashfs` o `filesystem.squashfs`) |
| `--herrero TAR`, `--director TAR` | usar paquetes ya descargados o compilados por ti |
| `--sin-director` | sin Director de rol (≈1 GB menos) |
| `--sin-nvidia`, `--sin-modelos` | que el primer arranque no instale el controlador NVIDIA/CUDA o no descargue modelos |
| `--rapido` | comprime con zstd: construye bastante antes, la ISO ocupa algo más |
| `--salida`, `--trabajo` | dónde dejar la ISO y la carpeta de trabajo |

Cómo funciona: Ubuntu MATE 24.04 trae el sistema por capas (`minimal.squashfs` es la base,
`minimal.standard` la instalación completa y `minimal.standard.live` lo que solo se usa en live).
El script extrae la capa base, entra con `chroot`, ejecuta `chroot/personalizar.sh` (`/opt/suite`,
accesos del menú, servicio del primer arranque y comprobación de que no falta ninguna biblioteca),
la vuelve a comprimir, actualiza tamaños (`install-sources.yaml`, `*.size`) y sumas (`SHA256SUMS`,
`md5sum.txt`) y rehace la ISO con `xorriso` reutilizando el arranque original (BIOS, UEFI y
Secure Boot). Al ir en la capa base, las aplicaciones están en la sesión live y en las dos
opciones del instalador (completa y mínima). No se instala nada con apt: todo lo que necesitan
los bundles de Flutter (GTK 3, GStreamer, libsecret) ya viene en Ubuntu MATE.
