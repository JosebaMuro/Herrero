import 'dart:async';
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../engine/pricing.dart';

/// Ubicación del dispositivo y búsqueda de distribuidores de material en el
/// mapa abierto (OpenStreetMap). No se envía nada más que las coordenadas o
/// el nombre de la población escrita.

const _ua = {'User-Agent': 'Herrero/4.3 (app de oficina tecnica de estructuras metalicas)', 'Accept-Language': 'es'};

/// Posición actual por GPS / red (Android, Windows con ubicación activada,
/// Linux con GeoClue). Lanza un texto explicando qué falta si no se puede.
Future<GeoPoint> currentPosition() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw 'La ubicación del dispositivo está desactivada. Actívala o escribe tu población.';
  }
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
  if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
    throw 'Sin permiso de ubicación. Puedes escribir tu población en su lugar.';
  }
  try {
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 20)),
    );
    return GeoPoint(p.latitude, p.longitude);
  } on TimeoutException {
    final last = await Geolocator.getLastKnownPosition().catchError((_) => null);
    if (last != null) return GeoPoint(last.latitude, last.longitude);
    throw 'No llega la posición. Prueba de nuevo o escribe tu población.';
  }
}

/// Coordenadas de una población o dirección escrita (Nominatim, OSM).
Future<(GeoPoint, String)?> geocode(String place, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {'q': place, 'format': 'json', 'limit': '1'});
    final r = await c.get(uri, headers: _ua).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) return null;
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as List;
    if (j.isEmpty) return null;
    final e = j.first as Map;
    final lat = double.tryParse('${e['lat']}'), lon = double.tryParse('${e['lon']}');
    if (lat == null || lon == null) return null;
    final name = '${e['display_name'] ?? place}'.split(',').take(2).join(',').trim();
    return (GeoPoint(lat, lon), name);
  } finally {
    if (client == null) c.close();
  }
}

/// Nombre de la población de unas coordenadas (para enseñarlo).
Future<String?> placeName(GeoPoint p, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse',
        {'lat': '${p.lat}', 'lon': '${p.lon}', 'format': 'json', 'zoom': '10'});
    final r = await c.get(uri, headers: _ua).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) return null;
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
    final a = (j['address'] as Map?) ?? const {};
    return (a['city'] ?? a['town'] ?? a['village'] ?? a['municipality'] ?? a['county'] ?? j['name'])?.toString();
  } catch (_) {
    return null;
  } finally {
    if (client == null) c.close();
  }
}

/// Consulta Overpass de almacenes de hierros, aceros, metales, ferralla,
/// ferreterías industriales y galvanizadores alrededor de [p].
String distributorsQuery(GeoPoint p, double radiusKm) {
  final r = (radiusKm.clamp(1, 150) * 1000).round();
  final a = 'around:$r,${p.lat.toStringAsFixed(5)},${p.lon.toStringAsFixed(5)}';
  const names = 'hierro|acero|aceros|metal|perfiles|ferralla|siderurg|chapa|tubos|galvaniz|ferreter[ií]a industrial|suministros industriales';
  return '[out:json][timeout:40];('
      'nwr($a)["shop"="trade"]["trade"~"metal|steel|building_supplies|hardware|industrial",i];'
      'nwr($a)["shop"="trade"]["name"~"$names",i];'
      'nwr($a)["shop"="hardware"]["name"~"industrial|suministros|hierro|metal",i];'
      'nwr($a)["industrial"]["name"~"$names",i];'
      'nwr($a)["office"="company"]["name"~"hierros|aceros|metales|siderurg|galvaniz",i];'
      'nwr($a)["craft"="metal_construction"]["name"~"galvaniz",i];'
      'nwr($a)["shop"="wholesale"]["name"~"$names",i];'
      ');out center tags 300;';
}

/// Lee la respuesta de Overpass y la convierte en proveedores con ubicación.
List<Supplier> parseDistributors(String body) {
  final j = jsonDecode(body) as Map;
  final out = <Supplier>[];
  final seen = <String>{};
  for (final e in (j['elements'] as List?) ?? const []) {
    final m = e as Map;
    final t = ((m['tags'] as Map?) ?? const {}).cast<String, Object?>();
    final name = '${t['name'] ?? t['brand'] ?? ''}'.trim();
    if (name.isEmpty) continue;
    final lat = (m['lat'] ?? (m['center'] as Map?)?['lat']) as num?;
    final lon = (m['lon'] ?? (m['center'] as Map?)?['lon']) as num?;
    if (lat == null || lon == null) continue;
    final key = '${name.toLowerCase()}|${lat.toStringAsFixed(3)}|${lon.toStringAsFixed(3)}';
    if (!seen.add(key)) continue;
    String s(List<String> ks) => ks.map((k) => '${t[k] ?? ''}').firstWhere((v) => v.isNotEmpty, orElse: () => '');
    final street = [s(['addr:street']), s(['addr:housenumber'])].where((v) => v.isNotEmpty).join(' ');
    final city = [s(['addr:postcode']), s(['addr:city'])].where((v) => v.isNotEmpty).join(' ');
    out.add(Supplier(
      id: 'osm${m['type'] ?? 'n'}${m['id']}',
      name: name,
      address: [street, city].where((v) => v.isNotEmpty).join(', '),
      location: GeoPoint(lat.toDouble(), lon.toDouble()),
      phone: s(['phone', 'contact:phone', 'mobile', 'contact:mobile']),
      email: s(['email', 'contact:email']),
      web: s(['website', 'contact:website', 'url']),
      source: SupplierSource.mapa,
    ));
  }
  return out;
}

/// Distribuidores cercanos según OpenStreetMap. El mapa no trae precios:
/// sirve para saber a quién pedirlos (con el pedido de material del
/// proyecto) y para guardar su ubicación junto a sus facturas o tarifas.
Future<List<Supplier>> nearbyDistributors(GeoPoint p, double radiusKm, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final q = distributorsQuery(p, radiusKm);
    Object? lastError;
    for (final host in ['overpass-api.de', 'overpass.kumi.systems', 'maps.mail.ru']) {
      try {
        final path = host == 'maps.mail.ru' ? '/osm/tools/overpass/api/interpreter' : '/api/interpreter';
        final r = await c
            .post(Uri.https(host, path), headers: {..._ua, 'Content-Type': 'application/x-www-form-urlencoded'}, body: {'data': q})
            .timeout(const Duration(seconds: 50));
        if (r.statusCode == 200) {
          final list = parseDistributors(utf8.decode(r.bodyBytes));
          list.sort((a, b) => p.distanceTo(a.location!).compareTo(p.distanceTo(b.location!)));
          return list;
        }
        lastError = 'HTTP ${r.statusCode}';
      } catch (e) {
        lastError = e;
      }
    }
    throw 'No se pudo consultar el mapa ($lastError). Comprueba la conexión.';
  } finally {
    if (client == null) c.close();
  }
}

/// Descarga la página de tarifas de un distribuidor y devuelve su texto
/// (sin etiquetas HTML) para leer precios con el lector de tarifas.
Future<(String, bool)> fetchPriceText(String url, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final r = await c.get(Uri.parse(url), headers: _ua).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw 'La página respondió ${r.statusCode}';
    final type = r.headers['content-type'] ?? '';
    if (type.contains('pdf') || (r.bodyBytes.length > 4 && String.fromCharCodes(r.bodyBytes.take(4)) == '%PDF')) {
      return (latin1.decode(r.bodyBytes, allowInvalid: true), true);
    }
    return (htmlToText(utf8.decode(r.bodyBytes, allowMalformed: true)), false);
  } finally {
    if (client == null) c.close();
  }
}

/// Texto plano de una página HTML, con una línea por fila de tabla o párrafo.
String htmlToText(String html) {
  var s = html
      .replaceAll(RegExp(r'<(script|style|noscript)[^>]*>[\s\S]*?</\1>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<\s*(br|/p|/tr|/li|/h\d|/div)\b[^>]*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<\s*/t[dh]\s*>', caseSensitive: false), '  ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ');
  const ents = {'&nbsp;': ' ', '&amp;': '&', '&euro;': '€', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#8364;': '€', '&aacute;': 'á', '&eacute;': 'é', '&iacute;': 'í', '&oacute;': 'ó', '&uacute;': 'ú', '&ntilde;': 'ñ'};
  ents.forEach((k, v) => s = s.replaceAll(k, v));
  return s.split('\n').map((l) => l.replaceAll(RegExp(r'[ \t]{2,}'), '  ').trim()).where((l) => l.isNotEmpty).join('\n');
}
