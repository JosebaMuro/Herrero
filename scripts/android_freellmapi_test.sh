#!/usr/bin/env bash
# Arranca en un emulador Android el FreeLLMAPI preparado para el APK
# (libnode.so + bibliotecas renombradas + libfreellmapi_app.so) y comprueba
# que da la clave sola (modo escritorio) y responde en /v1.
# Uso: scripts/android_freellmapi_test.sh <carpeta jni>
set -euo pipefail
JNI="$1"
D=/data/local/tmp/herrero
adb shell rm -rf $D
adb shell mkdir -p $D/lib $D/pack $D/data $D/tmp
adb push "$JNI"/. $D/lib/ >/dev/null
adb shell chmod 755 $D/lib/*
adb shell "cd $D/pack && tar -xzf $D/lib/libfreellmapi_app.so"
adb shell "echo '# Herrero' > $D/pack/openssl.cnf"
ENV="LD_LIBRARY_PATH=$D/lib OPENSSL_CONF=$D/pack/openssl.cnf SSL_CERT_FILE=$D/pack/cert.pem NODE_EXTRA_CA_CERTS=$D/pack/cert.pem TMPDIR=$D/tmp HOME=$D/pack"
timeout 60 adb shell "$ENV $D/lib/libnode.so --version"
timeout 60 adb shell "$ENV $D/lib/libnode.so -e \"console.log(require('node:sqlite') ? 'node:sqlite ok' : 'sin sqlite')\""
timeout 20 adb shell "cd $D/pack/app/server && $ENV NODE_ENV=production HOST=127.0.0.1 PORT=31480 FREEAPI_DESKTOP=1 ENCRYPTION_KEY=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef FREEAPI_DB_PATH=$D/data/freeapi.db FREEAPI_ENV_PATH=$D/data/.env setsid nohup $D/lib/libnode.so dist/index.js < /dev/null > $D/data/log.txt 2>&1 &" < /dev/null || true
cat > /tmp/probe.js <<'JS'
const base = 'http://127.0.0.1:31480';
(async () => {
  for (let i = 0; i < 90; i++) {
    try {
      const r = await fetch(base + '/api/auth/desktop-session', { method: 'POST' });
      if (r.ok) {
        const { token } = await r.json();
        const { apiKey } = await (await fetch(base + '/api/settings/api-key', { headers: { authorization: 'Bearer ' + token } })).json();
        if (!apiKey.startsWith('freellmapi-')) throw new Error('clave rara ' + apiKey);
        const m = await (await fetch(base + '/v1/models', { headers: { authorization: 'Bearer ' + apiKey } })).json();
        if (!m.data.some(x => x.id === 'auto')) throw new Error('sin modelo auto');
        const page = await fetch(base + '/');
        if (!page.ok) throw new Error('panel ' + page.status);
        console.log('FreeLLMAPI en Android: OK, clave', apiKey.slice(0, 14) + '…,', m.data.length, 'modelos');
        process.exit(0);
      }
    } catch (e) { if (i > 85) console.log(String(e)); }
    await new Promise(r => setTimeout(r, 1000));
  }
  console.log('no arranca'); process.exit(1);
})();
JS
adb push /tmp/probe.js $D/probe.js >/dev/null
if ! timeout 300 adb shell "$ENV $D/lib/libnode.so $D/probe.js"; then
  adb shell cat $D/data/log.txt || true
  exit 1
fi
adb shell tail -5 $D/data/log.txt
