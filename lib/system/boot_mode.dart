// Cambiar el modo de arranque de Linux y reiniciar: escritorio (X11/Wayland) o terminal
// con la TUI de Herrero. Dart puro: lo usan la app y la TUI.
//
// El cambio necesita root. scripts/instalar-ubuntu.sh instala /usr/local/sbin/herrero-modo
// y una regla de sudo que deja ejecutarlo sin contraseña al usuario de Herrero. Sin esa
// regla, la app de escritorio lo pide con pkexec (ventana de contraseña) y la TUI dice qué
// comando escribir.
import 'dart:io';

/// Ayudante instalado por scripts/instalar-ubuntu.sh.
const bootModeHelper = '/usr/local/sbin/herrero-modo';

enum BootMode {
  /// Escritorio gráfico (graphical.target): el arranque normal de Ubuntu.
  desktop('escritorio', 'graphical.target'),

  /// Solo terminal (multi-user.target) con Herrero en tty1.
  tui('tui', 'multi-user.target');

  const BootMode(this.arg, this.target);
  final String arg;
  final String target;

  String get label => this == desktop ? 'escritorio (X11)' : 'modo terminal con Herrero';
}

/// Se puede cambiar de modo en este equipo (Linux con systemd).
bool get bootModeSupported => Platform.isLinux && Directory('/run/systemd/system').existsSync();

/// Modo con el que arranca ahora el equipo (null si no se sabe).
Future<BootMode?> currentBootMode() async {
  if (!Platform.isLinux) return null;
  try {
    final r = await Process.run('systemctl', ['get-default']);
    final t = (r.stdout as String).trim();
    if (t == BootMode.desktop.target) return BootMode.desktop;
    if (t == BootMode.tui.target) return BootMode.tui;
  } catch (_) {}
  return null;
}

/// Hay un escritorio instalado al que volver (gestor de inicio de sesión).
bool get desktopInstalled =>
    File('/etc/systemd/system/display-manager.service').existsSync() ||
    ['gdm3', 'gdm', 'sddm', 'lightdm'].any((d) => File('/lib/systemd/system/$d.service').existsSync());

/// Comando que el usuario puede escribir a mano para cambiar de modo y reiniciar.
String bootModeManualCommand(BootMode m) => File(bootModeHelper).existsSync()
    ? 'sudo $bootModeHelper ${m.arg} --reiniciar'
    : 'sudo systemctl set-default ${m.target} && sudo systemctl reboot';

/// Deja [mode] como arranque por defecto y reinicia. Devuelve null si el equipo va a
/// reiniciar, o el motivo por el que no se pudo. [graphical]: se puede pedir la
/// contraseña con una ventana (pkexec), solo desde el escritorio.
Future<String?> rebootInto(BootMode mode, {bool graphical = false}) async {
  if (!Platform.isLinux) return 'Solo en Linux.';
  if (mode == BootMode.desktop && !desktopInstalled) {
    return 'No hay escritorio instalado (gdm, sddm o lightdm). Instálalo con: sudo apt install ubuntu-desktop-minimal';
  }
  final helper = File(bootModeHelper).existsSync();
  final attempts = <List<String>>[
    if (helper) ['sudo', '-n', bootModeHelper, mode.arg, '--reiniciar'],
    if (helper && graphical) ['pkexec', bootModeHelper, mode.arg, '--reiniciar'],
    if (!helper && graphical) ['pkexec', 'sh', '-c', 'systemctl set-default ${mode.target} && systemctl reboot'],
  ];
  String? last;
  for (final a in attempts) {
    try {
      final r = await Process.run(a.first, a.sublist(1));
      if (r.exitCode == 0) return null;
      last = '${r.stderr}'.trim();
      if (a.first == 'pkexec' && (r.exitCode == 126 || r.exitCode == 127)) {
        return 'Cancelado.';
      }
    } catch (e) {
      last = '$e';
    }
  }
  return 'No se pudo cambiar el modo de arranque sin contraseña${last == null || last.isEmpty ? '' : ' ($last)'}. '
      'Escribe en una terminal: ${bootModeManualCommand(mode)}';
}
