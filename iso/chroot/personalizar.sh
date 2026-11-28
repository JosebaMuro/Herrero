#!/usr/bin/env bash
# Se ejecuta DENTRO del chroot de la capa base del sistema de Ubuntu MATE (casper/minimal.squashfs,
# o filesystem.squashfs en las ISO sin capas); lo llama construir-iso.sh. Deja Herrero y Director
# de rol en /opt/suite, con sus accesos en el menú, para que funcionen ya en la sesión live y se
# copien tal cual al disco al instalar (instalación normal o mínima).
#
# No instala paquetes con apt: las capas superiores de la ISO llevan su propia copia de la base
# de datos de dpkg y la taparían. Todo lo que necesitan los bundles de Flutter (GTK 3, GStreamer,
# libsecret) ya viene en Ubuntu MATE; curl, si falta, lo pone el primer arranque.
#
#   /tmp/suite-iso/proyectos/herrero.tar.gz   Herrero-linux-x64.tar.gz
#   /tmp/suite-iso/proyectos/director.tar.gz  DirectorDeRol-linux-x64.tar.gz (opcional)
#   /tmp/suite-iso/instalar-ubuntu.sh         instalador de la suite (queda en /opt/suite)
#   /tmp/suite-iso/primer-arranque.sh y .service
#   /tmp/suite-iso/suite-iso.conf
set -euo pipefail
export LC_ALL=C.UTF-8
IN=/tmp/suite-iso
SUITE=/opt/suite

paso() { echo -e "\e[1;36m  [chroot] $*\e[0m"; }

paso "Paquetes que necesitan Herrero y Director de rol"
for pkg in libgtk-3-0t64 libsecret-1-0 libgstreamer1.0-0 gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
           whiptail jq unzip pciutils sudo wget; do
  if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'ok installed'; then
    # nombres antiguos (22.04) sin el sufijo t64
    dpkg-query -W -f='${Status}' "${pkg%t64}" 2>/dev/null | grep -q 'ok installed' \
      || echo "  aviso: falta el paquete $pkg en esta ISO" >&2
  fi
done

instalar_bundle() { # instalar_bundle ID TAR
  local id="$1" tar="$2" tmp top
  tmp="$(mktemp -d)"
  tar -xzf "$tar" -C "$tmp"
  top="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -1)"
  [[ -n "$top" ]] || { echo "el paquete $tar está vacío" >&2; exit 1; }
  rm -rf "${SUITE:?}/$id"
  mkdir -p "$SUITE"
  mv "$top" "$SUITE/$id"
  rm -rf "$tmp"
  chown -R root:root "$SUITE/$id"
  chmod -R a+rX "$SUITE/$id"
}

dsk() { # dsk ID NOMBRE COMENTARIO ORDEN ICONO CATEGORÍAS (mismos nombres que instalar-ubuntu.sh)
  printf '[Desktop Entry]\nType=Application\nName=%s\nComment=%s\nExec=%s\nIcon=%s\nTerminal=false\nCategories=%s\n' \
    "$2" "$3" "$4" "$5" "$6" > "/usr/share/applications/suite-$1.desktop"
}

if [[ -f $IN/proyectos/herrero.tar.gz ]]; then
  paso "Herrero en $SUITE/herrero"
  instalar_bundle herrero "$IN/proyectos/herrero.tar.gz"
  [[ -x $SUITE/herrero/herrero-tui ]] || { echo "el paquete de Herrero no trae herrero-tui" >&2; exit 1; }
  ln -sfn "$SUITE/herrero" /opt/herrero
  ln -sf "$SUITE/herrero/herrero-tui" /usr/local/bin/herrero-tui
  [[ -x $SUITE/herrero/herrero ]] && ln -sf "$SUITE/herrero/herrero" /usr/local/bin/herrero
  dsk herrero "Herrero" "Oficina técnica de estructuras metálicas" /usr/local/bin/herrero \
    applications-engineering "Office;Engineering;"
  dsk herrero-tui "Herrero (terminal)" "Herrero en modo texto" "mate-terminal --maximize -x herrero-tui" \
    utilities-terminal "Office;Engineering;"
fi

if [[ -f $IN/proyectos/director.tar.gz ]]; then
  paso "Director de rol en $SUITE/director"
  instalar_bundle director "$IN/proyectos/director.tar.gz"
  exe="$(find "$SUITE/director" -maxdepth 1 -type f -executable ! -name '*.so*' | head -1)"
  [[ -n "$exe" ]] || { echo "el paquete de Director de rol no trae ejecutable" >&2; exit 1; }
  ln -sf "$exe" /usr/local/bin/director-de-rol
  dsk director "Director de rol" "Partidas de rol con IA local" /usr/local/bin/director-de-rol \
    applications-games "Game;RolePlaying;"
fi

paso "Comprobar las bibliotecas de los ejecutables"
falta=0
while read -r b; do
  # las bibliotecas propias del bundle están en su lib/ (las encuentra por RUNPATH o así)
  if LD_LIBRARY_PATH="$(dirname "$b")/lib:$(dirname "$b")" ldd "$b" 2>/dev/null | grep 'not found'; then
    echo "  ^ en $b" >&2; falta=1
  fi
done < <(find "$SUITE" -maxdepth 3 -type f \( -name '*.so*' -o -perm -u+x \) ! -name 'libdartjni.so' \
           -exec sh -c 'head -c4 "$1" | grep -q ELF' _ {} \; -print)
# (libdartjni.so pide libjvm.so: es de Android y en Linux no se carga)
[[ $falta == 0 ]] || { echo "faltan bibliotecas en la ISO para los bundles" >&2; exit 1; }

paso "Instalador de la suite y configuración del primer arranque"
install -m 0755 "$IN/instalar-ubuntu.sh" "$SUITE/instalar-ubuntu.sh"
mkdir -p "$SUITE/iso"
install -m 0755 "$IN/primer-arranque.sh" "$SUITE/iso/primer-arranque.sh"
install -m 0644 "$IN/suite-iso.conf" /etc/suite-iso.conf
install -m 0644 "$IN/suite-primer-arranque.service" /etc/systemd/system/suite-primer-arranque.service
mkdir -p /etc/systemd/system/multi-user.target.wants
ln -sf /etc/systemd/system/suite-primer-arranque.service \
  /etc/systemd/system/multi-user.target.wants/suite-primer-arranque.service


