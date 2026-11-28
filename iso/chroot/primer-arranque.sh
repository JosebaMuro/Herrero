#!/usr/bin/env bash
# Primer arranque del Ubuntu MATE instalado desde la ISO de la suite (no se ejecuta en live).
# Herrero y Director de rol ya vienen instalados en /opt/suite; aquí se hace lo que depende
# del equipo y del usuario creado en la instalación:
#   · el usuario entra en los grupos video y render (gráfica para la IA)
#   · controlador NVIDIA si hay gráfica NVIDIA (ubuntu-drivers, versión de escritorio)
#   · paquete CUDA de Herrero (cuando el controlador ya funciona, tras reiniciar)
#   · modelos de IA de Herrero
# Si falta la red o la gráfica aún no está lista, lo pendiente se reintenta en el siguiente
# arranque. Registro: /var/log/suite-primer-arranque.log
set -uo pipefail
# en la sesión live no hay nada que hacer (el servicio ya lo evita; por si se lanza a mano)
if [[ -e /var/log/casper.log || -e /run/casper-md5check.json ]]; then exit 0; fi
MARCA=/var/lib/suite/primer-arranque.hecho
LOG=/var/log/suite-primer-arranque.log
mkdir -p /var/lib/suite
exec >>"$LOG" 2>&1
echo "=== $(date -Is) primer arranque de la suite"

WITH_NVIDIA=1
WITH_MODELS=1
# shellcheck disable=SC1091
[[ -f /etc/suite-iso.conf ]] && . /etc/suite-iso.conf

# usuario: el primero «normal» (el que crea el instalador)
U="$(getent passwd | awk -F: '$3>=1000 && $3<60000 && $7 !~ /(nologin|false)$/ {print $1; exit}')"
if [[ -z "$U" ]]; then echo "aún no hay usuario: se reintentará"; exit 0; fi
H="$(getent passwd "$U" | cut -d: -f6)"
as_user() { sudo -u "$U" -H -- "$@"; }
echo "usuario: $U ($H)"

usermod -aG video,render "$U" 2>/dev/null || true

red=0
for _ in $(seq 60); do
  if wget -q --spider --timeout=10 https://github.com >/dev/null 2>&1; then red=1; break; fi
  sleep 5
done
echo "red: $red"

pendiente=0

# curl lo usa el instalador completo de la suite (/opt/suite/instalar-ubuntu.sh)
if [[ $red == 1 ]] && ! command -v curl >/dev/null; then
  apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl || pendiente=1
fi
hecho() { [[ -f /var/lib/suite/$1 ]]; }
marcar() { touch "/var/lib/suite/$1"; }

has_nvidia_pci() {
  local d
  for d in /sys/bus/pci/devices/*; do
    [[ -r "$d/vendor" && -r "$d/class" ]] || continue
    [[ "$(cat "$d/vendor")" == "0x10de" && "$(cat "$d/class")" == 0x03* ]] && return 0
  done
  return 1
}
nvidia_ok() { command -v nvidia-smi >/dev/null && nvidia-smi >/dev/null 2>&1; }

if [[ $WITH_NVIDIA == 1 ]] && has_nvidia_pci; then
  if nvidia_ok; then
    echo "controlador NVIDIA funcionando"
  elif ! hecho nvidia-instalado; then
    if [[ $red == 1 ]] && command -v ubuntu-drivers >/dev/null; then
      echo "instalando el controlador NVIDIA recomendado"
      apt-get update -qq || true
      if DEBIAN_FRONTEND=noninteractive ubuntu-drivers install; then
        marcar nvidia-instalado
        echo "controlador instalado: el paquete CUDA de Herrero se instala tras reiniciar"
      fi
    fi
    pendiente=1
  else
    echo "controlador instalado pero aún sin cargar (falta reiniciar)"
    pendiente=1
  fi
  if nvidia_ok && ! hecho cuda-herrero && [[ -x /usr/local/bin/herrero-tui ]]; then
    if [[ $red == 1 ]] && as_user /usr/local/bin/herrero-tui --instalar-cuda --motor auto; then
      marcar cuda-herrero
    else
      pendiente=1
    fi
  fi
fi

if [[ $WITH_MODELS == 1 && -x /usr/local/bin/herrero-tui ]] && ! hecho modelos-herrero; then
  if [[ $red == 1 ]] && as_user /usr/local/bin/herrero-tui --descargar-modelos; then
    marcar modelos-herrero
  else
    pendiente=1
  fi
fi

if [[ $pendiente == 0 ]]; then
  touch "$MARCA"
  echo "terminado"
else
  echo "queda algo pendiente: se reintentará en el siguiente arranque"
fi
exit 0
