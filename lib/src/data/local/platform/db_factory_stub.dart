import 'package:sembast/sembast_memory.dart';

/// Fallback opener for platforms that expose neither `dart:io` nor JS interop.
/// Keeps the app runnable (in-memory) instead of crashing at startup.
Future<Database> openPlatformDatabase() =>
    databaseFactoryMemory.openDatabase('rms_local');
