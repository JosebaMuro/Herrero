#!/usr/bin/env bash
# ISO de Ubuntu MATE con Herrero y Director de rol (Rol-master) ya instalados.
#
# Parte de la ISO oficial de Ubuntu MATE, abre la capa base de su sistema (casper/minimal.squashfs),
# instala dentro Herrero y Director de rol en /opt/suite con sus accesos en el menú y vuelve a
# generar la ISO con el mismo arranque (BIOS y UEFI, Secure Boot). Así:
#   · en la sesión live («Probar Ubuntu MATE») ya se pueden usar las dos aplicaciones
#   · al instalar se copian al disco tal cual, y en el primer arranque del sistema instalado
#     un servicio pone lo que depende del equipo y del usuario: controlador NVIDIA, paquete
#     CUDA y modelos de IA de Herrero (iso/chroot/primer-arranque.sh)
#
#   sudo ./construir-iso.sh                          descarga lo necesario y construye la ISO
#   sudo ./construir-iso.sh --iso ubuntu-mate-24.04.5-desktop-amd64.iso
#
# Opciones:
#   --iso FICHERO       ISO original de Ubuntu MATE (si no, se descarga y se comprueba su SHA256)
#   --version V         versión de Ubuntu MATE que descargar (por defecto 24.04.5)
#   --salida FICHERO    ISO resultante (por defecto ubuntu-mate-V-suite-amd64.iso)
#   --herrero TAR       Herrero-linux-x64.tar.gz ya descargado
#   --director TAR      DirectorDeRol-linux-x64.tar.gz ya descargado
#   --sin-director      no incluir Director de rol (la ISO ocupa ≈1 GB menos)
#   --sin-nvidia        el primer arranque no instala el controlador NVIDIA ni CUDA
#   --sin-modelos       el primer arranque no descarga los modelos de IA de Herrero
#   --trabajo CARPETA   carpeta de trabajo (necesita ≈25 GB libres; por defecto ./trabajo-iso)
#   --rapido            squashfs con zstd en vez de xz: construye antes, ISO algo mayor
#
# Necesita Ubuntu o Debian x86-64 con: sudo apt install xorriso squashfs-tools curl
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GH=https://github.com/JosebaMuro
VERSION=24.04.5
ISO=""
OUT=""
HERRERO_TAR=""
DIRECTOR_TAR=""
WITH_DIRECTOR=1
WITH_NVIDIA=1
WITH_MODELS=1
WORK="$PWD/trabajo-iso"
COMP=(-comp xz -Xbcj x86)

c_h=$'\e[1;36m'; c_ok=$'\e[1;32m'; c_err=$'\e[1;31m'; c_0=$'\e[0m'
paso() { echo "${c_h}==> $*${c_0}"; }
ok() { echo "${c_ok}    $*${c_0}"; }
fallo() { echo "${c_err}Error: $*${c_0}" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --iso) ISO="${2:?falta el fichero}"; shift ;;
    --version) VERSION="${2:?falta la versión}"; shift ;;
    --salida) OUT="${2:?falta el fichero}"; shift ;;
    --herrero) HERRERO_TAR="${2:?falta el fichero}"; shift ;;
    --director) DIRECTOR_TAR="${2:?falta el fichero}"; shift ;;
    --sin-director) WITH_DIRECTOR=0 ;;
    --sin-nvidia) WITH_NVIDIA=0 ;;
    --sin-modelos) WITH_MODELS=0 ;;
    --trabajo) WORK="${2:?falta la carpeta}"; shift ;;
    --rapido) COMP=(-comp zstd -Xcompression-level 15) ;;
    -h|--help|--ayuda) sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fallo "opción desconocida: $1 (usa --ayuda)" ;;
  esac
  shift
done

[[ $EUID -eq 0 ]] || fallo "ejecútalo con sudo (hace falta para el chroot)"
[[ "$(uname -m)" == x86_64 ]] || fallo "hay que construirla en un equipo x86-64"
for t in xorriso unsquashfs mksquashfs curl sha256sum md5sum chroot; do
  command -v "$t" >/dev/null || fallo "falta $t: sudo apt install xorriso squashfs-tools curl"
done
OUT="${OUT:-$PWD/ubuntu-mate-$VERSION-suite-amd64.iso}"
mkdir -p "$WORK"
WORK="$(cd "$WORK" && pwd)"
RAIZ="$WORK/raiz"
DL="$WORK/descargas"
mkdir -p "$DL"

dl() { curl -fL --retry 3 --retry-delay 5 -o "$2.part" "$1" && mv "$2.part" "$2"; }

# ------------------------------------------------------------------ descargas
if [[ -z "$ISO" ]]; then
  base="https://cdimage.ubuntu.com/ubuntu-mate/releases/$VERSION/release"
  name="ubuntu-mate-$VERSION-desktop-amd64.iso"
  ISO="$DL/$name"
  paso "ISO de Ubuntu MATE $VERSION"
  [[ -f "$ISO" ]] || dl "$base/$name" "$ISO" || fallo "no se pudo descargar $base/$name"
  sum="$(curl -fsSL "$base/SHA256SUMS" | awk -v n="*$name" '$2==n || $2==substr(n,2) {print $1}')"
  [[ -n "$sum" ]] || fallo "no encuentro el SHA256 de $name"
  echo "$sum  $ISO" | sha256sum -c --quiet || { rm -f "$ISO"; fallo "la ISO descargada está dañada"; }
  ok "SHA256 correcto"
fi
[[ -f "$ISO" ]] || fallo "no existe $ISO"

if [[ -z "$HERRERO_TAR" ]]; then
  paso "Herrero para Linux (última versión publicada)"
  HERRERO_TAR="$DL/Herrero-linux-x64.tar.gz"
  dl "$GH/Herrero/releases/latest/download/Herrero-linux-x64.tar.gz" "$HERRERO_TAR" \
    || fallo "no se pudo descargar Herrero"
fi
if [[ $WITH_DIRECTOR == 1 && -z "$DIRECTOR_TAR" ]]; then
  paso "Director de rol para Linux (≈1,1 GB, con voces y Whisper)"
  DIRECTOR_TAR="$DL/DirectorDeRol-linux-x64.tar.gz"
  dl "$GH/Rol-master/releases/download/linux-latest/DirectorDeRol-linux-x64.tar.gz" "$DIRECTOR_TAR" \
    || fallo "no se pudo descargar Director de rol"
fi

# ------------------------------------------------------------------ sistema live
# Ubuntu MATE 24.04 trae el sistema por capas: minimal.squashfs (base) + minimal.standard
# (instalación completa) + minimal.standard.live (solo live). Se modifica la capa base, así las
# apps se ven en la sesión live y quedan en las dos opciones de instalación. Las ISO antiguas
# traen un único casper/filesystem.squashfs.
listado="$(xorriso -indev "$ISO" -find /casper -type f 2>/dev/null)"
if grep -q "'/casper/minimal.squashfs'" <<<"$listado"; then CAPA=minimal
elif grep -q "'/casper/filesystem.squashfs'" <<<"$listado"; then CAPA=filesystem
else fallo "no encuentro el sistema live en /casper: $(grep -o "'/casper/[^']*squashfs'" <<<"$listado" | tr '\n' ' ')"; fi
SQ=/casper/$CAPA.squashfs
paso "Sistema live de la ISO ($SQ)"
rm -rf "$WORK/iso" "$RAIZ"
mkdir -p "$WORK/iso/casper"
extra=()
for f in /md5sum.txt /casper/SHA256SUMS /casper/install-sources.yaml /casper/$CAPA.size /casper/filesystem.size; do
  grep -q "'$f'" <<<"$listado$(printf "\n'/md5sum.txt'")" && extra+=(-extract "$f" "$WORK/iso$f")
done
xorriso -osirrox on -indev "$ISO" -extract "$SQ" "$WORK/iso$SQ" "${extra[@]}" >/dev/null 2>&1 || true
[[ -f "$WORK/iso$SQ" ]] || fallo "no se pudo extraer $SQ"
chmod -R u+w "$WORK/iso"
unsquashfs -no-progress -d "$RAIZ" "$WORK/iso$SQ" >/dev/null
rm -f "$WORK/iso$SQ"
antes="$(du -sx --block-size=1 "$RAIZ" | cut -f1)"
ok "$(du -sh "$RAIZ" | cut -f1) descomprimidos"

# ------------------------------------------------------------------ chroot
montado=()
desmontar() {
  local i
  for ((i = ${#montado[@]} - 1; i >= 0; i--)); do umount -l "${montado[$i]}" 2>/dev/null || true; done
  montado=()
}
trap desmontar EXIT
montar() { mount "$@" && montado+=("${*: -1}"); }

paso "Instalar Herrero${DIRECTOR_TAR:+ y Director de rol} en el sistema de la ISO"
IN="$RAIZ/tmp/suite-iso"
mkdir -p "$IN/proyectos"
cp "$HERRERO_TAR" "$IN/proyectos/herrero.tar.gz"
if [[ $WITH_DIRECTOR == 1 ]]; then cp "$DIRECTOR_TAR" "$IN/proyectos/director.tar.gz"; fi
cp "$HERE/chroot/personalizar.sh" "$HERE/chroot/primer-arranque.sh" \
   "$HERE/chroot/suite-primer-arranque.service" "$IN/"
cp "$HERE/../scripts/instalar-ubuntu.sh" "$IN/instalar-ubuntu.sh"
printf 'WITH_NVIDIA=%s\nWITH_MODELS=%s\n' "$WITH_NVIDIA" "$WITH_MODELS" > "$IN/suite-iso.conf"

montar --bind /dev "$RAIZ/dev"
montar -t proc proc "$RAIZ/proc"
montar -t sysfs sysfs "$RAIZ/sys"
chroot "$RAIZ" /bin/bash /tmp/suite-iso/personalizar.sh
desmontar
rm -rf "$RAIZ/tmp/suite-iso"
despues="$(du -sx --block-size=1 "$RAIZ" | cut -f1)"
delta=$((despues - antes))
ok "$((delta / 1024 / 1024)) MB añadidos"

# ------------------------------------------------------------------ squashfs e ISO
paso "Comprimir el sistema live (${COMP[1]}; tarda un rato)"
mksquashfs "$RAIZ" "$WORK/iso$SQ" "${COMP[@]}" -noappend -no-progress -quiet
rm -rf "$RAIZ"
ok "$(du -h "$WORK/iso$SQ" | cut -f1)"

paso "Tamaños y sumas de comprobación"
( cd "$WORK/iso/casper"
  # espacio que necesita el instalador: se suma lo añadido
  for f in "$CAPA.size" filesystem.size; do
    [[ -f $f ]] && echo $(($(cat "$f") + delta)) > "$f"
  done
  if [[ -f install-sources.yaml ]]; then
    awk -v d="$delta" '/^  size: [0-9]+$/ {print "  size: " ($2 + d); next} {print}' install-sources.yaml > i.tmp
    mv i.tmp install-sources.yaml
  fi
  if [[ -f SHA256SUMS ]]; then
    s="$(sha256sum "$CAPA.squashfs" | cut -d' ' -f1)"
    sed -i "s|^[0-9a-f]* \*$CAPA.squashfs\$|$s *$CAPA.squashfs|" SHA256SUMS
  fi )
mapas=()
while read -r f; do
  f="${f#"$WORK/iso"}"
  mapas+=(-map "$WORK/iso$f" "$f")
done < <(find "$WORK/iso" -type f ! -name md5sum.txt)
if [[ -f "$WORK/iso/md5sum.txt" ]]; then
  ( cd "$WORK/iso"
    while read -r f; do
      s="$(md5sum "$f" | cut -d' ' -f1)"
      sed -i "s|^[0-9a-f]*  ${f//./\\.}\$|$s  $f|" md5sum.txt
    done < <(find . -type f ! -name md5sum.txt) )
  mapas+=(-map "$WORK/iso/md5sum.txt" /md5sum.txt)
fi

paso "Generar $OUT"
rm -f "$OUT"
xorriso -indev "$ISO" -outdev "$OUT" \
  -compliance iso_9660_level=3 "${mapas[@]}" \
  -boot_image any replay 2>&1 | grep -E 'Writing to|Written to medium|FAILURE|SORRY' || true
[[ -s "$OUT" ]] || fallo "xorriso no generó la ISO"
rm -rf "$WORK/iso"
( cd "$(dirname "$OUT")" && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256" )
paso "Listo: $OUT ($(du -h "$OUT" | cut -f1))"
echo "    Grábala en un USB (p. ej. con  sudo dd if=$OUT of=/dev/sdX bs=4M status=progress oflag=sync,"
echo "    o con balenaEtcher / Ventoy). En la sesión live, Herrero y Director de rol están en el menú."
