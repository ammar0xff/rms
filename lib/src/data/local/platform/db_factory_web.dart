import 'package:sembast/sembast.dart';
import 'package:sembast_web/sembast_web.dart';

/// Flutter Web opener: persists to the browser's IndexedDB.
Future<Database> openPlatformDatabase() =>
    databaseFactoryWeb.openDatabase('rms_local');
