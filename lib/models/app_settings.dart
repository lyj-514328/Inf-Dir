enum NewTabLocation { current, home, custom }

class UnsupportedSettingsVersion implements Exception {
  const UnsupportedSettingsVersion(this.version);

  final int version;

  @override
  String toString() => 'Unsupported settings schema version: $version';
}

class AppSettings {
  static const currentSchemaVersion = 2;

  static const _themeModes = {'system', 'light', 'dark'};
  static const _viewModes = {
    'details',
    'list',
    'extraLargeIcons',
    'largeIcons',
    'mediumIcons',
    'smallIcons',
    'tiles',
    'content',
  };

  const AppSettings({
    this.themeMode = 'system',
    this.showHiddenFiles = false,
    this.showFileExtensions = true,
    this.showThumbnails = true,
    this.defaultViewMode = 'details',
    this.newTabLocation = NewTabLocation.current,
    this.customNewTabPath,
    this.confirmRecycleDelete = true,
  });

  final String themeMode;
  final bool showHiddenFiles;
  final bool showFileExtensions;
  final bool showThumbnails;
  final String defaultViewMode;
  final NewTabLocation newTabLocation;
  final String? customNewTabPath;
  final bool confirmRecycleDelete;

  factory AppSettings.fromJson(Map<String, Object?> json) {
    return switch (schemaVersionOf(json)) {
      1 => _decodeV1(json),
      currentSchemaVersion => _decodeV2(json),
      final version => throw UnsupportedSettingsVersion(version),
    };
  }

  static int schemaVersionOf(Map<String, Object?> json) {
    final value = json['schemaVersion'];
    if (value == null) return 1;
    if (value is int && value > 0) return value;
    throw const FormatException('Invalid settings schemaVersion');
  }

  static AppSettings _decodeV1(Map<String, Object?> json) {
    return _decodeFlatJson(json);
  }

  static AppSettings _decodeV2(Map<String, Object?> json) {
    return _decodeFlatJson(json);
  }

  static AppSettings _decodeFlatJson(Map<String, Object?> json) {
    final rawTheme = json['themeMode'];
    final rawView = json['defaultViewMode'];
    final rawLocation = json['newTabLocation'];
    final rawCustomPath = json['customNewTabPath'];

    return AppSettings(
      themeMode: rawTheme is String && _themeModes.contains(rawTheme)
          ? rawTheme
          : 'system',
      showHiddenFiles: json['showHiddenFiles'] is bool
          ? json['showHiddenFiles']! as bool
          : false,
      showFileExtensions: json['showFileExtensions'] is bool
          ? json['showFileExtensions']! as bool
          : true,
      showThumbnails: json['showThumbnails'] is bool
          ? json['showThumbnails']! as bool
          : true,
      defaultViewMode: rawView is String && _viewModes.contains(rawView)
          ? rawView
          : 'details',
      newTabLocation: rawLocation is String
          ? NewTabLocation.values.asNameMap()[rawLocation] ??
                NewTabLocation.current
          : NewTabLocation.current,
      customNewTabPath:
          rawCustomPath is String && rawCustomPath.trim().isNotEmpty
          ? rawCustomPath
          : null,
      confirmRecycleDelete: json['confirmRecycleDelete'] is bool
          ? json['confirmRecycleDelete']! as bool
          : true,
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': currentSchemaVersion,
    'themeMode': themeMode,
    'showHiddenFiles': showHiddenFiles,
    'showFileExtensions': showFileExtensions,
    'showThumbnails': showThumbnails,
    'defaultViewMode': defaultViewMode,
    'newTabLocation': switch (newTabLocation) {
      NewTabLocation.current => 'current',
      NewTabLocation.home => 'home',
      NewTabLocation.custom => 'custom',
    },
    'customNewTabPath': customNewTabPath,
    'confirmRecycleDelete': confirmRecycleDelete,
  };

  AppSettings copyWith({
    String? themeMode,
    bool? showHiddenFiles,
    bool? showFileExtensions,
    bool? showThumbnails,
    String? defaultViewMode,
    NewTabLocation? newTabLocation,
    String? customNewTabPath,
    bool? confirmRecycleDelete,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      showHiddenFiles: showHiddenFiles ?? this.showHiddenFiles,
      showFileExtensions: showFileExtensions ?? this.showFileExtensions,
      showThumbnails: showThumbnails ?? this.showThumbnails,
      defaultViewMode: defaultViewMode ?? this.defaultViewMode,
      newTabLocation: newTabLocation ?? this.newTabLocation,
      customNewTabPath: customNewTabPath ?? this.customNewTabPath,
      confirmRecycleDelete: confirmRecycleDelete ?? this.confirmRecycleDelete,
    );
  }
}
