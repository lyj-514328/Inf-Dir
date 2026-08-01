import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/directory_repository.dart';
import 'state/app_state.dart';
import 'state/layout_state.dart';
import 'state/sidebar_controller.dart';
import 'widgets/app_shell.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        // Sidebar 与 PaneController 共用同一个 DirectoryRepository（§2.7）。
        Provider<DirectoryRepository>(
          create: (_) => DirectoryRepository(
            yieldFrame: () {
              final c = Completer<void>();
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => c.complete());
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
          create: (ctx) =>
              SidebarSyncController(repository: ctx.read<DirectoryRepository>()),
        ),
      ],
      child: const InfDirApp(),
    ),
  );
}

class InfDirApp extends StatelessWidget {
  const InfDirApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inf-Dir',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0078D4),
          brightness: Brightness.light,
        ),
        visualDensity: VisualDensity.compact,
        fontFamily: 'Segoe UI',
        dividerColor: const Color(0xFFD0D0D0),
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const AppShell(),
    );
  }
}
