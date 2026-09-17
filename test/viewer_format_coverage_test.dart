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
    'inf-dir.pdfjs-view': {
      '.dwg', '.dxf',
      '.xps', '.oxps',
      '.wps',
      '.doc', '.docm', '.docx', '.dot', '.dotm', '.dotx',
      '.odt', '.ott', '.fodt', '.rtf', '.ppt', '.pptm', '.pptx', '.pot', '.potm',
      '.potx', '.pps', '.ppsm', '.ppsx', '.odp', '.otp', '.fodp',
      '.xls', '.xlsb', '.xlsx', '.xlsm', '.xlt', '.xltm', '.xltx',
    },
    // excel-view owns the whole spreadsheet family: the OOXML formats it renders
    // directly, and the legacy/ODF ones it normalises to xlsx via LibreOffice.
    'inf-dir.excel-view': {
      '.xlsx', '.xlsm', '.xltx', '.xltm',
      '.xls', '.xlt', '.xlsb', '.ods', '.ots',
    },
    'inf-dir.project-view': {'.mpp', '.mpt', '.mpx'},
    // Fallback candidates that the bundled quick-view.default.json relies on:
    // the archive viewer lists CBZ contents and code-view shows Markdown or
    // XHTML as source, so both have to declare what the default rules assume.
    'inf-dir.archive-view': {'.cbz'},
    'inf-dir.ebook-view': {
      '.epub', '.mobi', '.azw', '.azw3', '.fb2', '.fbz', '.fb2z', '.cbz',
      '.cbr', '.tcr', '.djvu', '.djv',
    },
    'inf-dir.font-view': {'.ttf', '.otf', '.woff', '.woff2', '.ttc', '.dfont'},
    'inf-dir.chm-view': {'.chm'},
    'inf-dir.web-view': {
      '.svg', '.svgz', '.html', '.htm', '.xhtml',
      '.mht', '.mhtml', '.shtml', '.shtm',
      '.xml', '.xsl', '.xslt',
      '.vsd', '.vsdm', '.vsdx', '.vss', '.vssm', '.vssx',
      '.vst', '.vstm', '.vstx', '.vdx', '.vdw', '.vsx', '.vtx',
    },
    'inf-dir.code-view': {'.markdown', '.md', '.mdown', '.mkd', '.xhtml'},
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

  test('pdfjs-view declares Office conversion formats for LibreOffice', () {
    final manifests = _loadPluginManifests();
    final extensions = manifests['inf-dir.pdfjs-view']!;
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
    expect(manifests, isNot(contains('inf-dir.office-view')));
    expect(manifests, isNot(contains('inf-dir.mupdf-view')));
  });

  test('preset rule tree routes only to plugins that exist', () {
    final pluginIds = _pluginIds();
    for (final rule in _flattenRules(_readDefaultRuleTree())) {
      for (final id in _viewerIdsFor(rule)) {
        expect(
          pluginIds,
          contains(id),
          reason: '${rule['id']} routes to $id which has no plugin.json',
        );
      }
    }
  });

  test('spreadsheet rules prefer excel-view and office rules do not', () {
    final rules = _flattenRules(_readDefaultRuleTree());
    for (final extension in [
      '.xlsx', '.xlsm', '.xltx', '.xltm',
      '.xls', '.xlt', '.xlsb', '.ods', '.ots',
    ]) {
      expect(
        _viewerIdsFor(_extensionRule(rules, extension)).first,
        'inf-dir.excel-view',
        reason: '$extension should hit excel-view before the PDF fallback',
      );
    }
    for (final extension in ['.doc', '.docx', '.ppt', '.pptx', '.ppsm', '.odp']) {
      expect(
        _viewerIdsFor(_extensionRule(rules, extension)),
        ['inf-dir.pdfjs-view'],
        reason: '$extension is out of scope for the spreadsheet viewer',
      );
    }
  });

  test('visio rules route to web-view and XPS rules route to pdfjs-view', () {
    final rules = _flattenRules(_readDefaultRuleTree());
    for (final extension in ['.vsd', '.vsdx', '.vstx']) {
      expect(
        _viewerIdsFor(_extensionRule(rules, extension)),
        ['inf-dir.web-view'],
        reason: '$extension is rendered as converted SVG by web-view',
      );
    }
    for (final extension in ['.xps', '.oxps']) {
      expect(
        _viewerIdsFor(_extensionRule(rules, extension)),
        ['inf-dir.pdfjs-view'],
        reason: '$extension is converted to PDF by pdfjs-view',
      );
    }
  });
}

Map<String, dynamic> _readDefaultRuleTree() {
  final file = File('plugins${Platform.pathSeparator}quick-view.default.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

/// Every rule in the preset tree, including nested MIME subclasses.
List<Map<String, dynamic>> _flattenRules(Map<String, dynamic> config) {
  final flattened = <Map<String, dynamic>>[];
  void visit(List<dynamic> rules) {
    for (final rule in rules.cast<Map<String, dynamic>>()) {
      flattened.add(rule);
      visit(rule['rules'] as List<dynamic>? ?? const []);
    }
  }

  visit(config['rules'] as List<dynamic>);
  return flattened;
}

Map<String, dynamic> _extensionRule(List<Map<String, dynamic>> rules, String extension) {
  return rules.firstWhere(
    (rule) =>
        rule['type'] == 'extension' &&
        (rule['value'] as String).toLowerCase() == extension,
    orElse: () => throw StateError('no extension rule for $extension'),
  );
}

List<String> _viewerIdsFor(Map<String, dynamic> rule) {
  final viewers = rule['viewers'] as List<dynamic>? ?? const [];
  return viewers
      .cast<Map<String, dynamic>>()
      .where((viewer) => viewer['enabled'] != false)
      .map((viewer) => viewer['id'] as String)
      .toList();
}

Set<String> _pluginIds() {
  final ids = <String>{};
  for (final entity in Directory('plugins').listSync()) {
    if (entity is! Directory) continue;
    final manifest = File('${entity.path}${Platform.pathSeparator}plugin.json');
    if (!manifest.existsSync()) continue;
    final json = jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
    ids.add(json['id'] as String);
  }
  return ids;
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
