import '../engine/model.dart';
import '../views/render_view.dart';

/// Ambiente de la foto IA.
enum PhotoScene { sunny, sunset, overcast, construction }

extension PhotoSceneLabel on PhotoScene {
  String get label {
    switch (this) {
      case PhotoScene.sunny:
        return 'Día soleado';
      case PhotoScene.sunset:
        return 'Atardecer';
      case PhotoScene.overcast:
        return 'Nublado';
      case PhotoScene.construction:
        return 'En obra';
    }
  }

  String get english {
    switch (this) {
      case PhotoScene.sunny:
        return 'bright sunny day, clear blue sky, crisp shadows';
      case PhotoScene.sunset:
        return 'golden hour, warm sunset light, long shadows';
      case PhotoScene.overcast:
        return 'overcast sky, soft diffuse light';
      case PhotoScene.construction:
        return 'construction site, steel erection in progress, mobile crane, workers with helmets, gravel ground';
    }
  }
}

String _finish(Finish f) {
  switch (f) {
    case Finish.galvanizado:
      return 'hot-dip galvanized steel with silver zinc finish';
    case Finish.pintadoGris:
      return 'anthracite grey painted steel';
    case Finish.pintadoRojo:
      return 'red oxide primer painted steel';
    case Finish.corten:
      return 'corten weathering steel with orange rust patina';
    case Finish.negro:
      return 'matte black powder coated steel';
  }
}

String _roof(String roofing) {
  final r = roofing.toLowerCase();
  if (r.contains('sin cubierta')) return 'open frame without roof';
  if (r.contains('sándwich') || r.contains('sandwich')) return 'insulated sandwich panel roof';
  if (r.contains('policarbonato')) return 'translucent polycarbonate roof sheets';
  if (r.contains('teja')) return 'tiled roof';
  if (r.contains('fotovolt')) return 'solar photovoltaic panels on the roof';
  if (r.contains('tramex') || r.contains('rejilla')) return 'steel grating deck';
  if (r.contains('chapa')) return 'corrugated metal roof sheets';
  return 'metal roof';
}

/// Descripción en inglés de la tipología (el codificador CLIP entiende mejor el inglés).
String structureEnglish(StructureSpec s) => s.type.english;

/// Prompt en inglés para la foto IA a partir del diseño.
String photoPrompt(Design d, Finish f, PhotoScene scene, {bool roof = true}) {
  final s = d.spec;
  final parts = <String>[
    'professional architectural photograph of a ${structureEnglish(s)}',
    _finish(f),
    'welded steel profiles, bolted connections, concrete footings',
    if (s.type.hasRoof) (roof ? _roof(s.roofing) : 'exposed steel skeleton frame without cladding'),
    if (s.railing) 'steel safety railing',
    scene.english,
    'photorealistic, sharp focus, high detail, 35mm lens',
  ];
  return parts.join(', ');
}
