/// Texto leído de un plano con su posición (unidades de la página, y hacia abajo).
class PlanToken {
  final String text;
  final double x0, y0, x1, y1;
  final bool vertical;
  final double confidence;
  const PlanToken(this.text, this.x0, this.y0, this.x1, this.y1,
      {this.vertical = false, this.confidence = 1});

  double get cx => (x0 + x1) / 2;
  double get cy => (y0 + y1) / 2;
  double get h => vertical ? x1 - x0 : y1 - y0;

  @override
  String toString() => '$text@(${x0.round()},${y0.round()})${vertical ? '↕' : ''}';
}

/// Resultado de leer un plano (PDF o imagen).
class PlanReading {
  final List<PlanToken> tokens;
  final String source; // 'pdf-texto', 'pdf-ocr', 'imagen-ocr'
  final int pages;
  final double pageWidth, pageHeight;
  const PlanReading(this.tokens, this.source, {this.pages = 1, this.pageWidth = 0, this.pageHeight = 0});
}
