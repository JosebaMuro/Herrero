#!/usr/bin/env bash
# Instala Herrero en Ubuntu LTS (22.04, 24.04, 26.04) para usarlo en modo texto:
# sin X11 ni Wayland, con inicio de sesión automático en tty1 que abre la TUI de Herrero.
# Instala también el controlador NVIDIA headless (CUDA sin escritorio), el paquete CUDA
# de Herrero y los modelos de IA local.
#
#   sudo ./instalar-ubuntu.sh                      instalación con internet
#   ./instalar-ubuntu.sh --preparar /media/usb/herrero-offline
#                                                  descarga TODO para instalar sin conexión
#                                                  (ejecutar en el mismo Ubuntu, mejor en el
#                                                  propio equipo: los módulos NVIDIA van con
#                                                  la versión exacta del kernel)
#   sudo ./instalar-ubuntu.sh --desde /media/usb/herrero-offline
#                                                  instalación sin conexión
#   sudo ./instalar-ubuntu.sh --deshacer           vuelve al escritorio y quita el autologin
#
# Opciones:
#   --usuario NOMBRE     usuario que abre Herrero en tty1 (por defecto, quien usa sudo)
#   --tarball FICHERO    Herrero-linux-x64.tar.gz ya descargado
#   --driver VERSIÓN     controlador NVIDIA, p. ej. 580-open (por defecto el recomendado)
#   --sin-nvidia         no instalar el controlador NVIDIA
#   --sin-modelos        no instalar los modelos de IA
#   --mantener-escritorio  instala, pero sin quitar el escritorio ni poner autologin
#   --ascii              la TUI sin caracteres de dibujo (fuentes de consola básicas)
#
# Pensado para portátiles con gráfica NVIDIA (p. ej. HP Victus con RTX 4050 de 6 GB):
# los módulos precompilados y firmados de Ubuntu funcionan con Secure Boot sin DKMS.
set -euo pipefail

REPO="JosebaMuro/Herrero"
RELEASE_URL="https://github.com/$REPO/releases/latest/download/Herrero-linux-x64.tar.gz"
PREFIX=/opt/herrero
MARK_BEGIN="# >>> herrero-tui >>>"
MARK_END="# <<< herrero-tui <<<"

MODE=install
OFFLINE=""
PREP_DIR=""
TARGET_USER="${SUDO_USER:-}"
TARBALL=""
DRIVER=""
WITH_NVIDIA=1
WITH_MODELS=1
TEXT_MODE=1
TUI_ARGS=""

c_ok=$'\e[1;32m'; c_warn=$'\e[1;33m'; c_err=$'\e[1;31m'; c_h=$'\e[1;36m'; c_0=$'\e[0m'
paso() { echo "${c_h}==> $*${c_0}"; }
ok() { echo "${c_ok}    $*${c_0}"; }
aviso() { echo "${c_warn}    Aviso: $*${c_0}"; }
fallo() { echo "${c_err}Error: $*${c_0}" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --preparar) MODE=prepare; PREP_DIR="${2:?falta la carpeta}"; shift ;;
    --desde) OFFLINE="${2:?falta la carpeta}"; shift ;;
    --deshacer) MODE=undo ;;
    --usuario) TARGET_USER="${2:?falta el usuario}"; shift ;;
    --tarball) TARBALL="${2:?falta el fichero}"; shift ;;
    --driver) DRIVER="${2:?falta la versión}"; shift ;;
    --sin-nvidia) WITH_NVIDIA=0 ;;
    --sin-modelos) WITH_MODELS=0 ;;
    --mantener-escritorio) TEXT_MODE=0 ;;
    --ascii) TUI_ARGS="--ascii" ;;
    -h|--help|--ayuda) sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fallo "opción desconocida: $1 (usa --ayuda)" ;;
  esac
  shift
done

# shellcheck disable=SC1091
. /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || aviso "pensado para Ubuntu LTS; este sistema es ${PRETTY_NAME:-desconocido}"
UBU_VER="${VERSION_ID:-24.04}"
KVER="$(uname -r)"
ARCH="$(dpkg --print-architecture)"
[[ "$ARCH" == "amd64" ]] || fallo "Herrero para Linux es solo x86-64 (este equipo: $ARCH)"

has_nvidia_pci() {
  local d
  for d in /sys/bus/pci/devices/*; do
    [[ -r "$d/vendor" && -r "$d/class" ]] || continue
    [[ "$(cat "$d/vendor")" == "0x10de" && "$(cat "$d/class")" == 0x03* ]] && return 0
  done
  return 1
}

# Controlador NVIDIA recomendado («580-open»…): ubuntu-drivers o, si no, uno fijo.
pick_driver() {
  if [[ -n "$DRIVER" ]]; then echo "$DRIVER"; return; fi
  if command -v ubuntu-drivers >/dev/null 2>&1; then
    local rec
    rec="$(ubuntu-drivers devices 2>/dev/null | awk '/recommended/ {print $3}' | sed -n 's/^nvidia-driver-//p' | head -1)"
    if [[ -n "$rec" ]]; then echo "$rec"; return; fi
  fi
  echo "580-open"
}

# Paquetes NVIDIA headless (CUDA sin X11) para la versión $1 («580-open»).
nvidia_packages() {
  local d="$1" base="${1%-open}"
  local pkgs=("nvidia-headless-no-dkms-$d" "nvidia-utils-$base" "nvidia-modprobe")
  # módulos precompilados y firmados (Secure Boot) para el kernel actual y su metapaquete
  # el metapaquete de la misma serie que el kernel instalado (HWE o el de lanzamiento)
  local meta="linux-modules-nvidia-$d-generic"
  if dpkg -s "linux-generic-hwe-$UBU_VER" >/dev/null 2>&1 || dpkg -s "linux-image-generic-hwe-$UBU_VER" >/dev/null 2>&1; then
    meta="linux-modules-nvidia-$d-generic-hwe-$UBU_VER"
  fi
  local p
  for p in "linux-modules-nvidia-$d-$KVER" "$meta"; do
    if apt-cache "${APT_OFFLINE_OPTS[@]}" show "$p" >/dev/null 2>&1; then pkgs+=("$p"); fi
  done
  echo "${pkgs[@]}"
}

APT_OFFLINE_OPTS=()
BASE_PACKAGES=(unzip pciutils kbd console-setup console-setup-linux ca-certificates curl mokutil)
FIRMWARE_PACKAGES=(linux-firmware intel-microcode amd64-microcode)

# ---------------------------------------------------------------------------
# Preparar la carpeta para instalar sin conexión
# ---------------------------------------------------------------------------
prepare() {
  local dir="$PREP_DIR"
  mkdir -p "$dir/debs" "$dir/cuda" "$dir/modelos"
  dir="$(cd "$dir" && pwd)"
  command -v apt-ftparchive >/dev/null || fallo "falta apt-ftparchive: sudo apt install apt-utils"
  echo "    (antes conviene  sudo apt update  para bajar las versiones más recientes)"

  paso "Herrero"
  if [[ -n "$TARBALL" ]]; then cp "$TARBALL" "$dir/Herrero-linux-x64.tar.gz"
  else curl -fL --retry 3 -o "$dir/Herrero-linux-x64.tar.gz" "$RELEASE_URL"; fi
  cp "$0" "$dir/instalar-ubuntu.sh"; chmod +x "$dir/instalar-ubuntu.sh"
  local tmp; tmp="$(mktemp -d)"
  tar -xzf "$dir/Herrero-linux-x64.tar.gz" -C "$tmp"
  local tui="$tmp/herrero/herrero-tui"
  [[ -x "$tui" ]] || fallo "el paquete de Herrero no trae herrero-tui"
  ok "$(du -h "$dir/Herrero-linux-x64.tar.gz" | cut -f1) en Herrero-linux-x64.tar.gz"

  paso "Paquete CUDA de Herrero (ONNX Runtime GPU + cuDNN, cuBLAS…; ≈1,5 GB)"
  "$tui" --descargar-cuda "$dir/cuda"

  if [[ $WITH_MODELS == 1 ]]; then
    paso "Modelos de IA (comprensión y razonamiento)"
    "$tui" --descargar-modelos --modelos "$dir/modelos"
  fi
  rm -rf "$tmp"

  paso "Paquetes .deb (controlador NVIDIA, firmware, utilidades) con sus dependencias"
  local d; d="$(pick_driver)"
  echo "$d" > "$dir/driver.txt"
  echo "$KVER" > "$dir/kernel.txt"
  echo "$UBU_VER" > "$dir/ubuntu.txt"
  local list=("${BASE_PACKAGES[@]}" "${FIRMWARE_PACKAGES[@]}")
  # shellcheck disable=SC2207
  [[ $WITH_NVIDIA == 1 ]] && list+=($(nvidia_packages "$d"))
  echo "    Controlador NVIDIA: $d · kernel $KVER · Ubuntu $UBU_VER"
  echo "    Paquetes: ${list[*]}"
  # cierre de dependencias completo (también lo que ya trae este sistema: el destino
  # puede no tenerlo)
  local all
  all="$(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks \
         --no-replaces --no-enhances "${list[@]}" 2>/dev/null | grep -E '^[a-zA-Z0-9]' | sort -u)"
  local n=0 failed=()
  ( cd "$dir/debs"
    for p in $all; do
      ls "${p}"_*.deb >/dev/null 2>&1 && continue
      apt-get download "$p" >/dev/null 2>&1 || failed+=("$p")
      n=$((n + 1))
    done
    [[ ${#failed[@]} -eq 0 ]] || echo "    (virtuales o sin candidato, se omiten: ${failed[*]})"
  )
  ( cd "$dir/debs" && apt-ftparchive packages . > Packages && gzip -kf Packages )
  ok "$(ls "$dir/debs"/*.deb | wc -l) paquetes, $(du -sh "$dir/debs" | cut -f1)"

  paso "Listo: $(du -sh "$dir" | cut -f1) en $dir"
  echo "    En el equipo de destino (sin conexión):"
  echo "      sudo $dir/instalar-ubuntu.sh --desde $dir"
}

# ---------------------------------------------------------------------------
# Instalación
# ---------------------------------------------------------------------------
setup_apt() {
  if [[ -n "$OFFLINE" ]]; then
    [[ -f "$OFFLINE/debs/Packages" ]] || fallo "$OFFLINE/debs no es una carpeta preparada con --preparar"
    local kprep; kprep="$(cat "$OFFLINE/kernel.txt" 2>/dev/null || true)"
    if [[ -n "$kprep" && "$kprep" != "$KVER" ]]; then
      aviso "la carpeta se preparó con el kernel $kprep y este equipo usa $KVER: los módulos NVIDIA"
      aviso "pueden no cargar. Prepárala de nuevo en este equipo (o arranca ese kernel)."
    fi
    local list; list="$(mktemp)"
    echo "deb [trusted=yes] file:$OFFLINE/debs ./" > "$list"
    APT_OFFLINE_OPTS=(-o "Dir::Etc::SourceList=$list" -o "Dir::Etc::SourceParts=/dev/null"
                      -o "APT::Get::List-Cleanup=0")
    apt-get "${APT_OFFLINE_OPTS[@]}" update -qq
  else
    apt-get update -qq
  fi
}

apt_install() {
  DEBIAN_FRONTEND=noninteractive apt-get "${APT_OFFLINE_OPTS[@]}" install -y -qq --no-install-recommends "$@"
}

install_herrero() {
  paso "Herrero en $PREFIX"
  local src=""
  if [[ -n "$TARBALL" ]]; then src="$TARBALL"
  elif [[ -n "$OFFLINE" && -f "$OFFLINE/Herrero-linux-x64.tar.gz" ]]; then src="$OFFLINE/Herrero-linux-x64.tar.gz"
  fi
  local here; here="$(cd "$(dirname "$0")" && pwd)"
  local tmp; tmp="$(mktemp -d)"
  if [[ -z "$src" && -x "$here/herrero-tui" ]]; then
    # el script va dentro del paquete descomprimido
    cp -a "$here" "$tmp/herrero"
  else
    if [[ -z "$src" ]]; then
      src="$tmp/Herrero-linux-x64.tar.gz"
      curl -fL --retry 3 -o "$src" "$RELEASE_URL" || fallo "no se pudo descargar Herrero ($RELEASE_URL)"
    fi
    tar -xzf "$src" -C "$tmp"
  fi
  [[ -x "$tmp/herrero/herrero-tui" ]] || fallo "el paquete de Herrero no trae herrero-tui"
  rm -rf "$PREFIX.old"
  [[ -d "$PREFIX" ]] && mv "$PREFIX" "$PREFIX.old"
  mv "$tmp/herrero" "$PREFIX"
  rm -rf "$tmp" "$PREFIX.old"
  ln -sf "$PREFIX/herrero-tui" /usr/local/bin/herrero-tui
  [[ -x "$PREFIX/herrero" ]] && ln -sf "$PREFIX/herrero" /usr/local/bin/herrero
  ok "herrero-tui en /usr/local/bin"
}

install_nvidia() {
  if [[ $WITH_NVIDIA == 0 ]]; then return; fi
  if ! has_nvidia_pci; then
    ok "sin gráfica NVIDIA: la IA usará la CPU"
    WITH_NVIDIA=0
    return
  fi
  local d
  if [[ -n "$OFFLINE" && -z "$DRIVER" && -f "$OFFLINE/driver.txt" ]]; then d="$(cat "$OFFLINE/driver.txt")"
  else d="$(pick_driver)"; fi
  paso "Controlador NVIDIA $d headless (CUDA sin escritorio)"
  if command -v nvidia-smi >/dev/null && nvidia-smi >/dev/null 2>&1; then
    ok "ya hay un controlador NVIDIA funcionando: $(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader | head -1)"
    apt_install nvidia-modprobe || true
  else
    # shellcheck disable=SC2046
    apt_install $(nvidia_packages "$d") || fallo "no se pudo instalar el controlador NVIDIA $d"
  fi
  # módulos al arrancar y GPU siempre inicializada (sin escritorio nadie lo hace)
  printf 'nvidia\nnvidia_uvm\n' > /etc/modules-load.d/nvidia.conf
  systemctl enable nvidia-persistenced >/dev/null 2>&1 || aviso "no hay nvidia-persistenced"
  if [[ "$(mokutil --sb-state 2>/dev/null || true)" == *enabled* ]]; then
    ok "Secure Boot activo: se usan los módulos firmados por Canonical"
  fi
}

user_home() { getent passwd "$TARGET_USER" | cut -d: -f6; }

as_user() { sudo -u "$TARGET_USER" -H -- "$@"; }

install_user_parts() {
  local home; home="$(user_home)"
  usermod -aG video,render "$TARGET_USER" 2>/dev/null || true

  if [[ $WITH_NVIDIA == 1 ]]; then
    paso "Paquete CUDA de Herrero para $TARGET_USER"
    if [[ -n "$OFFLINE" ]]; then
      as_user /usr/local/bin/herrero-tui --instalar-cuda --desde "$OFFLINE/cuda" --motor auto \
        || aviso "no se pudo instalar el paquete CUDA (la IA usará la CPU)"
    else
      as_user /usr/local/bin/herrero-tui --instalar-cuda --motor auto \
        || aviso "no se pudo instalar el paquete CUDA (la IA usará la CPU)"
    fi
  fi

  if [[ $WITH_MODELS == 1 ]]; then
    paso "Modelos de IA"
    local mdir="$home/.local/share/es.herrero.herrero/models/reason"
    if [[ -n "$OFFLINE" && -d "$OFFLINE/modelos" ]]; then
      as_user mkdir -p "$mdir"
      cp -n "$OFFLINE/modelos/"* "$mdir/" 2>/dev/null || true
      chown -R "$TARGET_USER:" "$home/.local/share/es.herrero.herrero"
      ok "copiados a $mdir"
    else
      as_user /usr/local/bin/herrero-tui --descargar-modelos || aviso "no se pudieron descargar (se pueden bajar luego desde la TUI)"
    fi
  fi
}

text_mode_and_autologin() {
  [[ $TEXT_MODE == 1 ]] || return 0
  local home; home="$(user_home)"
  paso "Arranque en modo texto (sin X11) con Herrero en tty1"
  systemctl set-default multi-user.target >/dev/null
  ok "objetivo por defecto: multi-user.target (sin escritorio)"

  mkdir -p /etc/systemd/system/getty@tty1.service.d
  cat > /etc/systemd/system/getty@tty1.service.d/herrero.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $TARGET_USER --noclear %I \$TERM
EOF
  systemctl daemon-reload
  ok "inicio de sesión automático de $TARGET_USER en tty1 (las demás consolas piden contraseña)"

  # fuente de consola con tildes, η, cajas y flechas, grande para pantallas 1080p
  if [[ -f /etc/default/console-setup ]]; then
    sed -i -e 's/^CODESET=.*/CODESET="Uni2"/' -e 's/^FONTFACE=.*/FONTFACE="Terminus"/' \
           -e 's/^FONTSIZE=.*/FONTSIZE="16x32"/' /etc/default/console-setup
    setupcon --save-only >/dev/null 2>&1 || true
  fi

  # Herrero al entrar en tty1 (bash lee ~/.bash_profile si existe; si no, ~/.profile)
  local prof="$home/.profile"
  [[ -f "$home/.bash_profile" ]] && prof="$home/.bash_profile"
  touch "$prof"
  sed -i "/$MARK_BEGIN/,/$MARK_END/d" "$prof"
  cat >> "$prof" <<EOF
$MARK_BEGIN
if [ "\$(tty)" = "/dev/tty1" ] && [ -z "\${HERRERO_TUI_ACTIVA:-}" ] && [ -x /usr/local/bin/herrero-tui ]; then
  export HERRERO_TUI_ACTIVA=1
  /usr/local/bin/herrero-tui $TUI_ARGS
  echo
  echo "Has salido de Herrero. Escribe  herrero-tui  para volver, o  exit  para cerrar la sesión."
fi
$MARK_END
EOF
  chown "$TARGET_USER:" "$prof"
  ok "Herrero se abre en $prof"
}

undo() {
  [[ $EUID -eq 0 ]] || fallo "ejecútalo con sudo"
  paso "Volver al escritorio"
  systemctl set-default graphical.target >/dev/null
  rm -f /etc/systemd/system/getty@tty1.service.d/herrero.conf
  rmdir /etc/systemd/system/getty@tty1.service.d 2>/dev/null || true
  systemctl daemon-reload
  if [[ -n "$TARGET_USER" ]]; then
    local home; home="$(user_home)"
    for f in "$home/.profile" "$home/.bash_profile"; do
      [[ -f "$f" ]] && sed -i "/$MARK_BEGIN/,/$MARK_END/d" "$f"
    done
  fi
  ok "Hecho: al reiniciar vuelve el escritorio. Herrero sigue instalado en $PREFIX."
}

case "$MODE" in
  prepare) prepare; exit 0 ;;
  undo) undo; exit 0 ;;
esac

[[ $EUID -eq 0 ]] || fallo "ejecútalo con sudo: sudo $0 $*"
[[ -n "$TARGET_USER" && "$TARGET_USER" != "root" ]] || fallo "indica el usuario con --usuario NOMBRE"
getent passwd "$TARGET_USER" >/dev/null || fallo "no existe el usuario $TARGET_USER"
if [[ -n "$OFFLINE" ]]; then OFFLINE="$(cd "$OFFLINE" && pwd)"; fi

paso "Herrero para Ubuntu $UBU_VER (kernel $KVER) · usuario $TARGET_USER${OFFLINE:+ · sin conexión desde $OFFLINE}"
setup_apt
paso "Utilidades y firmware"
apt_install "${BASE_PACKAGES[@]}" || aviso "faltan algunas utilidades"
apt_install "${FIRMWARE_PACKAGES[@]}" || aviso "no se pudo actualizar el firmware"
install_nvidia
install_herrero
install_user_parts
text_mode_and_autologin

paso "Instalación terminada"
if [[ $WITH_NVIDIA == 1 ]]; then
  echo "    Tras reiniciar, comprueba la gráfica con:  herrero-tui --gpu"
fi
if [[ $TEXT_MODE == 1 ]]; then
  echo "    Al reiniciar, el equipo arranca sin escritorio y abre Herrero en la pantalla."
  echo "    Otras consolas: Ctrl+Alt+F2…F6. Para volver al escritorio:  sudo $PREFIX/instalar-ubuntu.sh --deshacer --usuario $TARGET_USER"
  read -r -t 30 -p "    ¿Reiniciar ahora? [s/N] " r || r=""
  [[ "${r,,}" == s* ]] && systemctl reboot
fi
