#!/usr/bin/env bash
# Compila la TUI (bin/herrero_tui.dart) como ejecutable nativo: scripts/build_tui.sh SALIDA
#
# `dart compile exe` no admite paquetes con «build hooks» en el grafo de dependencias
# (objective_c, que llega por path_provider en la app Flutter) ni nada que use dart:ui.
# La TUI no usa Flutter, así que se compila desde un paquete mínimo con el mismo código
# (lib/ y bin/ enlazados) y solo las dependencias que necesita, en las mismas versiones
# que la app. El paquete `onnxruntime` (plugin de Flutter) se copia sin Flutter: solo lo
# importa en ort_session.dart, y para Uint8List.
# Antes hay que haber ejecutado `flutter pub get` y `python3 scripts/ort_runtime.py linux`
# (cargador de ONNX Runtime con el paquete CUDA, en la copia de la caché de pub).
set -euo pipefail
OUT="$(realpath -m "${1:?uso: scripts/build_tui.sh SALIDA}")"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build"
W="$(mktemp -d "$ROOT/build/tui-pkg.XXXXXX")"
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

# onnxruntime ya parcheado (cargador de Herrero), sin la dependencia de Flutter
ORT_SRC="$(python3 - "$ROOT/.dart_tool/package_config.json" <<'EOF'
import json, sys, urllib.parse
for p in json.load(open(sys.argv[1]))['packages']:
    if p['name'] == 'onnxruntime':
        print(urllib.parse.unquote(p['rootUri'].replace('file://', '')))
EOF
)"
[[ -d "$ORT_SRC/lib" ]] || { echo "No se encuentra onnxruntime (¿falta flutter pub get?)"; exit 1; }
[[ -f "$ORT_SRC/lib/src/bindings/herrero_loader.dart" ]] \
  || echo "Aviso: onnxruntime sin el cargador de Herrero (falta python3 scripts/ort_runtime.py linux)"
mkdir -p "$W/onnxruntime"
cp -r "$ORT_SRC/lib" "$W/onnxruntime/"
sed -i "s#^import 'package:flutter/services.dart';#import 'dart:typed_data';#" "$W/onnxruntime/lib/src/ort_session.dart"
if grep -rn "package:flutter" "$W/onnxruntime/lib"; then
  echo "onnxruntime todavía usa Flutter"
  exit 1
fi
cat > "$W/onnxruntime/pubspec.yaml" <<EOF
name: onnxruntime
version: $(ver onnxruntime)
environment:
  # la misma versión del lenguaje que el original (sus clases Opaque no llevan «base»)
  sdk: '>=2.17.0 <4.0.0'
dependencies:
  ffi: $(ver ffi)
EOF

SDK="$(sed -n 's/^  sdk: *//p' "$ROOT/pubspec.yaml" | head -1)"
cat > "$W/pubspec.yaml" <<EOF
name: herrero
publish_to: none
environment:
  sdk: ${SDK:-^3.0.0}
dependencies:
  onnxruntime:
    path: onnxruntime
  ffi: $(ver ffi)
  http: $(ver http)
  crypto: $(ver crypto)
EOF
cat "$W/pubspec.yaml"
( cd "$W" && dart pub get >/dev/null )
mkdir -p "$(dirname "$OUT")"
( cd "$W" && dart compile exe bin/herrero_tui.dart -o "$OUT" )
echo "TUI: $OUT"
