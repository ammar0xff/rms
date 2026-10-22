import 'dart:ui';
import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/core/di/app_bootstrap.dart';
import 'src/core/logging/app_logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    AppLogger.error('Flutter framework error: ${details.exceptionAsString()}', details.exception, details.stack);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.error('Uncaught platform error: $error', error, stack);
    return true;
  };

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: const Color(0xFF0F1117),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(20),
          constraints: const BoxConstraints(maxWidth: 480),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2028),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 40),
                const SizedBox(height: 12),
                const Text(
                  'حدث خطأ في عرض الشاشة',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  details.exceptionAsString(),
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  };

  final services = await bootstrapApp();
  runApp(RmsApp(services: services));
}

