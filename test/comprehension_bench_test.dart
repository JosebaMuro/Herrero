// Banco de descripciones para medir la comprensión por reglas (sin modelos):
// cada caso dice qué debe salir en la ficha. Se cuenta cada dato por separado
// y se exige un mínimo de aciertos para que no se pierda comprensión.
import 'package:flutter_test/flutter_test.dart';
import 'package:herrero/engine/model.dart';
import 'package:herrero/engine/understanding.dart';

class Case {
  final String prompt;
  final StructureType type;
  final double? length, width, height;
  final String? roofing, cladding, finish, variant, grade;
  final Map<String, String> parts;
  final double? liveLoad; // kN/m²
  const Case(this.prompt, this.type,
      {this.length,
      this.width,
      this.height,
      this.roofing,
      this.cladding,
      this.finish,
      this.variant,
      this.grade,
      this.parts = const {},
      this.liveLoad});
}

const joseba = 'Barandilla de balcon formada por 5 listones frontales de 20×50 mm horizontales, con llanta de 30×5 mm '
    'vertical en extremos y centro y 170 mm de llanta hacia el interior en parte superior e inferior. Tiene una altura '
    'exterior de 390 mm e interior de 685 mm para union por el interior de la fachada del balcon. Lleva a media altura '
    'entre las llantas, apolladas y soldadas longitudinal para poner tiestos.';

const cases = <Case>[
  // --- Texto de prueba de Joseba (barandilla de balcón sobre el peto) -----------
  Case(joseba, StructureType.barandilla, length: 3, height: 0.685, variant: 'sobre peto · tiestos'),
  // --- Secciones de perfil que no son medidas de la estructura ------------------
  Case('reja de ventana de 1200 x 1000 mm con cuadradillo de 12 mm', StructureType.valla, length: 1.2, height: 1.0),
  Case('reja para ventana de 900 x 1100 mm con barrotes de cuadradillo 14 mm', StructureType.valla, length: 0.9, height: 1.1),
  Case('altillo de 7 x 3,5 con vigas IPE 160 y pilares de tubo 100x100x5 a 2,6 m', StructureType.entreplanta,
      length: 7, width: 3.5, height: 2.6, parts: {'vigas': 'IPE 160', 'pilares': 'SHS 100x5'}),
  Case('cobertizo de 4 x 2,5 m con techo de chapa minionda, 2,2 m de alto', StructureType.marquesina,
      length: 4, width: 2.5, height: 2.2, roofing: 'chapa ondulada'),
  Case('marquesina a un agua de 8 x 4 m con calaminón TR4, 3 m de alto', StructureType.marquesina,
      length: 8, width: 4, height: 3, roofing: 'chapa grecada'),
  Case('barandilla de 6 m con montantes de tubo 40x40 y pasamanos de 50x30', StructureType.barandilla, length: 6),
  Case('cancela de 3 m de hueco y 1,8 m de alto con bastidor de tubo 60x40 y barrotes de 20x20', StructureType.cancela,
      length: 3, height: 1.8),
  Case('marquesina de 5 x 3 m con pilares de tubo 100x100x4', StructureType.marquesina,
      length: 5, width: 3, parts: {'pilares': 'SHS 100x4'}),
  Case('barandilla de 4 m de largo con barras horizontales de pletina 40x8', StructureType.barandilla,
      length: 4, variant: 'barras horizontales'),
  // --- Materiales de cubierta ------------------------------------------------
  Case('Marquesina para 2 coches de 5,5 x 5 m y 2,4 m de alto, panel sándwich, galvanizada', StructureType.marquesina,
      length: 5.5, width: 5, height: 2.4, roofing: 'panel sándwich', finish: 'galvaniz'),
  Case('Tejavana de 6 x 4 con calaminón, 2,5 m de alto', StructureType.marquesina,
      length: 6, width: 4, height: 2.5, roofing: 'chapa grecada'),
  Case('cobertizo de 5 por 3 metros con techo de calamina para la leña', StructureType.marquesina,
      length: 5, width: 3, roofing: 'chapa ondulada'),
  Case('Pérgola de 4 x 3 m con policarbonato alveolar de 16 mm, lacada en blanco', StructureType.marquesina,
      length: 4, width: 3, roofing: 'policarbonato celular 16 mm', finish: 'lacad'),
  Case('porche de 6 x 3 m cubierto con policarbonato compacto de 6 mm', StructureType.marquesina,
      length: 6, width: 3, roofing: 'policarbonato compacto 6 mm'),
  Case('caseta de 4 x 3 m de 2,5 m de alto con cubierta de onduline', StructureType.nave,
      length: 4, width: 3, height: 2.5, roofing: 'placa asfáltica'),
  Case('marquesina de entrada de 3 x 1,5 m con cristal laminado', StructureType.marquesina,
      length: 3, width: 1.5, roofing: 'vidrio laminado'),
  Case('Nave de 30 x 15 m, 6 m al alero, pórticos cada 6 m, panel sándwich de 40 mm, en Vitoria', StructureType.nave,
      length: 30, width: 15, height: 6, roofing: 'panel sándwich 40 mm'),
  Case('nave agrícola de 20 m de luz y 40 de fondo, 7 m al alero, cubierta de fibrocemento', StructureType.nave,
      length: 40, width: 20, height: 7, roofing: 'fibrocemento'),
  Case('nave de 25 x 12, cubierta de chapa grecada y cerramiento de bloque de hormigón', StructureType.nave,
      length: 25, width: 12, roofing: 'chapa grecada', cladding: 'bloque'),
  Case('nave de 18 x 10 m con fachadas de panel sándwich y cubierta de chapa ondulada', StructureType.nave,
      length: 18, width: 10, roofing: 'chapa ondulada', cladding: 'panel sándwich'),
  Case('almacén de 20 x 10 cerrado con calaminón, 5 m de alto', StructureType.nave,
      length: 20, width: 10, height: 5, cladding: 'chapa grecada'),
  Case('pérgola fotovoltaica de 10 x 5 m para 4 coches', StructureType.marquesina,
      length: 10, width: 5, roofing: 'fotovoltaic'),
  Case('porche de 5 x 4 m con teja árabe', StructureType.marquesina, length: 5, width: 4, roofing: 'teja'),
  Case('pérgola bioclimática de lamas de 4 x 4 m', StructureType.marquesina, length: 4, width: 4, roofing: 'sin cubierta'),
  // --- Suelos -------------------------------------------------------------------
  Case('altillo de 8 x 4 m a 3 m de altura para almacén, suelo de tramex', StructureType.entreplanta,
      length: 8, width: 4, height: 3, roofing: 'tramex'),
  Case('entreplanta de 6 x 5 m con chapa lagrimada de 5 mm, a 2,8 m', StructureType.entreplanta,
      length: 6, width: 5, height: 2.8, roofing: 'lagrimada'),
  Case('altillo de 10 x 6 para oficina con forjado de chapa colaborante', StructureType.entreplanta,
      length: 10, width: 6, roofing: 'colaborante'),
  Case('altillo de 5 x 4 con suelo de tablero fenólico para trastero', StructureType.entreplanta,
      length: 5, width: 4, roofing: 'fenólico'),
  Case('altillo de 6 x 3 m con suelo de chapa estriada', StructureType.entreplanta,
      length: 6, width: 3, roofing: 'lagrimada'),
  Case('escalera de 3 m de altura con peldaños de chapa lagrimada', StructureType.escalera,
      height: 3, roofing: 'lagrimada'),
  Case('escalera recta de 2,8 m de alto y 90 cm de ancho, peldaño de rejilla', StructureType.escalera,
      height: 2.8, width: 0.9, roofing: 'tramex'),
  Case('pasarela de 12 m de largo y 1 m de ancho a 4 m de altura, suelo de tramex', StructureType.pasarela,
      length: 12, width: 1, height: 4, roofing: 'tramex'),
  // --- Rellenos -----------------------------------------------------------------
  Case('barandilla de 10 m con cristal laminado para terraza', StructureType.barandilla, length: 10, variant: 'vidrio'),
  Case('barandilla de 8 m de chapa perforada, 1,1 m de alto', StructureType.barandilla,
      length: 8, height: 1.1, variant: 'chapa perforada'),
  Case('barandilla de 12 m de largo con cables de inox', StructureType.barandilla, length: 12, variant: 'cables'),
  Case('barandilla de 6 m con barrotes de llanta, 1 m de alto', StructureType.barandilla,
      length: 6, height: 1, variant: 'barrotes'),
  // --- Perfiles ---------------------------------------------------------------------
  Case('pórtico para polipasto de 1000 kg de 4 m de luz con viga IPN', StructureType.portico,
      width: 4, parts: {'vigas': 'ipe'}),
  Case('nave de 20 x 10 m con pilares HEB 200 y correas de tubo', StructureType.nave,
      length: 20, width: 10, parts: {'pilares': 'HEB 200', 'correas': 'tubo'}),
  Case('escalera de 3 m de alto con zancas de UPN', StructureType.escalera, height: 3, parts: {'zancas': 'upn'}),
  Case('marquesina de 6 x 5 m, pilares de tubo cuadrado de 120 y vigas IPE', StructureType.marquesina,
      length: 6, width: 5, parts: {'vigas': 'ipe'}),
  // --- Acabados y aceros --------------------------------------------------------
  Case('cancela corredera de 4 m de hueco y 2 m de altura con barrotes, lacada en negro', StructureType.cancela,
      length: 4, height: 2, finish: 'lacad'),
  Case('valla de 30 m de largo y 2 m de alto con malla electrosoldada, galvanizada', StructureType.valla,
      length: 30, height: 2, finish: 'galvaniz'),
  Case('soporte para depósito de 5000 litros a 4 m de altura, en acero corten', StructureType.torre,
      height: 4, grade: 'corten'),
  Case('barandilla de inox 316 de 15 m', StructureType.barandilla, length: 15, grade: '316'),
];

void main() {
  test('banco de comprensión por reglas', () {
    var ok = 0, total = 0;
    final fails = <String>[];
    void check(Case c, String what, bool good, Object got) {
      total++;
      if (good) {
        ok++;
      } else {
        fails.add('«${c.prompt}» → $what: $got');
      }
    }

    bool near(double a, double b) => (a - b).abs() < 0.01;
    for (final c in cases) {
      final u = understand(c.prompt);
      final s = u.spec;
      check(c, 'tipo', u.type == c.type, u.type.name);
      if (c.length != null) check(c, 'largo', near(s.length, c.length!), s.length);
      if (c.width != null) check(c, 'ancho', near(s.width, c.width!), s.width);
      if (c.height != null) check(c, 'alto', near(s.height, c.height!), s.height);
      if (c.roofing != null) check(c, 'cubierta', s.roofing.contains(c.roofing!), s.roofing);
      if (c.cladding != null) check(c, 'cerramiento', s.cladding.contains(c.cladding!), s.cladding);
      if (c.finish != null) check(c, 'acabado', s.finish.toLowerCase().contains(c.finish!), s.finish);
      if (c.variant != null) check(c, 'variante', s.variant.contains(c.variant!), s.variant);
      if (c.grade != null) check(c, 'acero', s.grade.name.toLowerCase().contains(c.grade!), s.grade.name);
      c.parts.forEach((k, v) => check(c, 'perfil $k', (s.parts[k] ?? '').toLowerCase() == v.toLowerCase(), s.parts));
    }
    // ignore: avoid_print
    print('Comprensión por reglas: $ok / $total datos (${(100 * ok / total).toStringAsFixed(1)} %)\n${fails.join('\n')}');
    // v4.3.0-c daba 92,8 % en este banco; con el catálogo y las secciones de perfil, 100 %.
    expect(ok / total, greaterThanOrEqualTo(0.97));
  });
}
