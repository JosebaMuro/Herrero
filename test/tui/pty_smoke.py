"""Prueba de humo de la TUI en un terminal de verdad (pty): escribe una petición, calcula,
recorre pestañas, abre «IA y GPU» y sale con Ctrl+C. Uso: python3 pty_smoke.py herrero-tui"""
import os, pty, select, sys, time, fcntl, termios, struct

exe = sys.argv[1]
pid, fd = pty.fork()
if pid == 0:
    os.environ['TERM'] = 'linux'  # la consola de texto de Linux
    os.execv(exe, [exe, '--motor', 'cpu'])

fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', 40, 120, 0, 0))
out = b''

def pump(secs):
    global out
    end = time.time() + secs
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            try:
                out += os.read(fd, 65536)
            except OSError:
                return

def send(s, wait=0.6):
    os.write(fd, s.encode() if isinstance(s, str) else s)
    pump(wait)

pump(2)
send('marquesina para 3 coches en Burgos', 0.5)
send('\r', 1.5)          # ficha
send('\r', 1.5)          # calcular
send('\x1b[C', 0.5)      # pestaña Despiece
send('3', 0.5)           # Comprobaciones
send('\x07', 1.5)        # Ctrl+G: IA y GPU
send('\x1b', 0.5)        # volver
send('\x03', 1.5)        # Ctrl+C
_, status = os.waitpid(pid, 0)
text = out.decode('utf-8', 'replace')
checks = ['HERRERO', 'Lo que he entendido', 'Marquesina', 'Despiece', 'Comprobaciones', 'Motor', 'ONNX Runtime']
missing = [c for c in checks if c not in text]
code = os.waitstatus_to_exitcode(status)
print('salida:', code, '· bytes:', len(out), '· faltan:', missing)
if missing or code != 0:
    print(text[-3000:])
    sys.exit(1)
