# Windows Flutter Plugin Junction Workaround

## Background

`window_manager` is a Windows Flutter plugin. Flutter normally creates real
symbolic links under `windows/flutter/ephemeral/.plugin_symlinks/` for native
plugins. On Windows, creating those symbolic links requires Developer Mode or
an elevated terminal.

This project has verified that Windows directory junctions (`mklink /J`) work
for the generated CMake plugin paths and avoid that permission requirement.

This is a local development workaround, not a Flutter-supported replacement
for symbolic links. Keep Developer Mode as the preferred option when it is
available.

## Automated Repair

The project uses the development dependency
[`win_plugin_link_repair`](https://pub.dev/packages/win_plugin_link_repair).
From the project root, run:

```powershell
dart run win_plugin_link_repair --dry-run
dart run win_plugin_link_repair
flutter build windows --no-pub
```

The repair command reads `.flutter-plugins-dependencies` and replaces each
Windows plugin entry in `windows/flutter/ephemeral/.plugin_symlinks/` with a
directory junction.

Use `--no-pub` for the following build so Flutter does not refresh the plugin
links before CMake runs.

## Manual Repair

If the repair command is unavailable, recreate the two current Windows plugin
links from the project root:

```powershell
cmd /c rmdir "windows\flutter\ephemeral\.plugin_symlinks\screen_retriever_windows"
cmd /c mklink /J "windows\flutter\ephemeral\.plugin_symlinks\screen_retriever_windows" "C:\Users\lyjia\AppData\Local\Pub\Cache\hosted\pub.dev\screen_retriever_windows-0.2.2"

cmd /c rmdir "windows\flutter\ephemeral\.plugin_symlinks\window_manager"
cmd /c mklink /J "windows\flutter\ephemeral\.plugin_symlinks\window_manager" "C:\Users\lyjia\AppData\Local\Pub\Cache\hosted\pub.dev\window_manager-0.5.2"
```

Verify the results:

```powershell
Get-ChildItem windows\flutter\ephemeral\.plugin_symlinks |
  Select-Object Name, LinkType, Target
```

Both entries should report `LinkType` as `Junction`.

## When To Re-run

Run the repair again after any command that refreshes Flutter plugin metadata,
including `flutter pub get`, changing `pubspec.yaml`, changing dependency
versions, or deleting `windows/flutter/ephemeral/`. Do not commit the generated
`ephemeral` directory or its junctions.

The manual paths above are version-specific. When package versions change, use
the automated repair command or read `.flutter-plugins-dependencies` rather
than reusing those paths unchanged.
