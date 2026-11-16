import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'render_view.dart';

/// Vista 3D interactiva con z-buffer por píxel. Mientras se mueve la cámara se
/// dibuja una versión rápida a baja resolución y, al soltar, la definitiva
/// (sombras suaves, resolución completa) en segundo plano.
class ZRenderView extends StatefulWidget {
  final SceneMesh mesh;
  final OrbitCamera cam;
  final double sun;
  final int version;
  const ZRenderView({super.key, required this.mesh, required this.cam, required this.sun, required this.version});
  @override
  State<ZRenderView> createState() => _ZRenderViewState();
}

class _ZRenderViewState extends State<ZRenderView> {
  late ZScene _scene = widget.mesh.pack();
  ui.Image? _img;
  Size _size = Size.zero;
  double _dpr = 1;
  int _gen = 0;
  Timer? _hq;
  bool _scheduled = false;

  @override
  void didUpdateWidget(covariant ZRenderView old) {
    super.didUpdateWidget(old);
    if (old.mesh != widget.mesh) _scene = widget.mesh.pack();
    if (old.mesh != widget.mesh || old.version != widget.version || old.sun != widget.sun) _schedule();
  }

  @override
  void dispose() {
    _hq?.cancel();
    _gen++;
    _img?.dispose();
    super.dispose();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _render();
    });
  }

  Future<void> _set(ui.Image img, int gen) async {
    if (!mounted || gen != _gen) {
      img.dispose();
      return;
    }
    final old = _img;
    setState(() => _img = img);
    old?.dispose();
  }

  void _render() {
    if (_size.isEmpty) return;
    final gen = ++_gen;
    final cam = widget.cam;
    final sun = widget.sun;
    // Vista rápida (síncrona, ~1/3 de resolución)
    final fw = math.max(64, math.min(560, (_size.width * _dpr * 0.4).round()));
    final fh = math.max(48, (fw * _size.height / _size.width).round());
    final px = renderZ(_scene, zViewFor(cam, fw, fh, sun: sun, fast: true));
    rgbaToImage(px, fw, fh).then((img) => _set(img, gen));
    // Vista definitiva al dejar de mover
    _hq?.cancel();
    _hq = Timer(const Duration(milliseconds: 220), () async {
      final w = math.min(1800, (_size.width * _dpr).round());
      final h = (w * _size.height / _size.width).round();
      final view = zViewFor(cam, w, h, sun: sun);
      final scene = _scene;
      final hq = await renderRgba(scene, view);
      if (!mounted || gen != _gen) return;
      await _set(await rgbaToImage(hq, w, h), gen);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      final dpr = MediaQuery.of(context).devicePixelRatio;
      if (size != _size || dpr != _dpr) {
        _size = size;
        _dpr = dpr;
        _schedule();
      }
      return CustomPaint(painter: _ImagePainter(_img), size: size);
    });
  }
}

class _ImagePainter extends CustomPainter {
  final ui.Image? img;
  _ImagePainter(this.img);
  @override
  void paint(Canvas canvas, Size size) {
    final i = img;
    if (i == null) {
      canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height),
                [const Color(0xFF5B8FC7), const Color(0xFFE8EEF2), const Color(0xFF8E8A80)], [0, 0.55, 1]));
      return;
    }
    canvas.drawImageRect(i, Rect.fromLTWH(0, 0, i.width.toDouble(), i.height.toDouble()), Offset.zero & size,
        Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(covariant _ImagePainter old) => old.img != img;
}
