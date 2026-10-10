import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'core/widgets/app_shell.dart';

class RmsApp extends StatelessWidget {
  const RmsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Restaurant Management System',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const AppShell(),
    );
  }
}
