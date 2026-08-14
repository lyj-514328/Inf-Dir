import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:toastification/toastification.dart';
import 'package:window_manager/window_manager.dart';
import 'features/quick_view/quick_view_service.dart';
import 'services/directory_repository.dart';
import 'services/undo_redo_service.dart';
import 'services/window_layout_store.dart';
import 'state/app_state.dart';
import 'state/layout_state.dart';
import 'state/sidebar_controller.dart';
import 'state/theme_controller.dart';
import 'widgets/app_shell.dart';
import 'widgets/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  // AppShell releases the native close after persisting the session.
  await windowManager.setPreventClose(true);

  // 无边框窗口：隐藏系统标题栏，保留 DWM 原生缩放边框（不用 setAsFrameless）。
  const windowOptions = WindowOptions(
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
    minimumSize: Size(960, 600),
    backgroundColor: Colors.transparent,
  );
  unawaited(
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    }),
  );

  runApp(
    MultiProvider(
      providers: [
        // Sidebar 与 PaneController 共用同一个 DirectoryRepository（§2.7）。
        Provider<DirectoryRepository>(
          create: (_) => DirectoryRepository(
            yieldFrame: () {
              final c = Completer<void>();
              WidgetsBinding.instance.addPostFrameCallback((_) => c.complete());
              return c.future;
            },
          ),
        ),
        ChangeNotifierProvider(
          create: (ctx) =>
              AppState(repository: ctx.read<DirectoryRepository>()),
        ),
        ChangeNotifierProvider(
          create: (ctx) =>
              LayoutState(
                repository: ctx.read<DirectoryRepository>(),
                layoutStore: WindowLayoutStore(),
              ),
        ),
        Provider<UndoRedoService>(
          create: (ctx) => UndoRedoService(
            appState: ctx.read<AppState>(),
            layoutState: ctx.read<LayoutState>(),
            history: ctx.read<AppState>().history,
          ),
        ),
        ChangeNotifierProvider(
          create: (ctx) => SidebarSyncController(
            repository: ctx.read<DirectoryRepository>(),
          ),
        ),
        ChangeNotifierProvider(create: (_) => ThemeController()),
        ChangeNotifierProvider(create: (_) => QuickViewService()),
      ],
      child: const ToastificationWrapper(child: InfDirApp()),
    ),
  );
}

class InfDirApp extends StatelessWidget {
  const InfDirApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    return MaterialApp(
      title: 'Inf-Dir',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: theme.mode,
      home: const AppShell(),
    );
  }
}
