#!/usr/bin/env bash
# Compila la TUI (bin/herrero_tui.dart) como ejecutable nativo: scripts/build_tui.sh SALIDA
#
# `dart compile exe` no admite paquetes con «build hooks» en el grafo de dependencias
# (objective_c, que llega por path_provider en la app Flutter). La TUI no usa nada de
# Flutter, así que se compila desde un paquete mínimo con el mismo código (lib/ y bin/
# enlazados) y solo las dependencias que necesita, en las mismas versiones que la app.
# Antes hay que haber ejecutado `python3 scripts/ort_runtime.py linux` (cargador de ONNX
# Runtime con el paquete CUDA, en la caché de pub compartida).
set -euo pipefail
OUT="${1:?uso: scripts/build_tui.sh SALIDA}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
W="$ROOT/build/tui-pkg"
rm -rf "$W"
mkdir -p "$W"
ln -s "$ROOT/lib" "$W/lib"
ln -s "$ROOT/bin" "$W/bin"

ver() { # versión de un paquete en pubspec.lock
  python3 - "$ROOT/pubspec.lock" "$1" <<'EOF'
import re, sys
text = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'\n  ' + re.escape(sys.argv[2]) + r':\n(?:    .*\n)*?    version: "([^"]+)"', text)
print(m.group(1) if m else 'any')
EOF
}

SDK="$(sed -n 's/^  sdk: *//p' "$ROOT/pubspec.yaml" | head -1)"
cat > "$W/pubspec.yaml" <<EOF
name: herrero
publish_to: none
environment:
  sdk: ${SDK:-^3.0.0}
dependencies:
  onnxruntime: $(ver onnxruntime)
  ffi: $(ver ffi)
  http: $(ver http)
  crypto: $(ver crypto)
EOF
cat "$W/pubspec.yaml"
( cd "$W" && flutter pub get >/dev/null )
mkdir -p "$(dirname "$OUT")"
( cd "$W" && dart compile exe bin/herrero_tui.dart -o "$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")" )
