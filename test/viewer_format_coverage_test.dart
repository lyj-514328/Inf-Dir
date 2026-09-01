import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final expectedByPlugin = <String, Set<String>>{
    'inf-dir.image-view': {
      '.cr3', '.3fr', '.fff', '.rwl',
      '.psd', '.jp2', '.j2k', '.jxl', '.jxr', '.dcm', '.dpx', '.cin',
      '.sgi', '.rgb', '.xpm', '.xbm', '.xface', '.dds', '.exr',
    },
    'inf-dir.mupdf-view': {
      '.xps', '.oxps', '.dwg', '.dxf',
      '.djvu', '.djv',
      '.epub', '.mobi', '.fb2', '.fbz', '.fb2z', '.tcr', '.cbr',
      '.vsd', '.vsdx', '.vst', '.vss', '.vdx', '.vdw', '.vsx', '.vtx',
      '.vstx', '.vssx', '.vstm', '.vsdm', '.wps',
    },
    'inf-dir.onlyoffice-view': {
      '.doc', '.docm', '.docx', '.dot', '.dotm', '.dotx',
      '.odt', '.ott', '.fodt', '.rtf', '.ppt', '.pptm', '.pptx', '.pot', '.potm',
      '.potx', '.pps', '.ppsm', '.ppsx', '.odp', '.otp', '.fodp',
      '.xls', '.xlsb', '.xlsx', '.xlsm', '.xlt', '.xltm', '.xltx',
    },
    'inf-dir.project-view': {'.mpp', '.mpt', '.mpx'},
    'inf-dir.font-view': {'.ttf', '.otf', '.woff', '.woff2', '.ttc', '.dfont'},
    'inf-dir.chm-view': {'.chm'},
    'inf-dir.web-view': {
      '.svg', '.svgz', '.html', '.htm', '.xhtml',
      '.mht', '.mhtml', '.shtml', '.shtm',
      '.xml', '.xsl', '.xslt',
    },
  };

  test('P2 roadmap formats are assigned to working viewer manifests', () {
    final manifests = _loadPluginManifests();
    for (final entry in expectedByPlugin.entries) {
      expect(manifests, contains(entry.key), reason: 'missing ${entry.key}');
      expect(
        manifests[entry.key],
        containsAll(entry.value),
        reason: '${entry.key} does not cover the roadmap',
      );
    }
  });

  test('viewer manifest extensions are normalized and unique per plugin', () {
    final manifests = _loadPluginManifests();
    for (final entry in manifests.entries) {
      final extensions = entry.value.toList();
      expect(extensions, everyElement(matches(RegExp(r'^\.[a-z0-9][a-z0-9.+-]*$'))));
      expect(extensions.toSet().length, extensions.length, reason: entry.key);
    }
  });

  test('onlyoffice-view declares Excel formats for x2t conversion', () {
    final manifests = _loadPluginManifests();
    final extensions = manifests['inf-dir.onlyoffice-view']!;
    expect(
      extensions,
      containsAll(<String>['.xls', '.xlsb', '.xlsx', '.xlsm', '.xlt', '.xltm', '.xltx']),
    );
  });

  test('onlyoffice-view does not claim Visio formats', () {
    final manifests = _loadPluginManifests();
    final extensions = manifests['inf-dir.onlyoffice-view']!;
    expect(
      extensions,
      isNot(anyOf(
        contains('.vsd'),
        contains('.vsdx'),
        contains('.vss'),
        contains('.vst'),
        contains('.wps'),
      )),
    );
  });
}

Map<String, List<String>> _loadPluginManifests() {
  final result = <String, List<String>>{};
  for (final entity in Directory('plugins').listSync()) {
    if (entity is! Directory) continue;
    final manifest = File('${entity.path}${Platform.pathSeparator}plugin.json');
    if (!manifest.existsSync()) continue;
    final json = jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
    final id = json['id'] as String;
    final capabilities = json['capabilities'] as Map<String, dynamic>?;
    final quickView = capabilities?['quickView'] as Map<String, dynamic>?;
    final extensions = quickView?['extensions'] as List<dynamic>?;
    if (extensions == null) continue;
    result[id] = extensions.cast<String>();
  }
  return result;
}
