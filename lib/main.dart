import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/core/di/app_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await bootstrapApp();
  runApp(RmsApp(services: services));
}
