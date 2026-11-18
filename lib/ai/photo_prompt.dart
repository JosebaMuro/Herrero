import '../engine/model.dart';
import '../engine/profiles.dart';
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
    case Finish.blanco:
      return 'white powder coated steel';
    case Finish.inox:
      return 'brushed stainless steel with satin metallic finish';
    case Finish.aluminio:
      return 'anodized aluminium profiles with silver satin finish';
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
  final rail = s.type == StructureType.barandilla;
  // CLIP solo lee 77 tokens: primero lo que define la forma (tipología, detalles
  // de la barandilla y acabado) y al final el ambiente.
  final parts = <String>[
    'professional architectural photograph of a ${structureEnglish(s)}',
    ...railingDetails(d),
    _finish(f),
    if (!rail) 'welded steel profiles, bolted connections, concrete footings',
    if (s.type.hasRoof) (roof ? _roof(s.roofing) : 'exposed steel skeleton frame without cladding'),
    if (s.railing && !rail) 'steel safety railing',
    scene.english,
    'photorealistic, sharp focus, high detail, 35mm lens',
  ];
  return parts.join(', ');
}

/// Detalles de barandilla que se ven en el diseño (tubo redondo, doble pasamanos,
/// relleno), para que la foto no se quede en la barandilla genérica.
List<String> railingDetails(Design d) {
  final rails = d.members.where((m) => m.role == MemberRole.handrail).toList();
  if (rails.isEmpty) return const [];
  final round = rails.every((m) => m.profile.family == ProfileFamily.chs || m.profile.family == ProfileFamily.round);
  final heights = {for (final m in rails) (m.a.z * 10).round()};
  final bars = d.members.where((m) => m.role == MemberRole.baluster).toList();
  return [
    if (round) 'round tube posts and handrails',
    if (heights.length >= 2) 'double handrail at two heights',
    if (bars.isNotEmpty) 'thin vertical ${bars.first.profile.family == ProfileFamily.round ? 'round ' : ''}bars',
  ];
}
