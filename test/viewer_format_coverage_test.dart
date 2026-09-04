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

  test('mupdf-view declares Office conversion formats for LibreOffice', () {
    final manifests = _loadPluginManifests();
    final extensions = manifests['inf-dir.mupdf-view']!;
    expect(
      extensions,
      containsAll(<String>[
        '.doc', '.xls', '.ppt', '.dot', '.xlt', '.pot', '.pps', '.xlsb',
        '.odt', '.ods', '.odp', '.rtf', '.wps', '.wbk',
      ]),
    );
  });

  test('no plugin manifest references a removed viewer', () {
    final manifests = _loadPluginManifests();
    expect(manifests, isNot(contains('inf-dir.onlyoffice-view')));
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
