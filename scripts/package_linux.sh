#!/usr/bin/env bash
# Empaqueta la build de Linux de Herrero como .deb y .AppImage.
#
#   scripts/package_linux.sh BUNDLE ARQUITECTURA SALIDA
#
# BUNDLE: build/linux/<x64|arm64>/release/bundle (app + herrero-tui ya compilada)
# ARQUITECTURA: arm64 (Raspberry Pi 4/5 con sistema de 64 bits) o x64
# Deja en SALIDA: Herrero-linux-<arq>.deb y Herrero-linux-<arq>.AppImage
#
# .deb: la app va en /opt/herrero, con `herrero` y `herrero-tui` en /usr/bin y
# entrada en el menú. Las dependencias se deducen de las bibliotecas que enlaza
# el bundle (ldd + dpkg -S), así que hay que ejecutarlo en Debian/Ubuntu.
# .AppImage: un solo archivo ejecutable; `--tui` abre la TUI de terminal.
set -euo pipefail
BUNDLE="$(realpath "${1:?uso: scripts/package_linux.sh BUNDLE ARQUITECTURA SALIDA}")"
ARCH="${2:?falta la arquitectura (arm64 o x64)}"
OUT="$(realpath -m "${3:?falta la carpeta de salida}")"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
case "$ARCH" in
  arm64) DEB_ARCH=arm64; AI_ARCH=aarch64 ;;
  x64)   DEB_ARCH=amd64; AI_ARCH=x86_64 ;;
  *) echo "arquitectura no admitida: $ARCH"; exit 1 ;;
esac
VERSION="$(sed -n 's/^version: *\([^+ ]*\).*/\1/p' "$ROOT/pubspec.yaml" | head -1)"
ICON="$ROOT/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png"
test -x "$BUNDLE/herrero" || { echo "falta $BUNDLE/herrero"; exit 1; }
test -x "$BUNDLE/herrero-tui" || { echo "falta $BUNDLE/herrero-tui"; exit 1; }
mkdir -p "$OUT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Solo la app y la TUI (sin el instalador de Ubuntu ni el LEEME del tar.gz)
copy_bundle() {
  mkdir -p "$1"
  cp -a "$BUNDLE/herrero" "$BUNDLE/herrero-tui" "$BUNDLE/lib" "$BUNDLE/data" "$1/"
}

desktop() { # $1 = Exec, $2 = Icon
  cat <<EOF
[Desktop Entry]
Type=Application
Name=Herrero
GenericName=Oficina técnica de estructuras metálicas
Comment=Predimensionado, despiece, planos y soldadura de estructuras metálicas
Exec=$1
Icon=$2
Terminal=false
Categories=Office;Engineering;
Keywords=estructuras;acero;soldadura;planos;despiece;
StartupWMClass=herrero
EOF
}

# ---------- .deb ----------
D="$WORK/deb"
copy_bundle "$D/opt/herrero"
mkdir -p "$D/usr/bin" "$D/usr/share/applications" "$D/usr/share/pixmaps" "$D/DEBIAN"
ln -s /opt/herrero/herrero "$D/usr/bin/herrero"
ln -s /opt/herrero/herrero-tui "$D/usr/bin/herrero-tui"
desktop /opt/herrero/herrero herrero > "$D/usr/share/applications/herrero.desktop"
cp "$ICON" "$D/usr/share/pixmaps/herrero.png"

# Dependencias: paquete del sistema de cada biblioteca que el bundle pide directamente
# (NEEDED, no las transitivas: así no se cuelan nombres propios de Ubuntu, como
# libjpeg-turbo8, que no existen en Raspberry Pi OS / Debian).
deps="$(
  for f in "$BUNDLE/herrero" "$BUNDLE/herrero-tui" "$BUNDLE"/lib/*.so*; do
    paths="$(LD_LIBRARY_PATH="$BUNDLE/lib" ldd "$f" 2>/dev/null || true)"
    # readelf falla con lo que no es ELF (o si no hay bibliotecas en lib/): se omite
    { readelf -d "$f" 2>/dev/null || :; } | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' | while read -r name; do
      if [[ -e "$BUNDLE/lib/$name" ]]; then continue; fi
      echo "$paths" | awk -v n="$name" '$1 == n && $3 ~ /^\// {print $3}'
    done
  done | sort -u | while read -r so; do
    for cand in "$so" "$(realpath "$so")"; do
      # dpkg -S sale con 1 si el archivo no es de ningún paquete: se prueba el siguiente
      pkg="$( { dpkg -S "$cand" 2>/dev/null || :; } | awk -F': ' -v p="$cand" '$2 == p && !n++ {print $1}')"
      if [[ -n "$pkg" ]]; then echo "${pkg%%:*}"; break; fi
    done
  done | sort -u | paste -sd, | sed 's/,/, /g'
)"
[[ -n "$deps" ]] || deps="libc6, libstdc++6, libgtk-3-0"
echo "Depends: $deps"
SIZE="$(du -sk "$D/opt" | cut -f1)"
cat > "$D/DEBIAN/control" <<EOF
Package: herrero
Version: $VERSION
Architecture: $DEB_ARCH
Maintainer: Herrero <herrero@users.noreply.github.com>
Section: science
Priority: optional
Installed-Size: $SIZE
Depends: $deps
Recommends: zenity | kdialog, geoclue-2.0
Homepage: https://github.com/JosebaMuro/Herrero
Description: Oficina técnica de estructuras metálicas
 Predimensionado (EC3 / CTE DB-SE-A), despiece, planos, montaje y soldadura
 a partir de una descripción en lenguaje natural, con IA local.
 Incluye la app de escritorio (herrero) y la TUI de terminal (herrero-tui).
 Estimación orientativa: el resultado debe validarlo un técnico.
EOF
cat > "$D/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications || true
EOF
chmod 755 "$D/DEBIAN/postinst"
dpkg-deb --root-owner-group --build "$D" "$OUT/Herrero-linux-$ARCH.deb"
dpkg-deb --info "$OUT/Herrero-linux-$ARCH.deb"

# ---------- .AppImage ----------
A="$WORK/Herrero.AppDir"
copy_bundle "$A/usr/lib/herrero"
desktop herrero herrero > "$A/herrero.desktop"
cp "$ICON" "$A/herrero.png"
cat > "$A/AppRun" <<'EOF'
#!/bin/sh
# Herrero.AppImage            -> app de escritorio
# Herrero.AppImage --tui ...  -> TUI de terminal (herrero-tui ...)
HERE="$(dirname "$(readlink -f "$0")")"
if [ "${1:-}" = "--tui" ]; then
  shift
  exec "$HERE/usr/lib/herrero/herrero-tui" "$@"
fi
exec "$HERE/usr/lib/herrero/herrero" "$@"
EOF
chmod 755 "$A/AppRun"
TOOL="$WORK/appimagetool"
curl -fsSL --retry 5 -o "$TOOL" \
  "https://github.com/AppImage/appimagetool/releases/download/1.9.0/appimagetool-$AI_ARCH.AppImage" \
  || curl -fsSL --retry 5 -o "$TOOL" \
  "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$AI_ARCH.AppImage"
chmod +x "$TOOL"
# sin FUSE en CI: el propio appimagetool se descomprime y se ejecuta
APPIMAGE_EXTRACT_AND_RUN=1 ARCH="$AI_ARCH" "$TOOL" --no-appstream "$A" "$OUT/Herrero-linux-$ARCH.AppImage"
chmod +x "$OUT/Herrero-linux-$ARCH.AppImage"
ls -l "$OUT"/Herrero-linux-"$ARCH".*
