#!/usr/bin/env bash
# Mete FreeLLMAPI (github.com/tashfeenahmed/freellmapi, MIT) y su Node.js
# dentro del paquete de Herrero, como hace 9000 tokens (Infinito).
#
# Uso: scripts/bundle_freellmapi.sh <linux-x64|linux-arm64|win-x64|android-arm64> <carpeta>
#
# Deja en <carpeta>/freellmapi:
#   node/       Node.js de la plataforma (en Android: ver scripts/android_node.py)
#   app/        servidor compilado (server/dist), panel web (client/dist) y sus dependencias
#   pack.json   versiones
# En Android el Node va aparte, como bibliotecas del APK (jniLibs).
set -euo pipefail
TARGET="$1"
DEST="$(mkdir -p "$2" && cd "$2" && pwd)"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REF="${FREELLMAPI_REF:-v0.16.51}"
NODE_MAJOR="${NODE_MAJOR:-22}"
WORK="${WORK:-$(mktemp -d)}"
if command -v cygpath >/dev/null 2>&1; then
  WORK="$(cygpath -m "$WORK")"; DEST="$(cygpath -m "$DEST")"; ROOT="$(cygpath -m "$ROOT")"
fi
PY=python3; command -v python3 >/dev/null 2>&1 || PY=python
OUT="$DEST/freellmapi"
rm -rf "$OUT"; mkdir -p "$OUT"

NODE_VER=""
if [ "$TARGET" != android-arm64 ]; then
  # 22.13+ trae node:sqlite; se usa la última 22.x
  NODE_VER=$(curl -fsSL https://nodejs.org/dist/index.json | $PY -c "import json,sys; print([r['version'] for r in json.load(sys.stdin) if r['version'].startswith('v$NODE_MAJOR.')][0])")
  echo "== Node.js $NODE_VER ($TARGET)"
  case "$TARGET" in
    linux-x64|linux-arm64)
      a="${TARGET#linux-}"
      curl -fsSL "https://nodejs.org/dist/$NODE_VER/node-$NODE_VER-linux-$a.tar.xz" | tar -xJ -C "$OUT"
      mv "$OUT/node-$NODE_VER-linux-$a" "$OUT/node"
      rm -rf "$OUT/node/include" "$OUT/node/share" "$OUT/node/lib/node_modules/corepack" ;;
    win-x64)
      curl -fsSLo "$WORK/node.zip" "https://nodejs.org/dist/$NODE_VER/node-$NODE_VER-win-x64.zip"
      (cd "$OUT" && unzip -q "$WORK/node.zip")
      mv "$OUT/node-$NODE_VER-win-x64" "$OUT/node"
      rm -rf "$OUT/node/node_modules/corepack" ;;
    *) echo "destino desconocido: $TARGET"; exit 2 ;;
  esac
  # npm del propio paquete no hace falta para ejecutar
  rm -rf "$OUT/node/lib/node_modules/npm" "$OUT/node/node_modules/npm" "$OUT/node/npm"* "$OUT/node/npx"* "$OUT/node/bin/npm" "$OUT/node/bin/npx" 2>/dev/null || true
fi

echo "== FreeLLMAPI $REF"
git clone -q --depth 1 --branch "$REF" https://github.com/tashfeenahmed/freellmapi "$WORK/fl"
cd "$WORK/fl"
npm ci --no-audit --no-fund --loglevel=error
npm run build -w server
npm run build -w client
rm -rf node_modules client/node_modules server/node_modules shared/node_modules cli/node_modules
# solo el servidor y lo compartido: fuera el panel (ya compilado), la CLI y las herramientas de desarrollo
node -e "const f='package.json',p=require('./'+f);p.workspaces=['shared','server'];delete p.devDependencies;require('fs').writeFileSync(f,JSON.stringify(p,null,2))"
rm -f package-lock.json
FLAGS=(--omit=dev --no-audit --no-fund --loglevel=error)
if [ "$TARGET" = android-arm64 ]; then
  # Android: base de datos con node:sqlite, sin módulos nativos
  FLAGS+=(--os=android --cpu=arm64 --ignore-scripts --omit=optional)
fi
npm install "${FLAGS[@]}"
# sharp (imágenes) se carga solo si hace falta y Herrero solo usa el chat
rm -rf node_modules/@img node_modules/sharp
if [ "$TARGET" = android-arm64 ]; then rm -rf node_modules/better-sqlite3; fi
# enlaces de los workspaces -> carpetas reales (Windows y los assets de Android no siguen enlaces)
for l in node_modules/@freellmapi/* ; do
  [ -L "$l" ] || continue
  t="$(cd "$(dirname "$l")" && cd "$(readlink "$(basename "$l")")" && pwd)"; rm "$l"; cp -r "$t" "$l"
done
rm -rf node_modules/@freellmapi/server node_modules/@freellmapi/client node_modules/@freellmapi/cli
mkdir -p "$OUT/app/server" "$OUT/app/client" "$OUT/app/desktop"
cp package.json "$OUT/app/"
cp -r node_modules "$OUT/app/"
[ -d server/node_modules ] && cp -r server/node_modules "$OUT/app/server/"
cp -r server/dist server/package.json "$OUT/app/server/"
cp -r client/dist "$OUT/app/client/"
cp -r shared "$OUT/app/"
cp desktop/package.json "$OUT/app/desktop/"
cp LICENSE "$OUT/LICENSE-freellmapi.txt"
# sin enlaces simbólicos (el .zip de Windows y el tar de Android no los quieren)
find "$OUT/app" -name .bin -type d -prune -exec rm -rf {} +
find "$OUT/app" -type l -delete
# fuera mapas de código, tipos y docs: no hacen falta para ejecutar
find "$OUT/app" \( -name '*.map' -o -name '*.d.ts' -o -name '*.md' -o -name 'CHANGELOG*' \) -type f -delete 2>/dev/null || true
FL_VER=$(node -p "require('./desktop/package.json').version")
cd "$ROOT"
cat > "$OUT/pack.json" <<JSON
{"target":"$TARGET","freellmapi":"$FL_VER","ref":"$REF","node":"${NODE_VER:-android}","built":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
JSON
cat "$OUT/pack.json"
du -sh "$OUT" "$OUT"/* 2>/dev/null || true
