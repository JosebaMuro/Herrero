import 'package:material_ui/material_ui.dart';

import '../engine/catalog.dart';
import '../engine/model.dart';
import '../engine/parser.dart';
import '../engine/profiles.dart';
import '../engine/vocabulary.dart';

/// Consulta de lo que la app entiende: tipologías, materiales y vocabulario.
class CatalogScreen extends StatelessWidget {
  /// Si se indica, al tocar un ejemplo se devuelve ese texto a la pantalla anterior.
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Qué entiende Herrero'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Estructuras', icon: Icon(Icons.foundation)),
            Tab(text: 'Materiales', icon: Icon(Icons.layers)),
            Tab(text: 'Vocabulario', icon: Icon(Icons.menu_book)),
          ]),
        ),
        body: const TabBarView(children: [_Typologies(), _Materials(), _Glossary()]),
      ),
    );
  }
}

class _Typologies extends StatelessWidget {
  const _Typologies();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(12), children: [
      for (final t in typologies)
        Card(
          child: ExpansionTile(
            title: Text(t.type.label, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(t.description, maxLines: 2, overflow: TextOverflow.ellipsis),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.description),
              const SizedBox(height: 8),
              Text('Calcula', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
              for (final c in t.computes) Text('•  $c'),
              const SizedBox(height: 8),
              Text('Datos que conviene indicar', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
              Text(t.data),
              const SizedBox(height: 8),
              Text('Normativa', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
              Text(t.norm),
              const SizedBox(height: 8),
              Text('También se reconoce como', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
              Text(t.keywords.keys.take(24).join(', '), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(6)),
                child: SelectableText('Ejemplo: ${t.example}', style: const TextStyle(fontStyle: FontStyle.italic)),
              ),
            ],
          ),
        ),
    ]);
  }
}

class _Materials extends StatelessWidget {
  const _Materials();
  static String _n(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 1).replaceAll('.', ',');
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Text('Por defecto se usa S275JR. Escribe el material en la descripción (p. ej. «en S355», «inox 316», '
          '«aluminio», «corten») o pon perfiles por partes: «pilares HEB 220, correas de tubo, tirantes de redondo 16».',
          style: TextStyle(color: cs.onSurfaceVariant)),
      const SizedBox(height: 8),
      for (final g in allGrades)
        Card(
          child: ListTile(
            title: Text('${g.name}  ·  ${g.norm}', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${g.description}\n'
                'fy ${_n(g.fy)} · fu ${_n(g.fu)} N/mm² · E ${_n(g.e / 1000)} GPa · ${_n(g.density)} kg/m³\n'
                'Soldadura: ${g.weld}\n${g.bolts}'),
            isThreeLine: true,
          ),
        ),
      const SizedBox(height: 8),
      Text('Cubiertas, suelos y cerramientos', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      for (final (k, v) in const [
        ('Panel sándwich', 'PUR/PIR 30–100 mm o lana de roca. Indica el espesor: «panel sándwich de 60 mm».'),
        ('Chapa grecada', 'Chapa trapezoidal de acero 0,5–0,8 mm.'),
        ('Policarbonato', 'Celular (6–32 mm) o compacto (3–12 mm).'),
        ('Teja', 'Teja sobre panel o rastrel.'),
        ('Vidrio', 'Laminado de seguridad (marquesinas y pérgolas).'),
        ('Fotovoltaica', 'Paneles solares sobre la estructura.'),
        ('Fibrocemento', 'Placa sin amianto.'),
        ('Suelos', 'Tramex, chapa lagrimada, chapa colaborante con losa, tablero fenólico o madera.'),
        ('Cerramientos', '«cerramiento de panel sándwich», «fachada de chapa», «laterales de policarbonato»…'),
      ])
        ListTile(dense: true, title: Text(k), subtitle: Text(v)),
    ]);
  }
}

class _Glossary extends StatefulWidget {
  const _Glossary();
  @override
  State<_Glossary> createState() => _GlossaryState();
}

class _GlossaryState extends State<_Glossary> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = normalize(_q.trim());
    bool hit(TradeTerm t) =>
        q.isEmpty ||
        normalize(t.term).contains(q) ||
        normalize(t.meaning).contains(q) ||
        t.aka.any((a) => normalize(a).contains(q));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar término (jácena, cartela, tramex…)'),
          onChanged: (v) => setState(() => _q = v),
        ),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(12), children: [
          for (final c in glossaryCategories)
            if (glossary.any((t) => t.category == c && hit(t))) ...[
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Text(c, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
              ),
              for (final t in glossary.where((t) => t.category == c && hit(t)))
                ListTile(
                  dense: true,
                  title: Text(t.term, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(t.aka.isEmpty ? t.meaning : '${t.meaning}\nTambién: ${t.aka.join(', ')}'),
                ),
            ],
        ]),
      ),
    ]);
  }
}
