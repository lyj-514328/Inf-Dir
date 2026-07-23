import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'state/app_state.dart';
import 'widgets/app_shell.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
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
