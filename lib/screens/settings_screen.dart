import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai/remote_settings.dart';
import '../engine/model.dart';
import 'models_screen.dart';

/// Ajustes de la app: endpoint de IA (FreeLLMAPI, pasarela de Infinito u otro
/// compatible con OpenAI) y acceso a los modelos locales.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _url = TextEditingController();
  final _key = TextEditingController();
  final _model = TextEditingController();
  RemoteLlmSettings _s = const RemoteLlmSettings();
  bool _loaded = false, _showKey = false, _testing = false;
  List<String> _models = const [];
  List<DetectedEndpoint> _detected = const [];
  String? _test;
  bool _testOk = false;
  bool _bundled = false;
  String _flVersion = '';
  StreamSubscription<FreeLlmApiState>? _sub;
  final _fl = EmbeddedFreeLlmApi.instance;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    _model.dispose();
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final s = await RemoteLlmStore.instance.load();
    final d = Platform.isAndroid || Platform.isIOS ? const <DetectedEndpoint>[] : await detectInfinito();
    var bundled = false;
    try {
      final b = await _fl.bundle();
      bundled = b?.exists ?? false;
      _flVersion = b?.version ?? '';
    } catch (_) {}
    _sub = _fl.changes.listen((_) {
      if (mounted) setState(() {});
    });
    if (!mounted) return;
    setState(() {
      _bundled = bundled;
      _s = !bundled && s.embedded ? s.copyWith(embedded: false) : s;
      _url.text = s.baseUrl;
      _key.text = s.apiKey;
      _model.text = s.model;
      _detected = d;
      _loaded = true;
    });
  }

  RemoteLlmSettings get _current =>
      _s.copyWith(baseUrl: _url.text.trim(), apiKey: _key.text.trim(), model: _model.text.trim());

  Future<void> _save([RemoteLlmSettings? s]) async {
    _s = s ?? _current;
    await RemoteLlmStore.instance.save(_s);
    if (mounted) setState(() {});
  }

  void _preset(String url, {String? key}) {
    _url.text = url;
    if (key != null) _key.text = key;
    if (_model.text.trim().isEmpty) _model.text = 'auto';
    _models = const [];
    _test = null;
    _save();
  }

  Future<void> _probe() async {
    await _save();
    setState(() {
      _testing = true;
      _test = null;
    });
    try {
      final s = await resolveRemote(_current);
      final models = await listRemoteModels(s);
      // prueba real: una ficha corta
      final job = startRemoteLlm(s.copyWith(timeoutS: 45), 'Marquesina de 5 x 3 m', StructureType.marquesina, (_) {});
      final r = await job.future;
      _models = models;
      _testOk = true;
      _test =
          'Conectado (${r.engineLabel}, ${(r.time.inMilliseconds / 1000).toStringAsFixed(1).replaceAll('.', ',')} s). '
          '${models.length - 1} modelos disponibles.';
    } catch (e) {
      _testOk = false;
      _test = '$e'.replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _testing = false);
  }

  String get _stateText => switch (_fl.state) {
    FreeLlmApiState.running => 'En marcha en ${_fl.dashboardUrl}',
    FreeLlmApiState.starting => 'Arrancando…',
    FreeLlmApiState.error => 'Error: ${_fl.lastError ?? ''}',
    FreeLlmApiState.absent => 'Este paquete no trae FreeLLMAPI',
    FreeLlmApiState.stopped => 'Parado (arranca solo al usarlo)',
  };

  Future<void> _startEmbedded() async {
    try {
      await _fl.endpoint();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  List<Widget> _embeddedPanel(TextTheme t, ColorScheme cs) => [
    if (!_bundled)
      Text(
        Platform.isIOS
            ? 'En iPhone no se pueden arrancar servidores dentro de una app: usa un endpoint externo (el FreeLLMAPI de tu PC).'
            : 'Este paquete de Herrero no trae FreeLLMAPI. Instala la versión con FreeLLMAPI o usa un endpoint externo.',
        style: t.bodySmall?.copyWith(color: cs.error),
      )
    else ...[
      Text(
        'Herrero trae FreeLLMAPI ${_flVersion.isEmpty ? '' : '$_flVersion '}y lo arranca en este equipo (solo escucha en 127.0.0.1). '
        'Sin claves ya usa los proveedores gratis que no las piden; para más modelos, abre el panel y añade '
        'tus claves en Keys. La URL y la clave se ponen solas.',
        style: t.bodySmall,
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          switch (_fl.state) {
            FreeLlmApiState.running => Icons.check_circle,
            FreeLlmApiState.error => Icons.error_outline,
            _ => Icons.pause_circle_outline,
          },
          color: switch (_fl.state) {
            FreeLlmApiState.running => Colors.green,
            FreeLlmApiState.error => cs.error,
            _ => cs.onSurfaceVariant,
          },
        ),
        title: Text(_stateText, style: t.bodyMedium),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (_fl.state == FreeLlmApiState.running)
            OutlinedButton.icon(onPressed: () => _fl.stop(), icon: const Icon(Icons.stop), label: const Text('Parar'))
          else
            OutlinedButton.icon(
              onPressed: _fl.state == FreeLlmApiState.starting ? null : _startEmbedded,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Arrancar'),
            ),
          OutlinedButton.icon(
            onPressed: _fl.state != FreeLlmApiState.running
                ? null
                : () => launchUrl(Uri.parse(_fl.dashboardUrl!), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.dashboard_customize_outlined),
            label: const Text('Abrir panel (claves de proveedores)'),
          ),
        ],
      ),
      const SizedBox(height: 8),
    ],
  ];

  List<Widget> _externalFields() => [
    Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final d in _detected)
          ActionChip(
            avatar: const Icon(Icons.auto_awesome, size: 16),
            label: Text(d.name),
            tooltip: 'Detectado en este equipo: ${d.baseUrl}',
            onPressed: () => _preset(d.baseUrl, key: d.apiKey),
          ),
        if (_detected.isEmpty)
          ActionChip(label: const Text('Infinito (:8686)'), onPressed: () => _preset(infinitoGateway)),
        ActionChip(label: const Text('FreeLLMAPI Docker (:3001)'), onPressed: () => _preset(freeLlmApiDocker)),
        ActionChip(label: const Text('FreeLLMAPI escritorio (:31415)'), onPressed: () => _preset(freeLlmApiDesktop)),
      ],
    ),
    const SizedBox(height: 8),
    TextField(
      controller: _url,
      keyboardType: TextInputType.url,
      decoration: const InputDecoration(
        labelText: 'URL base',
        hintText: 'http://localhost:3001/v1',
        helperText: 'Desde el móvil, la IP del PC (p. ej. http://192.168.1.20:3001/v1)',
      ),
      onSubmitted: (_) => _save(),
      onTapOutside: (_) => _save(),
    ),
    TextField(
      controller: _key,
      obscureText: !_showKey,
      decoration: InputDecoration(
        labelText: 'Clave (opcional)',
        hintText: 'freellmapi-…',
        helperText: 'La clave unificada de la página Keys de FreeLLMAPI',
        suffixIcon: IconButton(
          tooltip: _showKey ? 'Ocultar' : 'Mostrar',
          icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() => _showKey = !_showKey),
        ),
      ),
      onSubmitted: (_) => _save(),
      onTapOutside: (_) => _save(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Endpoint de IA (FreeLLMAPI)', style: t.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          'Usa un LLM por internet para leer la petición y rellenar la ficha, en lugar del modelo de '
                          '«Razonamiento» local. Vale FreeLLMAPI, la pasarela de Infinito (9000 tokens) o cualquier '
                          'servidor compatible con OpenAI (/v1/chat/completions). La IA local sigue igual para todo lo demás, '
                          'y la tipología y las medidas las siguen decidiendo las reglas: del LLM solo se aceptan datos que '
                          'aparecen en tu texto.',
                          style: t.bodySmall,
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Usar el endpoint para el razonamiento'),
                          subtitle: Text(
                            !_s.enabled
                                ? 'Desactivado: todo en local'
                                : _s.embedded
                                ? 'Con el FreeLLMAPI que trae Herrero'
                                : 'La petición se envía a ${normalizeBaseUrl(_url.text)}',
                          ),
                          value: _s.enabled,
                          onChanged: (v) => _save(_current.copyWith(enabled: v)),
                        ),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(
                              value: true,
                              icon: Icon(Icons.inventory_2_outlined),
                              label: Text('Integrado'),
                            ),
                            ButtonSegment(value: false, icon: Icon(Icons.link), label: Text('Externo (URL)')),
                          ],
                          selected: {_s.embedded},
                          onSelectionChanged: (v) {
                            _models = const [];
                            _test = null;
                            _save(_current.copyWith(embedded: v.first));
                          },
                        ),
                        const SizedBox(height: 8),
                        if (_s.embedded) ..._embeddedPanel(t, cs) else ..._externalFields(),
                        TextField(
                          controller: _model,
                          decoration: InputDecoration(
                            labelText: 'Modelo',
                            helperText: 'auto deja elegir a FreeLLMAPI (o auto:fast, auto:smart, un id)',
                            suffixIcon: _models.length > 1
                                ? PopupMenuButton<String>(
                                    tooltip: 'Elegir de la lista del endpoint',
                                    icon: const Icon(Icons.arrow_drop_down_circle_outlined),
                                    itemBuilder: (_) => [
                                      for (final m in _models) PopupMenuItem(value: m, child: Text(m)),
                                    ],
                                    onSelected: (m) {
                                      _model.text = m;
                                      _save();
                                    },
                                  )
                                : null,
                          ),
                          onSubmitted: (_) => _save(),
                          onTapOutside: (_) => _save(),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Si falla, usar el modelo local'),
                          subtitle: const Text('Sin conexión o sin cuota, razona el Qwen3 instalado (si lo hay)'),
                          value: _s.fallbackLocal,
                          onChanged: (v) => _save(_current.copyWith(fallbackLocal: v)),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            FilledButton.icon(
                              onPressed: _testing ? null : _probe,
                              icon: _testing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.wifi_tethering),
                              label: const Text('Probar conexión'),
                            ),
                            TextButton.icon(
                              onPressed: () =>
                                  launchUrl(Uri.parse(freeLlmApiRepo), mode: LaunchMode.externalApplication),
                              icon: const Icon(Icons.open_in_new, size: 18),
                              label: const Text('FreeLLMAPI en GitHub'),
                            ),
                          ],
                        ),
                        if (_test != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  _testOk ? Icons.check_circle : Icons.error_outline,
                                  size: 18,
                                  color: _testOk ? Colors.green : cs.error,
                                ),
                                const SizedBox(width: 6),
                                Expanded(child: Text(_test!, style: t.bodySmall)),
                              ],
                            ),
                          ),
                        const SizedBox(height: 8),
                        if (!_s.embedded)
                          Text(
                            'Cómo ponerlo en marcha: instala FreeLLMAPI (app de escritorio, Docker o el paquete completo de '
                            'Infinito), añade en Keys las claves gratis de los proveedores y copia aquí la clave unificada. '
                            'La petición sale de tu equipo hacia esos proveedores; si prefieres que nada salga, déjalo desactivado.',
                            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.download_for_offline_outlined),
                    title: const Text('Modelos de IA locales'),
                    subtitle: const Text('Descargas, motor (CPU/GPU) y foto IA'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ModelsScreen())),
                  ),
                ),
              ],
            ),
    );
  }
}
