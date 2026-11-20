// Lectura rápida de la cabecera de un modelo descargado por el usuario, sin cargarlo:
// formato (ONNX, GGUF, safetensors, TFLite, PyTorch…), versión IR, opsets, entradas y
// salidas del grafo y si guarda los pesos en un fichero externo.
//
// ONNX es protobuf: se recorre el mensaje ModelProto saltando los bloques grandes
// (pesos) con seek, así que leer un modelo de 600 MB cuesta milisegundos.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Formato de fichero detectado.
enum ModelFormat { onnx, ortFormat, gguf, safetensors, tflite, pytorch, json, text, unknown }

extension ModelFormatLabel on ModelFormat {
  String get label => const {
        ModelFormat.onnx: 'ONNX',
        ModelFormat.ortFormat: 'ONNX Runtime (.ort)',
        ModelFormat.gguf: 'GGUF (llama.cpp)',
        ModelFormat.safetensors: 'safetensors',
        ModelFormat.tflite: 'TensorFlow Lite',
        ModelFormat.pytorch: 'PyTorch',
        ModelFormat.json: 'JSON',
        ModelFormat.text: 'texto',
        ModelFormat.unknown: 'desconocido',
      }[this]!;
}

/// Lo que se sabe de un fichero de modelo sin ejecutarlo.
class OnnxInfo {
  final ModelFormat format;
  final int irVersion;
  final String producer;
  final Map<String, int> opsets; // dominio ('' = ai.onnx) -> versión
  final List<String> inputs;
  final List<String> outputs;
  final bool externalData;
  final int initializers;
  const OnnxInfo({
    required this.format,
    this.irVersion = 0,
    this.producer = '',
    this.opsets = const {},
    this.inputs = const [],
    this.outputs = const [],
    this.externalData = false,
    this.initializers = 0,
  });

  int get onnxOpset => opsets[''] ?? opsets['ai.onnx'] ?? 0;
}

/// Versiones que admite ONNX Runtime 1.20 (el que lleva la app).
const ortMaxIrVersion = 10;
const ortMaxOpset = 21;

/// Dominios de operadores que conoce ONNX Runtime 1.20.
const ortKnownDomains = {'', 'ai.onnx', 'ai.onnx.ml', 'com.microsoft', 'com.microsoft.nchwc', 'ai.onnx.training',
  'ai.onnx.preview.training', 'com.microsoft.experimental', 'com.ms.internal.nhwc', 'org.pytorch.aten'};

/// Detecta el formato por los primeros bytes (y la extensión como pista).
ModelFormat sniffFormat(Uint8List head, String name) {
  final lower = name.toLowerCase();
  String ascii(int a, int b) => head.length >= b ? String.fromCharCodes(head.sublist(a, b)) : '';
  if (ascii(0, 4) == 'GGUF') return ModelFormat.gguf;
  if (ascii(4, 8) == 'TFL3') return ModelFormat.tflite;
  if (ascii(4, 8) == 'ORTM') return ModelFormat.ortFormat;
  if (head.length >= 2 && head[0] == 0x50 && head[1] == 0x4B) {
    // zip: PyTorch (.pt/.pth/.bin modernos) o un archivo comprimido cualquiera
    return ModelFormat.pytorch;
  }
  if (head.length >= 2 && head[0] == 0x80 && head[1] <= 5) return ModelFormat.pytorch; // pickle
  if (head.length >= 9 && head[8] == 0x7B && ByteData.sublistView(head, 0, 8).getUint64(0, Endian.little) < 1 << 31) {
    return ModelFormat.safetensors; // 8 bytes de longitud + cabecera JSON
  }
  final first = head.firstWhere((b) => b != 0x20 && b != 0x0A && b != 0x0D && b != 0x09 && b != 0xEF && b != 0xBB && b != 0xBF,
      orElse: () => 0);
  if ((first == 0x7B || first == 0x5B) && !lower.endsWith('.onnx')) return ModelFormat.json;
  // ModelProto empieza casi siempre por ir_version (campo 1, varint: 0x08)
  if (head.isNotEmpty && head[0] == 0x08) return ModelFormat.onnx;
  if (lower.endsWith('.onnx')) return ModelFormat.onnx;
  if (lower.endsWith('.txt') || lower.endsWith('.json')) return ModelFormat.text;
  return ModelFormat.unknown;
}

/// Error de formato con un mensaje para el usuario.
class ModelFormatException implements Exception {
  final String message;
  ModelFormatException(this.message);
  @override
  String toString() => message;
}

/// Lee la cabecera de [path]. Lanza [ModelFormatException] si no es un ONNX legible.
OnnxInfo inspectModelFile(String path) {
  final f = File(path);
  final raf = f.openSync();
  try {
    final len = raf.lengthSync();
    final head = raf.readSync(16);
    final fmt = sniffFormat(head, path);
    if (fmt != ModelFormat.onnx) return OnnxInfo(format: fmt);
    raf.setPositionSync(0);
    return _parseModel(_Reader(raf, len));
  } finally {
    raf.closeSync();
  }
}

/// Lector protobuf sobre un fichero con búfer y saltos por seek.
class _Reader {
  final RandomAccessFile raf;
  final int length;
  _Reader(this.raf, this.length);

  static const _bufSize = 8192; // pequeño: tras cada salto de pesos se relee
  Uint8List _buf = Uint8List(0);
  int _bufStart = 0; // posición en el fichero de _buf[0]
  int pos = 0;

  int _byte() {
    if (pos >= length) throw ModelFormatException('El fichero está cortado (descarga incompleta).');
    if (pos < _bufStart || pos >= _bufStart + _buf.length) {
      raf.setPositionSync(pos);
      _buf = raf.readSync(_bufSize);
      _bufStart = pos;
    }
    return _buf[pos++ - _bufStart];
  }

  int varint() {
    var shift = 0;
    var result = 0;
    while (true) {
      final b = _byte();
      if (shift < 63) result |= (b & 0x7F) << shift;
      if (b & 0x80 == 0) return result;
      shift += 7;
      if (shift > 70) throw ModelFormatException('No es un modelo ONNX válido (varint incorrecto).');
    }
  }

  Uint8List bytes(int n) {
    if (n < 0 || pos + n > length) throw ModelFormatException('El fichero está cortado (descarga incompleta).');
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      out[i] = _byte();
    }
    return out;
  }

  String string(int n) => utf8.decode(bytes(n), allowMalformed: true);

  void skip(int wire) {
    switch (wire) {
      case 0:
        varint();
      case 1:
        _seek(8);
      case 2:
        _seek(varint());
      case 5:
        _seek(4);
      default:
        throw ModelFormatException('No es un modelo ONNX válido (tipo de campo $wire).');
    }
  }

  void _seek(int n) {
    if (n < 0 || pos + n > length) throw ModelFormatException('El fichero está cortado (descarga incompleta).');
    pos += n;
  }

  /// Recorre los campos de un mensaje que acaba en [end].
  void fields(int end, void Function(int field, int wire) onField) {
    while (pos < end) {
      final key = varint();
      final field = key >> 3;
      final wire = key & 7;
      if (field == 0) throw ModelFormatException('No es un modelo ONNX válido (campo 0).');
      final before = pos;
      onField(field, wire);
      if (pos == before) skip(wire); // el callback no lo consumió
    }
    if (pos != end) throw ModelFormatException('No es un modelo ONNX válido (mensaje mal cerrado).');
  }
}

OnnxInfo _parseModel(_Reader r) {
  var ir = 0;
  var producer = '';
  final opsets = <String, int>{};
  var inputs = <String>[];
  var outputs = <String>[];
  var external = false;
  var inits = 0;
  var sawGraph = false;
  r.fields(r.length, (field, wire) {
    if (field == 1 && wire == 0) {
      ir = r.varint();
    } else if (field == 2 && wire == 2) {
      producer = r.string(r.varint());
    } else if (field == 7 && wire == 2) {
      final end = r.varint() + r.pos;
      sawGraph = true;
      r.fields(end, (gf, gw) {
        if ((gf == 11 || gf == 12) && gw == 2) {
          final vend = r.varint() + r.pos;
          var name = '';
          r.fields(vend, (vf, vw) {
            if (vf == 1 && vw == 2) name = r.string(r.varint());
          });
          (gf == 11 ? inputs : outputs).add(name);
        } else if (gf == 5 && gw == 2) {
          inits++;
          final tend = r.varint() + r.pos;
          r.fields(tend, (tf, tw) {
            if (tf == 14 && tw == 0 && r.varint() == 1) external = true;
          });
        }
      });
    } else if (field == 8 && wire == 2) {
      final end = r.varint() + r.pos;
      var domain = '';
      var version = 0;
      r.fields(end, (of, ow) {
        if (of == 1 && ow == 2) {
          domain = r.string(r.varint());
        } else if (of == 2 && ow == 0) {
          version = r.varint();
        }
      });
      opsets[domain] = version;
    }
  });
  if (ir == 0 || !sawGraph) throw ModelFormatException('No es un modelo ONNX válido (no tiene grafo).');
  // las entradas del grafo pueden incluir pesos en modelos antiguos (IR < 4): no cuentan
  return OnnxInfo(
    format: ModelFormat.onnx,
    irVersion: ir,
    producer: producer,
    opsets: opsets,
    inputs: inputs,
    outputs: outputs,
    externalData: external,
    initializers: inits,
  );
}

/// Problemas de compatibilidad con el ONNX Runtime de la app (vacío si ninguno).
List<String> ortCompatibilityProblems(OnnxInfo i) {
  switch (i.format) {
    case ModelFormat.onnx:
      break;
    case ModelFormat.gguf:
      return ['Es un modelo GGUF (llama.cpp). Herrero usa ONNX: busca la versión ONNX del modelo.'];
    case ModelFormat.safetensors:
    case ModelFormat.pytorch:
      return ['Son pesos de ${i.format.label}, no un modelo ejecutable. Hay que convertirlo a ONNX (optimum-cli export onnx).'];
    case ModelFormat.tflite:
      return ['Es un modelo TensorFlow Lite. Herrero usa ONNX.'];
    case ModelFormat.ortFormat:
      return ['Es un modelo en formato .ort. Importa el fichero .onnx original.'];
    default:
      return ['No es un modelo ONNX.'];
  }
  final out = <String>[];
  if (i.irVersion > ortMaxIrVersion) {
    out.add('Versión IR ${i.irVersion}: el motor de la app (ONNX Runtime 1.20) admite hasta la $ortMaxIrVersion. '
        'Exporta el modelo con un opset más antiguo.');
  }
  if (i.onnxOpset > ortMaxOpset) {
    out.add('Opset ${i.onnxOpset}: ONNX Runtime 1.20 admite hasta el $ortMaxOpset.');
  }
  for (final d in i.opsets.keys) {
    if (!ortKnownDomains.contains(d)) out.add('Usa operadores personalizados ($d) que la app no tiene.');
  }
  if (i.externalData) {
    out.add('Guarda los pesos en un fichero aparte (.onnx_data). Importa un modelo de un solo fichero.');
  }
  return out;
}
