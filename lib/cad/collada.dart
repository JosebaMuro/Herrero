import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'dxf.dart' show MeshGroup;

/// Exporta el modelo 3D a COLLADA 1.4.1 (.dae), formato que SketchUp 2017
/// importa de forma nativa (Archivo > Importar) conservando un grupo y un
/// material por pieza. Unidades en metros, eje Z hacia arriba.
Uint8List colladaModel(List<MeshGroup> groups, {String title = 'Herrero'}) {
  final mats = <String, MeshGroup>{}; // id -> muestra de color
  String matId(MeshGroup g) {
    final id = 'mat_${(g.r * 255).round()}_${(g.g * 255).round()}_${(g.b * 255).round()}_${(g.alpha * 100).round()}';
    mats.putIfAbsent(id, () => g);
    return id;
  }

  String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
  String f(double v) {
    final s = v.toStringAsFixed(5);
    return s.contains('.') ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '') : s;
  }

  final geo = StringBuffer();
  final nodes = StringBuffer();
  final now = DateTime.now().toUtc().toIso8601String();
  for (var gi = 0; gi < groups.length; gi++) {
    final g = groups[gi];
    final t = g.tris;
    final nTri = t.length ~/ 9;
    if (nTri == 0) continue;
    final id = 'g$gi';
    final mid = matId(g);
    // normales por cara
    final normals = StringBuffer();
    final pos = StringBuffer();
    for (var i = 0; i < nTri; i++) {
      final o = i * 9;
      final ux = t[o + 3] - t[o], uy = t[o + 4] - t[o + 1], uz = t[o + 5] - t[o + 2];
      final vx = t[o + 6] - t[o], vy = t[o + 7] - t[o + 1], vz = t[o + 8] - t[o + 2];
      var nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
      final l = (nx * nx + ny * ny + nz * nz);
      if (l > 0) {
        final il = 1 / math.sqrt(l);
        nx *= il;
        ny *= il;
        nz *= il;
      }
      normals.write('${f(nx)} ${f(ny)} ${f(nz)} ');
      for (var k = 0; k < 9; k++) {
        pos
          ..write(f(t[o + k]))
          ..write(' ');
      }
    }
    final idx = StringBuffer();
    for (var i = 0; i < nTri; i++) {
      idx.write('${i * 3} $i ${i * 3 + 1} $i ${i * 3 + 2} $i ');
    }
    geo.write('''
    <geometry id="$id" name="${esc(g.name)}">
      <mesh>
        <source id="$id-pos">
          <float_array id="$id-pos-arr" count="${nTri * 9}">$pos</float_array>
          <technique_common><accessor source="#$id-pos-arr" count="${nTri * 3}" stride="3">
            <param name="X" type="float"/><param name="Y" type="float"/><param name="Z" type="float"/>
          </accessor></technique_common>
        </source>
        <source id="$id-nrm">
          <float_array id="$id-nrm-arr" count="${nTri * 3}">$normals</float_array>
          <technique_common><accessor source="#$id-nrm-arr" count="$nTri" stride="3">
            <param name="X" type="float"/><param name="Y" type="float"/><param name="Z" type="float"/>
          </accessor></technique_common>
        </source>
        <vertices id="$id-vtx"><input semantic="POSITION" source="#$id-pos"/></vertices>
        <triangles count="$nTri" material="m">
          <input semantic="VERTEX" source="#$id-vtx" offset="0"/>
          <input semantic="NORMAL" source="#$id-nrm" offset="1"/>
          <p>$idx</p>
        </triangles>
      </mesh>
    </geometry>
''');
    nodes.write('''
      <node id="n$gi" name="${esc(g.name)}">
        <instance_geometry url="#$id">
          <bind_material><technique_common>
            <instance_material symbol="m" target="#$mid"/>
          </technique_common></bind_material>
        </instance_geometry>
      </node>
''');
  }
  final effects = StringBuffer();
  final materials = StringBuffer();
  for (final e in mats.entries) {
    final g = e.value;
    effects.write('''
    <effect id="${e.key}-fx">
      <profile_COMMON><technique sid="common"><lambert>
        <diffuse><color>${f(g.r)} ${f(g.g)} ${f(g.b)} 1</color></diffuse>
        ${g.alpha < 1 ? '<transparent opaque="A_ONE"><color>1 1 1 ${f(g.alpha)}</color></transparent><transparency><float>1</float></transparency>' : ''}
      </lambert></technique></profile_COMMON>
    </effect>
''');
    materials.write('    <material id="${e.key}" name="${e.key}"><instance_effect url="#${e.key}-fx"/></material>\n');
  }
  final xml = '''<?xml version="1.0" encoding="utf-8"?>
<COLLADA xmlns="http://www.collada.org/2005/11/COLLADASchema" version="1.4.1">
  <asset>
    <contributor><authoring_tool>Herrero</authoring_tool></contributor>
    <created>$now</created>
    <modified>$now</modified>
    <unit name="meter" meter="1"/>
    <up_axis>Z_UP</up_axis>
  </asset>
  <library_effects>
$effects  </library_effects>
  <library_materials>
$materials  </library_materials>
  <library_geometries>
$geo  </library_geometries>
  <library_visual_scenes>
    <visual_scene id="escena" name="${esc(title)}">
$nodes    </visual_scene>
  </library_visual_scenes>
  <scene><instance_visual_scene url="#escena"/></scene>
</COLLADA>
''';
  return Uint8List.fromList(utf8.encode(xml));
}
