enum NewTabLocation { current, home, custom }

class AppSettings {
  static const currentSchemaVersion = 1;

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
    this.schemaVersion = currentSchemaVersion,
    this.themeMode = 'system',
    this.showHiddenFiles = false,
    this.showFileExtensions = true,
    this.showThumbnails = true,
    this.defaultViewMode = 'details',
    this.newTabLocation = NewTabLocation.current,
    this.customNewTabPath,
    this.confirmRecycleDelete = true,
    this.extraFields = const {},
  });

  final int schemaVersion;
  final String themeMode;
  final bool showHiddenFiles;
  final bool showFileExtensions;
  final bool showThumbnails;
  final String defaultViewMode;
  final NewTabLocation newTabLocation;
  final String? customNewTabPath;
  final bool confirmRecycleDelete;
  final Map<String, Object?> extraFields;

  factory AppSettings.fromJson(Map<String, Object?> json) {
    final extras = Map<String, Object?>.from(json)
      ..remove('schemaVersion')
      ..remove('themeMode')
      ..remove('showHiddenFiles')
      ..remove('showFileExtensions')
      ..remove('showThumbnails')
      ..remove('defaultViewMode')
      ..remove('newTabLocation')
      ..remove('customNewTabPath')
      ..remove('confirmRecycleDelete');

    final rawTheme = json['themeMode'];
    final rawView = json['defaultViewMode'];
    final rawLocation = json['newTabLocation'];
    final rawCustomPath = json['customNewTabPath'];

    return AppSettings(
      schemaVersion: switch (json['schemaVersion']) {
        final int value when value > 0 => value,
        _ => currentSchemaVersion,
      },
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
      extraFields: extras,
    );
  }

  Map<String, Object?> toJson() => {
    ...extraFields,
    'schemaVersion': schemaVersion,
    'themeMode': themeMode,
    'showHiddenFiles': showHiddenFiles,
    'showFileExtensions': showFileExtensions,
    'showThumbnails': showThumbnails,
    'defaultViewMode': defaultViewMode,
    'newTabLocation': newTabLocation.name,
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
      schemaVersion: schemaVersion,
      themeMode: themeMode ?? this.themeMode,
      showHiddenFiles: showHiddenFiles ?? this.showHiddenFiles,
      showFileExtensions: showFileExtensions ?? this.showFileExtensions,
      showThumbnails: showThumbnails ?? this.showThumbnails,
      defaultViewMode: defaultViewMode ?? this.defaultViewMode,
      newTabLocation: newTabLocation ?? this.newTabLocation,
      customNewTabPath: customNewTabPath ?? this.customNewTabPath,
      confirmRecycleDelete: confirmRecycleDelete ?? this.confirmRecycleDelete,
      extraFields: extraFields,
    );
  }
}
