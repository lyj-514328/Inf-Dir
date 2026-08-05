import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'features/quick_view/quick_view_service.dart';
import 'services/directory_repository.dart';
import 'state/app_state.dart';
import 'state/layout_state.dart';
import 'state/sidebar_controller.dart';
import 'state/theme_controller.dart';
import 'widgets/app_shell.dart';
import 'widgets/app_theme.dart';

void main() {
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
              LayoutState(repository: ctx.read<DirectoryRepository>()),
        ),
        ChangeNotifierProvider(
          create: (ctx) => SidebarSyncController(
            repository: ctx.read<DirectoryRepository>(),
          ),
        ),
        ChangeNotifierProvider(create: (_) => ThemeController()),
        ChangeNotifierProvider(create: (_) => QuickViewService()),
      ],
      child: const InfDirApp(),
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
