import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../engine/catalog.dart';
import '../engine/formacion.dart';
import '../engine/model.dart';
import '../engine/normativa.dart';
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
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Qué entiende Herrero'),
          bottom: const TabBar(isScrollable: true, tabAlignment: TabAlignment.center, tabs: [
            Tab(text: 'Estructuras', icon: Icon(Icons.foundation)),
            Tab(text: 'Materiales', icon: Icon(Icons.layers)),
            Tab(text: 'Vocabulario', icon: Icon(Icons.menu_book)),
            Tab(text: 'Normativa', icon: Icon(Icons.gavel)),
            Tab(text: 'Formación', icon: Icon(Icons.school)),
          ]),
        ),
        body: const TabBarView(children: [_Typologies(), _Materials(), _Glossary(), _Norms(), _Training()]),
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

/// Normativa de soldadura, estructura, herrería y calderería (resúmenes propios).
class _Norms extends StatefulWidget {
  const _Norms();
  @override
  State<_Norms> createState() => _NormsState();
}

class _NormsState extends State<_Norms> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = normalize(_q.trim());
    bool hit(Norm n) =>
        q.isEmpty ||
        normalize(n.code).contains(q) ||
        normalize(n.title).contains(q) ||
        normalize(n.summary).contains(q) ||
        n.points.any((p) => normalize(p).contains(q));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar norma (5817, TIG, galvanizado, EXC…)'),
          onChanged: (v) => setState(() => _q = v),
        ),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(12), children: [
          Text('Resúmenes orientativos con la referencia de cada norma. Para proyecto, consulta la edición vigente '
              '(AENOR, BOE). Escribe en la descripción lo que necesites: «soldadura TIG», «calidad B», «EXC3», '
              '«radiografiado», «junto al mar», «cordones continuos», «soldado en obra»…',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          for (final a in normAreas)
            if (normLibrary.any((n) => n.area == a && hit(n))) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(a, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
              ),
              for (final n in normLibrary.where((n) => n.area == a && hit(n)))
                Card(
                  child: ExpansionTile(
                    title: Text(n.code, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(n.title),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(n.summary),
                      for (final p in n.points)
                        Padding(padding: const EdgeInsets.only(top: 4), child: Text('•  $p')),
                    ],
                  ),
                ),
            ],
        ]),
      ),
    ]);
  }
}

/// Formación reglada y acreditación en calderería, soldadura y estructuras
/// metálicas, con enlaces a las fuentes oficiales.
class _Training extends StatefulWidget {
  const _Training();
  @override
  State<_Training> createState() => _TrainingState();
}

class _TrainingState extends State<_Training> {
  String _q = '';

  Future<void> _open(SourceLink l) async {
    final messenger = ScaffoldMessenger.of(context);
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(l.url), mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok) {
      await Clipboard.setData(ClipboardData(text: l.url));
      messenger.showSnackBar(SnackBar(content: Text('No se pudo abrir. Enlace copiado: ${l.url}')));
    }
  }

  Future<void> _copy(SourceLink l) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: l.url));
    messenger.showSnackBar(SnackBar(content: Text('Enlace copiado: ${l.url}')));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = normalize(_q.trim());
    bool hit(Training t) =>
        q.isEmpty ||
        normalize(t.code).contains(q) ||
        normalize(t.title).contains(q) ||
        normalize(t.level).contains(q) ||
        normalize(t.summary).contains(q) ||
        t.points.any((p) => normalize(p).contains(q));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: TextField(
          decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search), hintText: 'Buscar (TIG, calderería, FMEC0208, 9606, grado superior…)'),
          onChanged: (v) => setState(() => _q = v),
        ),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(12), children: [
          Text('Títulos de FP, certificados profesionales, cualificaciones, homologación del soldador y diplomas '
              'de soldadura, resumidos con enlace a la fuente oficial (TodoFP, INCUAL, SEPE, BOE, CESOL). Horas y '
              'módulos pueden variar por comunidad autónoma: manda la fuente. Toca un enlace para abrirlo; '
              'mantenlo pulsado para copiarlo.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          for (final a in trainingAreas)
            if (trainingLibrary.any((t) => t.area == a && hit(t))) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(a, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
              ),
              for (final t in trainingLibrary.where((t) => t.area == a && hit(t)))
                Card(
                  child: ExpansionTile(
                    title: Text(t.code, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text([t.title, if (t.level.isNotEmpty) t.level, if (t.hours.isNotEmpty) t.hours].join(' · ')),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.summary),
                      for (final p in t.points)
                        Padding(padding: const EdgeInsets.only(top: 4), child: Text('•  $p')),
                      if (t.links.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 4, children: [
                          for (final l in t.links)
                            Tooltip(
                              message: l.url,
                              child: InkWell(
                                onLongPress: () => _copy(l),
                                child: ActionChip(
                                  avatar: const Icon(Icons.open_in_new, size: 16),
                                  label: Text(l.label),
                                  onPressed: () => _open(l),
                                ),
                              ),
                            ),
                        ]),
                      ],
                    ],
                  ),
                ),
            ],
        ]),
      ),
    ]);
  }
}
