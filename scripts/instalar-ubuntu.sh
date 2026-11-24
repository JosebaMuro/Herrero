#!/usr/bin/env bash
# Suite de Joseba para Ubuntu LTS (22.04, 24.04, 26.04), también en modo texto sin X11:
#   Herrero (oficina técnica de estructuras: app y TUI), Oficina (Nexus-Office), Prueba (Studio
#   IA Local), Director de rol, Juegos (escritorio y TUI) y Programador (cuando tenga repositorio).
# Instala el controlador NVIDIA headless (CUDA sin escritorio), un venv de Python COMPARTIDO por
# los proyectos que admiten la misma versión, y deja el equipo arrancando en modo terminal con
# el lanzador de la suite en tty1 («Reiniciar con el escritorio» vuelve al escritorio).
#
#   sudo ./instalar-ubuntu.sh                       menú interactivo (flechas, Espacio, Enter)
#   sudo ./instalar-ubuntu.sh --sin-menu            instala con las opciones de la línea de órdenes
#   ./instalar-ubuntu.sh --preparar CARPETA         descarga TODO para instalar sin conexión (en el
#                                                   mismo Ubuntu y kernel, mejor en el propio equipo)
#   sudo ./instalar-ubuntu.sh --desde CARPETA       instala sin conexión desde esa carpeta
#   sudo ./instalar-ubuntu.sh --deshacer            vuelve al escritorio y quita el autologin
#   sudo herrero-modo escritorio|tui --reiniciar    cambia de modo (lo usan la TUI y las apps)
#
# Opciones:
#   --proyectos LISTA    herrero,oficina,prueba,director,juegos,programador (o «todos»)
#   --usuario NOMBRE     usuario que usa la suite (por defecto, quien llama a sudo)
#   --tarball FICHERO    Herrero-linux-x64.tar.gz ya descargado
#   --driver VERSIÓN     controlador NVIDIA, p. ej. 580-open (por defecto el recomendado)
#   --sin-nvidia         no instalar el controlador NVIDIA
#   --sin-modelos        no instalar modelos de IA
#   --modelos-prueba     (con --preparar) incluye los modelos de Ollama de Prueba (≈12 GB)
#   --red-local          Oficina y Prueba accesibles desde otros equipos de la red
#   --mantener-escritorio  instala sin quitar el escritorio ni poner autologin
#   --ascii              TUIs sin caracteres de dibujo (fuentes de consola básicas)
set -euo pipefail

SUITE=/opt/suite
PREFIX=/opt/herrero
GH=https://github.com/JosebaMuro
MARK_BEGIN="# >>> suite-tui >>>"
MARK_END="# <<< suite-tui <<<"

# ------------------------------------------------------------------ catálogo de proyectos
# tipo: bundle (binarios listos) · python (código + requisitos, va a un venv compartido) · nada
TODOS=(herrero oficina prueba director juegos programador)
declare -A NOMBRE DESC TIPO URL PYOK SUB REQS PUERTO
NOMBRE[herrero]="Herrero";            DESC[herrero]="Oficina técnica de estructuras metálicas (app y TUI, CUDA)"
TIPO[herrero]=bundle;                 URL[herrero]="$GH/Herrero/releases/latest/download/Herrero-linux-x64.tar.gz"
NOMBRE[oficina]="Oficina";            DESC[oficina]="Nexus-Office: oficina de IA local para pymes (web, puerto 8775)"
TIPO[oficina]=python;                 URL[oficina]="$GH/Nexus-AI/archive/refs/heads/main.tar.gz"
PYOK[oficina]="3.12 3.11";            SUB[oficina]="nexus-office"; REQS[oficina]="requirements.txt"; PUERTO[oficina]=8775
NOMBRE[prueba]="Prueba";              DESC[prueba]="Studio IA Local: multi-agente con Ollama (web, puerto 8765)"
TIPO[prueba]=python;                  URL[prueba]="$GH/Prueba/archive/refs/heads/main.tar.gz"
PYOK[prueba]="3.12";                  SUB[prueba]=""; REQS[prueba]="backend/requirements.txt"; PUERTO[prueba]=8765
NOMBRE[director]="Director de rol";   DESC[director]="Partidas de rol con IA local (solo escritorio)"
TIPO[director]=bundle;                URL[director]="$GH/Rol-master/releases/download/linux-latest/DirectorDeRol-linux-x64.tar.gz"
NOMBRE[juegos]="Juegos";              DESC[juegos]="Bloques, Punto de cruz, DOS, juegos libres y chat (escritorio y TUI)"
TIPO[juegos]=python;                  URL[juegos]="$GH/juegos/releases/download/linux-latest/juegos-linux.tar.gz"
PYOK[juegos]="3.12 3.11 3.10";        SUB[juegos]=""; REQS[juegos]="."
NOMBRE[programador]="Programador";    DESC[programador]="CodeForge AI (aún sin repositorio publicado)"
TIPO[programador]=nada

# ------------------------------------------------------------------ opciones
MODE=install
OFFLINE=""
PREP_DIR=""
TARGET_USER="${SUDO_USER:-}"
TARBALL=""
DRIVER=""
WITH_NVIDIA=1
WITH_MODELS=1
PRUEBA_MODELS=0
TEXT_MODE=1
LAN=0
TUI_ARGS=""
MENU=auto
SELECTED="herrero oficina prueba director juegos"

c_ok=$'\e[1;32m'; c_warn=$'\e[1;33m'; c_err=$'\e[1;31m'; c_h=$'\e[1;36m'; c_0=$'\e[0m'
paso() { echo "${c_h}==> $*${c_0}"; }
ok() { echo "${c_ok}    $*${c_0}"; }
aviso() { echo "${c_warn}    Aviso: $*${c_0}"; }
fallo() { echo "${c_err}Error: $*${c_0}" >&2; exit 1; }

ARGS_ORIG=("$@")
while [[ $# -gt 0 ]]; do
  case "$1" in
    --preparar) MODE=prepare; PREP_DIR="${2:?falta la carpeta}"; shift ;;
    --desde) OFFLINE="${2:?falta la carpeta}"; shift ;;
    --deshacer) MODE=undo ;;
    --proyectos) SELECTED="${2:?falta la lista}"; shift ;;
    --usuario) TARGET_USER="${2:?falta el usuario}"; shift ;;
    --tarball) TARBALL="${2:?falta el fichero}"; shift ;;
    --driver) DRIVER="${2:?falta la versión}"; shift ;;
    --sin-nvidia) WITH_NVIDIA=0 ;;
    --sin-modelos) WITH_MODELS=0 ;;
    --modelos-prueba) PRUEBA_MODELS=1 ;;
    --red-local) LAN=1 ;;
    --mantener-escritorio) TEXT_MODE=0 ;;
    --ascii) TUI_ARGS="--ascii" ;;
    --sin-menu) MENU=no ;;
    --menu) MENU=yes ;;
    -h|--help|--ayuda) sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fallo "opción desconocida: $1 (usa --ayuda)" ;;
  esac
  shift
done
SELECTED="${SELECTED//,/ }"
[[ "$SELECTED" == "todos" ]] && SELECTED="${TODOS[*]}"
# sin opciones y con terminal: menú
if [[ $MENU == auto ]]; then
  if [[ ${#ARGS_ORIG[@]} -eq 0 && -t 0 && -t 1 ]]; then MENU=yes; else MENU=no; fi
fi

# shellcheck disable=SC1091
. /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || aviso "pensado para Ubuntu LTS; este sistema es ${PRETTY_NAME:-desconocido}"
UBU_VER="${VERSION_ID:-24.04}"
KVER="$(uname -r)"
ARCH="$(dpkg --print-architecture)"
[[ "$ARCH" == "amd64" ]] || fallo "la suite para Linux es solo x86-64 (este equipo: $ARCH)"

sel() { [[ " $SELECTED " == *" $1 "* ]]; }

# ------------------------------------------------------------------ menú interactivo (whiptail)
W() { whiptail --backtitle "Suite · instalador para Ubuntu $UBU_VER" "$@" 3>&1 1>&2 2>&3; }

menu_interactivo() {
  command -v whiptail >/dev/null || { aviso "no está whiptail (sudo apt install whiptail): uso las opciones por defecto"; return; }
  local r
  while true; do
    r="$(W --title "Suite" --menu "Elige qué hacer (flechas y Enter):" 20 78 9 \
      instalar "Instalar ahora (con internet)" \
      desde "Instalar sin conexión desde una carpeta (--desde)" \
      preparar "Preparar una carpeta para instalar sin conexión (--preparar)" \
      proyectos "Proyectos: $(echo "$SELECTED" | wc -w) elegidos" \
      opciones "Usuario, NVIDIA, modo de arranque, red…" \
      deshacer "Quitar el modo terminal y volver al escritorio" \
      salir "Salir sin hacer nada")" || exit 0
    case "$r" in
      proyectos) menu_proyectos ;;
      opciones) menu_opciones ;;
      instalar) MODE=install; OFFLINE=""; if resumen; then return; fi ;;
      desde)
        OFFLINE="$(W --inputbox "Carpeta preparada con --preparar (p. ej. el USB):" 10 70 "${OFFLINE:-/media/$TARGET_USER}")" || continue
        MODE=install; if resumen; then return; fi ;;
      preparar)
        PREP_DIR="$(W --inputbox "Carpeta donde dejarlo todo (un USB con espacio: ≈5 GB, +12 GB con los modelos de Prueba):" \
          10 78 "${PREP_DIR:-/media/$TARGET_USER/suite-offline}")" || continue
        if W --defaultno --yesno "¿Incluir también los modelos de Ollama de Prueba (≈12 GB)?" 8 64; then PRUEBA_MODELS=1; fi
        MODE=prepare; return ;;
      deshacer) MODE=undo; return ;;
      salir) exit 0 ;;
    esac
  done
}

menu_proyectos() {
  local items=() p st r
  for p in "${TODOS[@]}"; do
    st=OFF; sel "$p" && st=ON
    [[ ${TIPO[$p]} == nada ]] && st=OFF
    items+=("$p" "${NOMBRE[$p]} · ${DESC[$p]}" "$st")
  done
  r="$(W --title "Proyectos" --checklist "Espacio marca o desmarca, Enter acepta.\nLos de Python comparten venv si admiten la misma versión." \
    20 100 8 "${items[@]}")" || return 0
  SELECTED="$(echo "$r" | tr -d '"')"
  if sel programador; then
    W --msgbox "Programador (CodeForge AI) todavía no tiene repositorio con código: se omite." 8 64
    SELECTED="${SELECTED//programador/}"
  fi
}

menu_opciones() {
  local r
  while true; do
    r="$(W --title "Opciones" --menu "Opciones de la instalación:" 20 80 9 \
      usuario "Usuario de la suite: ${TARGET_USER:-?}" \
      nvidia "Controlador NVIDIA: $([[ $WITH_NVIDIA == 1 ]] && echo "${DRIVER:-recomendado}" || echo no)" \
      arranque "Arranque: $([[ $TEXT_MODE == 1 ]] && echo 'modo terminal con la suite en tty1' || echo 'mantener el escritorio')" \
      modelos "Modelos de IA: $([[ $WITH_MODELS == 1 ]] && echo sí || echo no)" \
      red "Oficina y Prueba desde la red local: $([[ $LAN == 1 ]] && echo sí || echo no)" \
      ascii "TUIs solo con ASCII: $([[ -n $TUI_ARGS ]] && echo sí || echo no)" \
      volver "Volver")" || return 0
    case "$r" in
      usuario) TARGET_USER="$(W --inputbox "Usuario:" 8 50 "$TARGET_USER")" || true ;;
      nvidia)
        if W --yesno "¿Instalar el controlador NVIDIA headless (CUDA sin escritorio)?" 8 64; then
          WITH_NVIDIA=1
          DRIVER="$(W --inputbox "Versión (vacío = la recomendada por ubuntu-drivers; p. ej. 580-open):" 9 72 "$DRIVER")" || true
        else WITH_NVIDIA=0; fi ;;
      arranque) if W --yesno "¿Arrancar en modo terminal (sin X11) con la suite en tty1?" 8 66; then TEXT_MODE=1; else TEXT_MODE=0; fi ;;
      modelos) if W --yesno "¿Instalar los modelos de IA (Herrero, Juegos…)?" 8 60; then WITH_MODELS=1; else WITH_MODELS=0; fi ;;
      red) if W --defaultno --yesno "¿Abrir Oficina y Prueba a la red local? (sin escritorio es la forma de usarlas desde otro equipo)" 9 72
           then LAN=1; else LAN=0; fi ;;
      ascii) if W --defaultno --yesno "¿TUIs solo con ASCII? (si la consola muestra rombos en vez de cajas)" 8 66
             then TUI_ARGS="--ascii"; else TUI_ARGS=""; fi ;;
      volver) return 0 ;;
    esac
  done
}

resumen() {
  local t nv=no
  [[ $WITH_NVIDIA == 1 ]] && nv="${DRIVER:-recomendado}"
  t="Proyectos: $SELECTED\nUsuario: $TARGET_USER\nNVIDIA: $nv"
  t+="\nArranque: $([[ $TEXT_MODE == 1 ]] && echo 'modo terminal (sin X11)' || echo escritorio)"
  t+="\nOrigen: ${OFFLINE:-internet}"
  W --title "Resumen" --yesno "$t\n\n¿Instalar?" 16 72
}

# ------------------------------------------------------------------ utilidades
has_nvidia_pci() {
  local d
  for d in /sys/bus/pci/devices/*; do
    [[ -r "$d/vendor" && -r "$d/class" ]] || continue
    [[ "$(cat "$d/vendor")" == "0x10de" && "$(cat "$d/class")" == 0x03* ]] && return 0
  done
  return 1
}

pick_driver() {
  if [[ -n "$DRIVER" ]]; then echo "$DRIVER"; return; fi
  if command -v ubuntu-drivers >/dev/null 2>&1; then
    local rec
    rec="$(ubuntu-drivers devices 2>/dev/null | awk '/recommended/ {print $3}' | sed -n 's/^nvidia-driver-//p' | head -1)"
    if [[ -n "$rec" ]]; then echo "$rec"; return; fi
  fi
  echo "580-open"
}

APT_OFFLINE_OPTS=()
# Paquetes NVIDIA headless (CUDA sin X11) + Vulkan para la versión $1 («580-open»).
nvidia_packages() {
  local d="$1" base="${1%-open}"
  local pkgs=("nvidia-headless-no-dkms-$d" "nvidia-utils-$base" "nvidia-modprobe" "libnvidia-gl-$base" "libvulkan1")
  # módulos precompilados y firmados (Secure Boot): el del kernel actual y el metapaquete de su serie
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

BASE_PACKAGES=(unzip pciutils kbd console-setup console-setup-linux ca-certificates curl mokutil whiptail jq)
FIRMWARE_PACKAGES=(linux-firmware intel-microcode amd64-microcode)
JUEGOS_PACKAGES=(dosbox zenity libsdl2-2.0-0)

dl() { # dl URL DESTINO
  curl -fL --retry 3 --retry-delay 3 -o "$2" "$1"
}

gh_asset() { # gh_asset owner/repo REGEX: URL del último asset que cumple REGEX
  curl -fsSL -H 'User-Agent: suite-instalador' "https://api.github.com/repos/$1/releases/latest" \
    | jq -r --arg re "$2" '.assets[].browser_download_url | select(test($re))' | head -1
}

# CPython autónomo (python-build-standalone) de la versión $1 → URL
python_url() {
  gh_asset astral-sh/python-build-standalone "cpython-${1//./\\.}\\.[0-9]+\\+[0-9]+-x86_64-unknown-linux-gnu-install_only_stripped\\.tar\\.gz$"
}

# ------------------------------------------------------------------ venvs compartidos
# Agrupa los proyectos de Python por una versión que todos admitan, empezando por la que
# cubre a más proyectos: así comparten un único venv (y su espacio en disco).
declare -A VENV_OF VERSION_OF
plan_venvs() {
  local pend=() p v best bestn n
  for p in $SELECTED; do [[ ${TIPO[$p]} == python ]] && pend+=("$p"); done
  while [[ ${#pend[@]} -gt 0 ]]; do
    best=""; bestn=0
    for v in 3.12 3.13 3.11 3.10; do
      n=0
      for p in "${pend[@]}"; do [[ " ${PYOK[$p]} " == *" $v "* ]] && n=$((n + 1)); done
      if [[ $n -gt $bestn ]]; then best=$v; bestn=$n; fi
    done
    [[ -n "$best" ]] || fallo "no hay versión de Python común para: ${pend[*]}"
    local rest=()
    for p in "${pend[@]}"; do
      if [[ " ${PYOK[$p]} " == *" $best "* ]]; then VENV_OF[$p]="$SUITE/venv/py$best"; VERSION_OF[$p]=$best
      else rest+=("$p"); fi
    done
    pend=("${rest[@]+"${rest[@]}"}")
  done
}

venv_groups() { # venvs distintos, uno por línea
  local p
  for p in "${!VENV_OF[@]}"; do echo "${VENV_OF[$p]}"; done | sort -u
}

# ------------------------------------------------------------------ preparar sin conexión
prepare() {
  local dir="$PREP_DIR"
  mkdir -p "$dir"/{debs,proyectos,python,wheels,cuda,modelos,llama.cpp}
  dir="$(cd "$dir" && pwd)"
  command -v apt-ftparchive >/dev/null || fallo "falta apt-ftparchive: sudo apt install apt-utils"
  command -v jq >/dev/null || fallo "falta jq: sudo apt install jq"
  echo "    (antes conviene  sudo apt update  para bajar las versiones más recientes)"
  cp "$0" "$dir/instalar-ubuntu.sh"; chmod +x "$dir/instalar-ubuntu.sh"
  echo "$SELECTED" > "$dir/proyectos.txt"

  local p
  for p in $SELECTED; do
    [[ ${TIPO[$p]} == nada ]] && { aviso "${NOMBRE[$p]}: ${DESC[$p]}"; continue; }
    paso "${NOMBRE[$p]}"
    if [[ $p == herrero && -n "$TARBALL" ]]; then cp "$TARBALL" "$dir/proyectos/herrero.tar.gz"
    else dl "${URL[$p]}" "$dir/proyectos/$p.tar.gz" || fallo "no se pudo descargar ${NOMBRE[$p]}"; fi
    ok "$(du -h "$dir/proyectos/$p.tar.gz" | cut -f1)"
  done

  local tmp; tmp="$(mktemp -d)"
  if sel herrero; then
    tar -xzf "$dir/proyectos/herrero.tar.gz" -C "$tmp"
    local tui="$tmp/herrero/herrero-tui"
    paso "Paquete CUDA de Herrero (≈1,5 GB)"
    "$tui" --descargar-cuda "$dir/cuda"
    if [[ $WITH_MODELS == 1 ]]; then
      paso "Modelos de IA de Herrero"
      "$tui" --descargar-modelos --modelos "$dir/modelos/herrero"
    fi
  fi

  plan_venvs
  local v
  for v in $(for p in "${!VERSION_OF[@]}"; do echo "${VERSION_OF[$p]}"; done | sort -u); do
    paso "Python $v autónomo y ruedas (wheels) de sus proyectos"
    local url; url="$(python_url "$v")"
    [[ -n "$url" ]] || fallo "no encuentro CPython $v en python-build-standalone"
    dl "$url" "$dir/python/cpython-$v.tar.gz"
    mkdir -p "$tmp/py$v"
    tar -xzf "$dir/python/cpython-$v.tar.gz" -C "$tmp/py$v"
    local py="$tmp/py$v/python/bin/python3" reqs=()
    for p in "${!VERSION_OF[@]}"; do
      [[ ${VERSION_OF[$p]} == "$v" ]] || continue
      mkdir -p "$tmp/src-$p"; tar -xzf "$dir/proyectos/$p.tar.gz" -C "$tmp/src-$p" --strip-components=1
      if [[ ${REQS[$p]} == "." ]]; then reqs+=("$tmp/src-$p${SUB[$p]:+/${SUB[$p]}}")
      else reqs+=(-r "$tmp/src-$p${SUB[$p]:+/${SUB[$p]}}/${REQS[$p]}"); fi
    done
    "$py" -m pip download -q --dest "$dir/wheels/py$v" "${reqs[@]}" pip setuptools wheel \
      || fallo "no se pudieron descargar las ruedas de Python $v"
    ok "$(find "$dir/wheels/py$v" -type f | wc -l) ruedas"
  done

  if sel juegos; then
    paso "llama.cpp para el chat de Juegos (Vulkan y CPU)"
    local u var
    for var in vulkan cpu; do
      if [[ $var == vulkan ]]; then u="$(gh_asset ggml-org/llama.cpp 'bin-ubuntu-vulkan-x64\.zip$' || true)"
      else u="$(gh_asset ggml-org/llama.cpp 'bin-ubuntu-x64\.zip$' || true)"; fi
      if [[ -n "$u" ]]; then dl "$u" "$dir/llama.cpp/$var.zip" || aviso "no se pudo bajar llama.cpp $var"
      else aviso "no encuentro llama.cpp $var"; fi
    done
  fi

  if sel prueba; then
    paso "Ollama para Prueba"
    dl "https://ollama.com/download/ollama-linux-amd64.tgz" "$dir/ollama-linux-amd64.tgz" || aviso "no se pudo bajar Ollama"
    if [[ $PRUEBA_MODELS == 1 && -f "$dir/ollama-linux-amd64.tgz" ]]; then
      paso "Modelos de Ollama de Prueba (≈12 GB)"
      mkdir -p "$tmp/ollama" "$dir/ollama-models"
      tar -xzf "$dir/ollama-linux-amd64.tgz" -C "$tmp/ollama"
      OLLAMA_MODELS="$dir/ollama-models" OLLAMA_HOST=127.0.0.1:11999 "$tmp/ollama/bin/ollama" serve >/dev/null 2>&1 &
      local opid=$! m
      sleep 3
      for m in qwen3:8b qwen3-vl:8b-instruct qwen3-embedding:0.6b; do
        OLLAMA_HOST=127.0.0.1:11999 "$tmp/ollama/bin/ollama" pull "$m" || aviso "no se pudo bajar $m"
      done
      kill "$opid" 2>/dev/null || true
    fi
  fi

  paso "Paquetes .deb (controlador NVIDIA, firmware, utilidades) con sus dependencias"
  local d; d="$(pick_driver)"
  echo "$d" > "$dir/driver.txt"
  echo "$KVER" > "$dir/kernel.txt"
  echo "$UBU_VER" > "$dir/ubuntu.txt"
  local list=("${BASE_PACKAGES[@]}" "${FIRMWARE_PACKAGES[@]}")
  # shellcheck disable=SC2207
  [[ $WITH_NVIDIA == 1 ]] && list+=($(nvidia_packages "$d"))
  sel juegos && list+=("${JUEGOS_PACKAGES[@]}")
  sel director && list+=(libgstreamer1.0-0 gstreamer1.0-plugins-base gstreamer1.0-plugins-good libgtk-3-0)
  echo "    Controlador NVIDIA: $d · kernel $KVER · Ubuntu $UBU_VER"
  local all
  all="$(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks \
         --no-replaces --no-enhances "${list[@]}" 2>/dev/null | grep -E '^[a-zA-Z0-9]' | sort -u)"
  ( cd "$dir/debs"
    for p in $all; do
      ls "${p}"_*.deb >/dev/null 2>&1 && continue
      apt-get download "$p" >/dev/null 2>&1 || true
    done
    apt-ftparchive packages . > Packages
  )
  ok "$(find "$dir/debs" -name '*.deb' | wc -l) paquetes, $(du -sh "$dir/debs" | cut -f1)"
  paso "Listo: $(du -sh "$dir" | cut -f1) en $dir"
  echo "    En el equipo de destino, sin conexión:  sudo $dir/instalar-ubuntu.sh --desde $dir"
}

# ------------------------------------------------------------------ instalación
setup_apt() {
  if [[ -n "$OFFLINE" ]]; then
    [[ -f "$OFFLINE/debs/Packages" ]] || fallo "$OFFLINE no es una carpeta preparada con --preparar"
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

user_home() { getent passwd "$TARGET_USER" | cut -d: -f6; }
as_user() { sudo -u "$TARGET_USER" -H -- "$@"; }

source_tar() { # source_tar PROYECTO → ruta del tar (descargándolo si hace falta)
  local p="$1" f
  if [[ $p == herrero && -n "$TARBALL" ]]; then echo "$TARBALL"; return; fi
  if [[ -n "$OFFLINE" ]]; then
    f="$OFFLINE/proyectos/$p.tar.gz"
    [[ -f "$f" ]] || fallo "falta $f (prepara la carpeta con este proyecto)"
    echo "$f"; return
  fi
  f="$(mktemp --suffix=.tar.gz)"
  dl "${URL[$p]}" "$f" >&2 || fallo "no se pudo descargar ${NOMBRE[$p]} (${URL[$p]})"
  echo "$f"
}

install_nvidia() {
  [[ $WITH_NVIDIA == 1 ]] || return 0
  if ! has_nvidia_pci; then ok "sin gráfica NVIDIA: la IA usará la CPU"; WITH_NVIDIA=0; return; fi
  local d
  if [[ -n "$OFFLINE" && -z "$DRIVER" && -f "$OFFLINE/driver.txt" ]]; then d="$(cat "$OFFLINE/driver.txt")"
  else d="$(pick_driver)"; fi
  paso "Controlador NVIDIA $d headless (CUDA sin escritorio) y Vulkan"
  if command -v nvidia-smi >/dev/null && nvidia-smi >/dev/null 2>&1; then
    ok "ya hay un controlador NVIDIA funcionando: $(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader | head -1)"
    apt_install nvidia-modprobe libvulkan1 || true
  else
    # shellcheck disable=SC2046
    apt_install $(nvidia_packages "$d") || fallo "no se pudo instalar el controlador NVIDIA $d"
  fi
  printf 'nvidia\nnvidia_uvm\n' > /etc/modules-load.d/nvidia.conf
  systemctl enable nvidia-persistenced >/dev/null 2>&1 || aviso "no hay nvidia-persistenced"
  if [[ "$(mokutil --sb-state 2>/dev/null || true)" == *enabled* ]]; then
    ok "Secure Boot activo: se usan los módulos firmados por Canonical"
  fi
}

install_bundle() { # Herrero, Director de rol
  local p="$1" dest="$SUITE/$1" tmp t
  paso "${NOMBRE[$p]} en $dest"
  t="$(source_tar "$p")"
  tmp="$(mktemp -d)"
  tar -xzf "$t" -C "$tmp"
  local top; top="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -1)"
  [[ -n "$top" ]] || fallo "el paquete de ${NOMBRE[$p]} está vacío"
  mkdir -p "$SUITE"
  if [[ -d "$dest" ]]; then mv "$dest" "$dest.old"; fi
  mv "$top" "$dest"
  rm -rf "$tmp" "$dest.old"
  case "$p" in
    herrero)
      [[ -x "$dest/herrero-tui" ]] || fallo "el paquete de Herrero no trae herrero-tui"
      if [[ -d "$PREFIX" && ! -L "$PREFIX" ]]; then mv "$PREFIX" "$PREFIX.antiguo"; fi
      ln -sfn "$dest" "$PREFIX"
      ln -sf "$dest/herrero-tui" /usr/local/bin/herrero-tui
      if [[ -x "$dest/herrero" ]]; then ln -sf "$dest/herrero" /usr/local/bin/herrero; fi
      ok "herrero y herrero-tui en /usr/local/bin" ;;
    director)
      local exe; exe="$(find "$dest" -maxdepth 1 -type f -executable ! -name '*.so*' | head -1)"
      if [[ -n "$exe" ]]; then ln -sf "$exe" /usr/local/bin/director-de-rol; fi
      apt_install libgstreamer1.0-0 gstreamer1.0-plugins-base gstreamer1.0-plugins-good libgtk-3-0 >/dev/null || true
      ok "director-de-rol (escritorio)" ;;
  esac
}

python_for() { # CPython autónomo de la versión $1 en $SUITE/python/$1
  local v="$1" d="$SUITE/python/$1" t
  if [[ -x "$d/bin/python3" ]]; then echo "$d/bin/python3"; return; fi
  if [[ -n "$OFFLINE" ]]; then t="$OFFLINE/python/cpython-$v.tar.gz"
  else
    local url; url="$(python_url "$v" || true)"
    t="$(mktemp --suffix=.tar.gz)"
    if [[ -z "$url" ]] || ! dl "$url" "$t" >&2; then
      # sin la API de GitHub: el Python del sistema si es esa versión
      if command -v "python$v" >/dev/null; then
        apt_install "python$v-venv" >&2 || true
        command -v "python$v"; return
      fi
      fallo "no se pudo conseguir Python $v"
    fi
  fi
  mkdir -p "$d"; tar -xzf "$t" -C "$d" --strip-components=1
  echo "$d/bin/python3"
}

install_python_projects() {
  plan_venvs
  [[ ${#VENV_OF[@]} -gt 0 ]] || return 0
  local p venv
  for p in "${!VENV_OF[@]}"; do
    paso "${NOMBRE[$p]} en $SUITE/$p"
    local t tmp; t="$(source_tar "$p")"; tmp="$(mktemp -d)"
    tar -xzf "$t" -C "$tmp" --strip-components=1
    mkdir -p "$SUITE"
    local new="$SUITE/$p.nuevo"
    if [[ -n "${SUB[$p]}" ]]; then mv "$tmp/${SUB[$p]}" "$new"; else mv "$tmp" "$new"; fi
    # conserva los datos de una instalación anterior
    if [[ -d "$SUITE/$p/data" && ! -d "$new/data" ]]; then mv "$SUITE/$p/data" "$new/data"; fi
    if [[ -d "$SUITE/$p" ]]; then mv "$SUITE/$p" "$SUITE/$p.old"; fi
    mv "$new" "$SUITE/$p"
    rm -rf "$SUITE/$p.old" "$tmp"
    chown -R "$TARGET_USER:" "$SUITE/$p"
  done
  # un venv por grupo de versión; si las dependencias chocan, cada proyecto va aparte
  while read -r venv; do
    [[ -n "$venv" ]] || continue
    local v="${venv##*/py}" py members=() reqs=()
    for p in "${!VENV_OF[@]}"; do [[ ${VENV_OF[$p]} == "$venv" ]] && members+=("$p"); done
    paso "venv compartido de Python $v: ${members[*]}"
    py="$(python_for "$v")"
    [[ -x "$venv/bin/python" ]] || "$py" -m venv "$venv"
    local PIP=("$venv/bin/python" -m pip install -q --disable-pip-version-check)
    [[ -n "$OFFLINE" ]] && PIP+=(--no-index --find-links "$OFFLINE/wheels/py$v")
    "${PIP[@]}" --upgrade pip setuptools wheel >/dev/null || true
    for p in "${members[@]}"; do
      if [[ ${REQS[$p]} == "." ]]; then reqs+=("$SUITE/$p"); else reqs+=(-r "$SUITE/$p/${REQS[$p]}"); fi
    done
    if "${PIP[@]}" "${reqs[@]}"; then
      ok "${members[*]} comparten $venv ($(du -sh "$venv" | cut -f1))"
    else
      aviso "las dependencias no caben juntas: cada proyecto en su propio venv"
      for p in "${members[@]}"; do
        local own="$SUITE/venv/$p-py$v"
        "$py" -m venv "$own"
        local P2=("$own/bin/python" -m pip install -q --disable-pip-version-check)
        [[ -n "$OFFLINE" ]] && P2+=(--no-index --find-links "$OFFLINE/wheels/py$v")
        if [[ ${REQS[$p]} == "." ]]; then "${P2[@]}" "$SUITE/$p"; else "${P2[@]}" -r "$SUITE/$p/${REQS[$p]}"; fi
        VENV_OF[$p]="$own"
      done
    fi
  done < <(venv_groups)
  for p in "${!VENV_OF[@]}"; do setup_python_project "$p" "${VENV_OF[$p]}"; done
}

service() { # service NOMBRE DIRECTORIO [VAR=VALOR…] -- ORDEN…
  local name="$1" wd="$2"; shift 2
  local env=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do env+=("Environment=$1"); shift; done
  shift
  {
    echo "[Unit]"; echo "Description=Suite · $name"; echo "After=network-online.target"
    echo "[Service]"; echo "User=$TARGET_USER"; echo "WorkingDirectory=$wd"
    printf '%s\n' "${env[@]+"${env[@]}"}"
    echo "ExecStart=$*"; echo "Restart=on-failure"
    echo "[Install]"; echo "WantedBy=multi-user.target"
  } > "/etc/systemd/system/suite-$name.service"
  systemctl daemon-reload
  systemctl enable "suite-$name" >/dev/null 2>&1 || true
  systemctl restart "suite-$name" || aviso "suite-$name no arrancó (journalctl -u suite-$name)"
}

setup_python_project() {
  local p="$1" venv="$2" host=127.0.0.1
  [[ $LAN == 1 ]] && host=0.0.0.0
  case "$p" in
    oficina)
      service oficina "$SUITE/oficina" -- "$venv/bin/python" -m nexus run --no-browser --host "$host" --port 8775
      ok "Oficina: http://$host:8775 (servicio suite-oficina)" ;;
    prueba)
      install_ollama
      mkdir -p "$SUITE/prueba/data" "$SUITE/prueba/workspace"; chown -R "$TARGET_USER:" "$SUITE/prueba"
      service prueba "$SUITE/prueba/backend" "HOST=$host" "PORT=8765" "DATA_DIR=$SUITE/prueba/data" \
        "WORKSPACE_DIR=$SUITE/prueba/workspace" "FRONTEND_DIR=$SUITE/prueba/frontend" -- "$venv/bin/python" -m app.main
      ok "Prueba: http://$host:8765 (servicio suite-prueba; los modelos se bajan desde su pestaña Modelos)" ;;
    juegos)
      apt_install "${JUEGOS_PACKAGES[@]}" >/dev/null || aviso "no se pudieron instalar DOSBox o zenity"
      local b
      for b in juegos juegos-tui juegos-x11; do
        printf '#!/bin/sh\nJUEGOS_DATOS=%s/juegos/datos exec %s/bin/%s "$@"\n' "$SUITE" "$venv" "$b" > "/usr/local/bin/$b"
        chmod 755 "/usr/local/bin/$b"
      done
      install_llama
      ok "juegos, juegos-tui y juegos-x11 en /usr/local/bin" ;;
  esac
}

install_ollama() {
  if command -v ollama >/dev/null; then ok "Ollama ya está instalado"; return; fi
  paso "Ollama (motor de IA de Prueba)"
  if [[ -n "$OFFLINE" ]]; then
    [[ -f "$OFFLINE/ollama-linux-amd64.tgz" ]] || { aviso "no hay Ollama en la carpeta"; return; }
    tar -xzf "$OFFLINE/ollama-linux-amd64.tgz" -C /usr
    id ollama >/dev/null 2>&1 || useradd -r -s /bin/false -U -m -d /usr/share/ollama ollama
    cat > /etc/systemd/system/ollama.service <<'UNIT'
[Unit]
Description=Ollama
After=network-online.target
[Service]
ExecStart=/usr/bin/ollama serve
User=ollama
Group=ollama
Restart=always
Environment="OLLAMA_FLASH_ATTENTION=1" "OLLAMA_KV_CACHE_TYPE=q8_0"
[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload; systemctl enable --now ollama >/dev/null 2>&1 || true
    if [[ -d "$OFFLINE/ollama-models" ]]; then
      mkdir -p /usr/share/ollama/.ollama/models
      cp -rn "$OFFLINE/ollama-models/." /usr/share/ollama/.ollama/models/
      chown -R ollama:ollama /usr/share/ollama/.ollama
      ok "modelos de Prueba copiados"
    fi
  else
    curl -fsSL https://ollama.com/install.sh | sh || aviso "no se pudo instalar Ollama"
  fi
}

install_llama() {
  local d="$SUITE/llama.cpp" var z u
  for var in vulkan cpu; do
    [[ -x "$d/$var/llama-server" ]] && continue
    if [[ -n "$OFFLINE" ]]; then
      z="$OFFLINE/llama.cpp/$var.zip"
      [[ -f "$z" ]] || continue
    else
      if [[ $var == vulkan ]]; then u="$(gh_asset ggml-org/llama.cpp 'bin-ubuntu-vulkan-x64\.zip$' || true)"
      else u="$(gh_asset ggml-org/llama.cpp 'bin-ubuntu-x64\.zip$' || true)"; fi
      [[ -n "$u" ]] || continue
      z="$(mktemp --suffix=.zip)"
      dl "$u" "$z" || continue
    fi
    local tmp srv; tmp="$(mktemp -d)"; unzip -q -o "$z" -d "$tmp"
    srv="$(find "$tmp" -name llama-server -type f | head -1)"
    if [[ -n "$srv" ]]; then
      mkdir -p "$d/$var"; cp -a "$(dirname "$srv")/." "$d/$var/"
      ok "llama.cpp ($var) para el chat de Juegos"
    fi
    rm -rf "$tmp"
  done
}

install_user_parts() {
  local home; home="$(user_home)"
  usermod -aG video,render "$TARGET_USER" 2>/dev/null || true
  if sel herrero && [[ $WITH_NVIDIA == 1 ]]; then
    paso "Paquete CUDA de Herrero para $TARGET_USER"
    if [[ -n "$OFFLINE" ]]; then
      as_user /usr/local/bin/herrero-tui --instalar-cuda --desde "$OFFLINE/cuda" --motor auto || aviso "paquete CUDA no instalado (la IA usará la CPU)"
    else
      as_user /usr/local/bin/herrero-tui --instalar-cuda --motor auto || aviso "paquete CUDA no instalado (la IA usará la CPU)"
    fi
  fi
  if sel herrero && [[ $WITH_MODELS == 1 ]]; then
    paso "Modelos de IA de Herrero"
    local mdir="$home/.local/share/es.herrero.herrero/models/reason"
    if [[ -n "$OFFLINE" && -d "$OFFLINE/modelos/herrero" ]]; then
      as_user mkdir -p "$mdir"; cp -n "$OFFLINE/modelos/herrero/"* "$mdir/" 2>/dev/null || true
      chown -R "$TARGET_USER:" "$home/.local/share/es.herrero.herrero"; ok "copiados a $mdir"
    else
      as_user /usr/local/bin/herrero-tui --descargar-modelos || aviso "no se pudieron descargar (luego, desde la TUI)"
    fi
  fi
}

# Lanzador de la suite en el modo terminal (tty1) y accesos del escritorio.
install_launcher() {
  paso "Lanzador de la suite (modo terminal) y accesos del escritorio"
  cat > /usr/local/bin/suite <<'SUITE_EOF'
#!/usr/bin/env bash
# Lanzador de la suite en modo terminal: elige programa con las flechas y Enter.
TUI_ARGS="${SUITE_TUI_ARGS:-}"
ip_local() { hostname -I 2>/dev/null | awk '{print $1}'; }
estado() { if systemctl is-active "suite-$1" >/dev/null 2>&1; then echo "en marcha"; else echo "parado"; fi; }
while true; do
  items=()
  [[ -x /usr/local/bin/herrero-tui ]] && items+=(herrero "Herrero · oficina técnica de estructuras")
  [[ -x /usr/local/bin/juegos-tui ]] && items+=(juegos "Juegos · Bloques, Punto de cruz, DOS, chat")
  systemctl cat suite-oficina >/dev/null 2>&1 && items+=(oficina "Oficina (web) · $(estado oficina)")
  systemctl cat suite-prueba >/dev/null 2>&1 && items+=(prueba "Prueba (web) · $(estado prueba)")
  [[ -e /usr/local/bin/director-de-rol ]] && items+=(director "Director de rol (solo escritorio)")
  items+=(gpu "Diagnóstico de la gráfica (CUDA)" escritorio "Reiniciar con el escritorio (X11)"
          shell "Terminal (escribe suite para volver)" apagar "Apagar el equipo")
  r=$(whiptail --title "Suite" --backtitle "$(hostname) · $(ip_local)" --cancel-button "Terminal" \
      --menu "Elige con las flechas y Enter:" 20 72 11 "${items[@]}" 3>&1 1>&2 2>&3) || r=shell
  case "$r" in
    herrero) herrero-tui $TUI_ARGS ;;
    juegos) JUEGOS_ASCII=${TUI_ARGS:+1} juegos-tui ;;
    oficina|prueba)
      p=$([[ $r == oficina ]] && echo 8775 || echo 8765)
      whiptail --title "$r" --msgbox "Es una aplicación web. Ábrela en un navegador:\n\n  · en este equipo, con el escritorio: http://127.0.0.1:$p\n  · desde otro equipo de la red (si se activó): http://$(ip_local):$p\n\nServicio suite-$r: $(estado "$r")." 14 72 ;;
    director) whiptail --msgbox "Director de rol necesita el escritorio: elige «Reiniciar con el escritorio»." 9 66 ;;
    gpu) clear; herrero-tui --gpu 2>/dev/null || nvidia-smi; read -rp "Enter para volver… " _ ;;
    escritorio)
      if whiptail --yesno "¿Reiniciar con el escritorio (X11)? Arrancará así hasta que vuelvas al modo terminal." 9 72; then
        sudo -n /usr/local/sbin/herrero-modo escritorio --reiniciar || read -rp "No se pudo (¿sin escritorio instalado?). Enter… " _
      fi ;;
    apagar) whiptail --yesno "¿Apagar el equipo?" 7 40 && systemctl poweroff ;;
    shell) clear; echo "Escribe  suite  para volver al menú."; exit 0 ;;
  esac
done
SUITE_EOF
  chmod 755 /usr/local/bin/suite
  local a=/usr/share/applications
  mkdir -p "$a"
  dsk() { # dsk ID NOMBRE COMENTARIO ORDEN ICONO CATEGORÍAS
    printf '[Desktop Entry]\nType=Application\nName=%s\nComment=%s\nExec=%s\nIcon=%s\nTerminal=false\nCategories=%s\n' \
      "$2" "$3" "$4" "$5" "$6" > "$a/suite-$1.desktop"
  }
  if sel herrero; then dsk herrero "Herrero" "Oficina técnica de estructuras metálicas" /usr/local/bin/herrero applications-engineering "Office;Engineering;"; fi
  if sel juegos; then dsk juegos "Juegos Reunidos" "Bloques, Punto de cruz, DOS y más" /usr/local/bin/juegos-x11 applications-games "Game;"; fi
  if sel director; then dsk director "Director de rol" "Partidas de rol con IA local" /usr/local/bin/director-de-rol applications-games "Game;RolePlaying;"; fi
  if sel oficina; then dsk oficina "Oficina (Nexus-Office)" "Oficina de IA local" "xdg-open http://127.0.0.1:8775" applications-office "Office;"; fi
  if sel prueba; then dsk prueba "Prueba (Studio IA Local)" "Estudio de IA local" "xdg-open http://127.0.0.1:8765" applications-science "Office;"; fi
  dsk modo-terminal "Reiniciar en modo terminal" "Reinicia sin escritorio, con la suite en la pantalla" \
    "sh -c 'sudo -n /usr/local/sbin/herrero-modo tui --reiniciar || pkexec /usr/local/sbin/herrero-modo tui --reiniciar'" \
    utilities-terminal "System;"
  ok "suite en /usr/local/bin y accesos en el menú del escritorio"
}

install_mode_helper() {
  paso "Cambio de modo de arranque (escritorio / terminal)"
  cat > /usr/local/sbin/herrero-modo <<'MODO'
#!/bin/sh
# herrero-modo escritorio|tui [--reiniciar]
# Deja el arranque con escritorio (graphical.target) o en modo terminal con la suite
# (multi-user.target) y, con --reiniciar, reinicia. Instalado por instalar-ubuntu.sh.
set -e
case "$1" in
  escritorio|x11) t=graphical.target ;;
  tui|terminal) t=multi-user.target ;;
  *) echo "uso: herrero-modo escritorio|tui [--reiniciar]" >&2; exit 2 ;;
esac
if [ "$t" = graphical.target ] && ! systemctl cat display-manager.service >/dev/null 2>&1; then
  echo "No hay escritorio instalado (sudo apt install ubuntu-desktop-minimal)" >&2
  exit 3
fi
systemctl set-default "$t" >/dev/null
if [ "${2:-}" = "--reiniciar" ]; then systemctl reboot; fi
exit 0
MODO
  chmod 0755 /usr/local/sbin/herrero-modo
  ln -sf /usr/local/sbin/herrero-modo /usr/local/sbin/suite-modo
  local rule; rule="$(mktemp)"
  echo "$TARGET_USER ALL=(root) NOPASSWD: /usr/local/sbin/herrero-modo" > "$rule"
  if visudo -cf "$rule" >/dev/null; then
    install -m 0440 "$rule" /etc/sudoers.d/herrero-modo
    ok "herrero-modo: $TARGET_USER puede cambiar de modo y reiniciar sin contraseña"
  else
    aviso "no se pudo crear la regla de sudo; el cambio de modo pedirá contraseña"
  fi
  rm -f "$rule"
}

text_mode_and_autologin() {
  [[ $TEXT_MODE == 1 ]] || return 0
  local home; home="$(user_home)"
  paso "Arranque en modo terminal (sin X11) con la suite en tty1"
  systemctl set-default multi-user.target >/dev/null
  mkdir -p /etc/systemd/system/getty@tty1.service.d
  cat > /etc/systemd/system/getty@tty1.service.d/herrero.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $TARGET_USER --noclear %I \$TERM
EOF
  systemctl daemon-reload
  ok "inicio de sesión automático de $TARGET_USER en tty1 (las demás consolas piden contraseña)"
  if [[ -f /etc/default/console-setup ]]; then
    sed -i -e 's/^CODESET=.*/CODESET="Uni2"/' -e 's/^FONTFACE=.*/FONTFACE="Terminus"/' \
           -e 's/^FONTSIZE=.*/FONTSIZE="16x32"/' /etc/default/console-setup
    setupcon --save-only >/dev/null 2>&1 || true
  fi
  local prof="$home/.profile"
  [[ -f "$home/.bash_profile" ]] && prof="$home/.bash_profile"
  touch "$prof"
  sed -i "/# >>> herrero-tui >>>/,/# <<< herrero-tui <<</d; /$MARK_BEGIN/,/$MARK_END/d" "$prof"
  cat >> "$prof" <<EOF
$MARK_BEGIN
if [ "\$(tty)" = "/dev/tty1" ] && [ -z "\${SUITE_ACTIVA:-}" ] && [ -x /usr/local/bin/suite ]; then
  export SUITE_ACTIVA=1 SUITE_TUI_ARGS="$TUI_ARGS"
  /usr/local/bin/suite
fi
$MARK_END
EOF
  chown "$TARGET_USER:" "$prof"
  ok "la suite se abre al entrar en tty1 ($prof)"
}

undo() {
  [[ $EUID -eq 0 ]] || fallo "ejecútalo con sudo"
  paso "Volver al escritorio"
  systemctl set-default graphical.target >/dev/null
  rm -f /etc/systemd/system/getty@tty1.service.d/herrero.conf
  rmdir /etc/systemd/system/getty@tty1.service.d 2>/dev/null || true
  systemctl daemon-reload
  if [[ -n "$TARGET_USER" ]]; then
    local home f; home="$(user_home)"
    for f in "$home/.profile" "$home/.bash_profile"; do
      [[ -f "$f" ]] && sed -i "/# >>> herrero-tui >>>/,/# <<< herrero-tui <<</d; /$MARK_BEGIN/,/$MARK_END/d" "$f"
    done
  fi
  ok "Hecho: al reiniciar vuelve el escritorio. La suite sigue instalada en $SUITE."
}

# ------------------------------------------------------------------ principal
if [[ $MENU == yes ]]; then menu_interactivo; fi
case "$MODE" in
  prepare) prepare; exit 0 ;;
  undo) undo; exit 0 ;;
esac

[[ $EUID -eq 0 ]] || fallo "ejecútalo con sudo: sudo $0 ${ARGS_ORIG[*]}"
[[ -n "$TARGET_USER" && "$TARGET_USER" != "root" ]] || fallo "indica el usuario con --usuario NOMBRE"
getent passwd "$TARGET_USER" >/dev/null || fallo "no existe el usuario $TARGET_USER"
if [[ -n "$OFFLINE" ]]; then
  OFFLINE="$(cd "$OFFLINE" && pwd)"
  if [[ -f "$OFFLINE/proyectos.txt" && "$SELECTED" == "herrero oficina prueba director juegos" ]]; then
    SELECTED="$(cat "$OFFLINE/proyectos.txt")"
  fi
fi
for p in $SELECTED; do
  [[ -n "${TIPO[$p]:-}" ]] || fallo "proyecto desconocido: $p (${TODOS[*]})"
  if [[ ${TIPO[$p]} == nada ]]; then aviso "${NOMBRE[$p]}: ${DESC[$p]}"; SELECTED="${SELECTED//$p/}"; fi
done

paso "Suite para Ubuntu $UBU_VER (kernel $KVER) · $TARGET_USER · $SELECTED ${OFFLINE:+· sin conexión}"
setup_apt
paso "Utilidades y firmware"
apt_install "${BASE_PACKAGES[@]}" || aviso "faltan algunas utilidades"
apt_install "${FIRMWARE_PACKAGES[@]}" || aviso "no se pudo actualizar el firmware"
install_nvidia
for p in $SELECTED; do if [[ ${TIPO[$p]} == bundle ]]; then install_bundle "$p"; fi; done
install_python_projects
install_user_parts
install_mode_helper
install_launcher
text_mode_and_autologin

paso "Instalación terminada"
for p in $SELECTED; do
  case "$p" in
    oficina|prueba) echo "    ${NOMBRE[$p]}: http://127.0.0.1:${PUERTO[$p]}" ;;
  esac
done
if [[ ${#VENV_OF[@]} -gt 0 ]]; then echo "    Venvs de Python: $(venv_groups | tr '\n' ' ')"; fi
if [[ $WITH_NVIDIA == 1 ]]; then echo "    Tras reiniciar, comprueba la gráfica con:  herrero-tui --gpu"; fi
if [[ $TEXT_MODE == 1 ]]; then
  echo "    Al reiniciar arranca sin escritorio y abre el menú de la suite (también: suite)."
  echo "    Desde el escritorio vuelve al modo terminal con «Reiniciar en modo terminal»."
  if [[ -t 0 ]]; then
    read -r -t 30 -p "    ¿Reiniciar ahora? [s/N] " r || r=""
    if [[ "${r,,}" == s* ]]; then systemctl reboot; fi
  fi
fi
exit 0
