// Importar un modelo que el usuario ha descargado por su cuenta (desde la web, otro
// ordenador, un pendrive…): se reconoce a qué modelo de Herrero corresponde, se
// comprueba el formato y que el motor de la app puede abrirlo, y se instala.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:onnxruntime/onnxruntime.dart';

import 'accel.dart';
import 'model_manager.dart';
import 'onnx_inspect.dart';

/// Fichero de destino de un modelo del catálogo.
class ImportTarget {
  final ModelVariant variant;
  final String file;
  const ImportTarget(this.variant, this.file);

  String get label {
    final part = variant.parts.where((p) => p.$2 == file).firstOrNull?.$1 ?? file;
    return '${variant.name} · $part';
  }

  @override
  bool operator ==(Object other) => other is ImportTarget && other.variant.id == variant.id && other.file == file;
  @override
  int get hashCode => Object.hash(variant.id, file);
}

/// Entradas mínimas que la app pasa a cada modelo ONNX (lo que hace falta para que el
/// fichero importado sirva en ese paso).
List<String> expectedInputs(String file) {
  final f = file.toLowerCase();
  if (f.contains('text_encoder')) return const ['input_ids'];
  if (f.contains('unet')) return const ['sample', 'timestep', 'encoder_hidden_states'];
  if (f.contains('vae_encoder') || f == 'taesd_encoder.onnx') return const ['sample'];
  if (f.contains('vae_decoder') || f == 'taesd_decoder.onnx') return const ['latent_sample'];
  if (f.startsWith('ppocrv4_')) return const ['x'];
  if (f.startsWith('e5s_model') || f.startsWith('jinaes_model')) return const ['input_ids', 'attention_mask'];
  if ((f.startsWith('qwen3_model') || f.startsWith('qwen3think_model')) && f.endsWith('.onnx')) {
    return const ['input_ids', 'attention_mask', 'past_key_values.0.key'];
  }
  if (f.contains('_vision')) return const ['pixel_values'];
  if (f.contains('_embed')) return const ['input_ids'];
  if (f.contains('_decoder')) return const ['inputs_embeds', 'attention_mask', 'position_ids'];
  return const [];
}

/// Todos los ficheros del catálogo (una vez por nombre; los compartidos van con la
/// primera variante que los usa).
List<ImportTarget> allTargets() {
  final seen = <String>{};
  return [
    for (final m in catalog)
      for (final f in m.files)
        if (seen.add('${m.subdir}/$f')) ImportTarget(m, f),
  ];
}

/// Destinos posibles para un fichero: primero por nombre exacto; si no, por formato y
/// entradas del modelo. [only]: limitar a una variante.
List<ImportTarget> candidatesFor(String fileName, OnnxInfo info, {ModelVariant? only}) {
  final name = fileName.split(RegExp(r'[\\/]')).last;
  final pool = only == null ? allTargets() : [for (final f in only.files) ImportTarget(only, f)];
  final exact = pool.where((t) => t.file == name).toList();
  if (exact.isNotEmpty) return exact;
  final lower = name.toLowerCase();
  if (info.format == ModelFormat.onnx) {
    final ins = info.inputs.toSet();
    final match = pool.where((t) {
      if (!t.file.endsWith('.onnx')) return false;
      final exp = expectedInputs(t.file);
      return exp.isNotEmpty && exp.every(ins.contains);
    }).toList();
    // el más específico gana: un UNet también tiene «sample», pero no es un codificador
    if (match.length > 1) {
      final best = match.map((t) => expectedInputs(t.file).length).reduce((a, b) => a > b ? a : b);
      match.retainWhere((t) => expectedInputs(t.file).length == best);
    }
    // el codificador de texto y el de embeddings piden lo mismo: se afina por las salidas
    // y por el nombre que trae el fichero
    if (match.length > 1) {
      final byName = match.where((t) => _nameHints(t.file).any(lower.contains)).toList();
      if (byName.isNotEmpty) return byName;
    }
    return match;
  }
  // tokenizadores, configuraciones, vocabularios
  final ext = lower.endsWith('.json') ? '.json' : (lower.endsWith('.txt') ? '.txt' : '');
  if (ext.isEmpty) return const [];
  final sameExt = pool.where((t) => t.file.endsWith(ext)).toList();
  final byKind = sameExt.where((t) {
    for (final k in const ['tokenizer', 'config', 'vocab', 'merges', 'keys']) {
      if (lower.contains(k) && t.file.contains(k)) return true;
    }
    return false;
  }).toList();
  final narrowed = byKind.where((t) => _nameHints(t.file).any(lower.contains)).toList();
  return narrowed.isNotEmpty ? narrowed : (byKind.isNotEmpty ? byKind : sameExt);
}

List<String> _nameHints(String file) {
  final f = file.toLowerCase();
  if (f.startsWith('qwen3think')) return const ['thinking', '4b'];
  if (f.startsWith('qwen3')) return const ['qwen'];
  if (f.startsWith('e5s')) return const ['e5', 'multilingual'];
  if (f.startsWith('jinaes')) return const ['jina', '-es', '_es'];
  if (f.startsWith('smolvlm500')) return const ['500'];
  if (f.startsWith('smolvlm')) return const ['smolvlm', '256'];
  if (f.startsWith('ppocr')) return [if (f.contains('det')) 'det', if (f.contains('rec')) 'rec'];
  if (f.contains('taesd')) return const ['taesd', 'tiny'];
  if (f.contains('unet')) return const ['unet'];
  if (f.contains('text_encoder')) return const ['text_encoder', 'clip'];
  if (f.contains('vae')) return const ['vae'];
  return const [];
}

/// Resultado de comprobar un fichero.
class ImportCheck {
  final String path;
  final OnnxInfo info;
  final String sha256;
  final int size;
  final List<String> errors;
  final List<String> warnings;
  const ImportCheck(this.path, this.info, this.sha256, this.size, this.errors, this.warnings);
  bool get ok => errors.isEmpty;
}

/// Lee el formato de [path] (rápido, sin cargar el modelo).
OnnxInfo sniff(String path) {
  try {
    return inspectModelFile(path);
  } on ModelFormatException {
    return const OnnxInfo(format: ModelFormat.unknown);
  }
}

/// Comprueba [path] para [target]: formato, compatibilidad con ONNX Runtime 1.20,
/// entradas que usa la app, que el motor lo abre y si es idéntico al oficial.
Future<ImportCheck> checkImport(String path, ImportTarget target, {String? officialSha, int? officialSize}) {
  return Isolate.run(() async {
    final errors = <String>[];
    final warnings = <String>[];
    final file = File(path);
    final size = file.lengthSync();
    var info = const OnnxInfo(format: ModelFormat.unknown);
    final digest = (await sha256.bind(file.openRead()).first).toString();
    final official = officialSha != null && digest == officialSha;
    if (target.file.endsWith('.onnx')) {
      try {
        info = inspectModelFile(path);
      } on ModelFormatException catch (e) {
        errors.add(e.message);
      }
      if (errors.isEmpty) errors.addAll(ortCompatibilityProblems(info));
      if (errors.isEmpty) {
        final missing = expectedInputs(target.file).where((i) => !info.inputs.contains(i)).toList();
        if (missing.isNotEmpty) {
          errors.add('No es el modelo de «${target.label}»: le faltan las entradas ${missing.join(', ')} '
              '(tiene ${info.inputs.take(6).join(', ')}${info.inputs.length > 6 ? '…' : ''}).');
        }
      }
      if (errors.isEmpty && !official) {
        // la prueba definitiva: que el ONNX Runtime de la app lo abra (en CPU)
        try {
          OrtEnv.instance.init();
          final o = ortOpenAccel(path, 1, AiEngine.cpu);
          o.session.release();
        } catch (e) {
          final s = '$e';
          errors.add('El motor de la app no puede abrirlo: ${s.length > 300 ? '${s.substring(0, 300)}…' : s}');
        }
      }
    } else {
      try {
        final text = await file.readAsString();
        if (text.trim().isEmpty) errors.add('El fichero está vacío.');
        if (target.file.endsWith('.json')) {
          final j = jsonDecode(text);
          if (j is! Map) {
            errors.add('No tiene el formato esperado (se esperaba un objeto JSON).');
          } else if (target.file.contains('tokenizer') && j['model'] == null) {
            errors.add('No es un tokenizador de Hugging Face (tokenizer.json).');
          }
        }
      } on FormatException {
        errors.add('No es un JSON válido o no es texto UTF-8.');
      } on FileSystemException catch (e) {
        errors.add('No se puede leer: ${e.message}');
      }
    }
    if (errors.isEmpty && officialSha != null && !official) {
      warnings.add('No es idéntico al fichero oficial de Herrero${officialSize != null && officialSize != size ? ' (tamaño distinto)' : ''}. '
          'Es compatible, pero los resultados pueden ser distintos; si no va bien, descarga el oficial.');
    }
    if (errors.isEmpty && officialSha == null) {
      warnings.add('No se ha podido comparar con el oficial (abre «Modelos de IA» con internet una vez para leer el catálogo).');
    }
    return ImportCheck(path, info, digest, size, errors, warnings);
  });
}
