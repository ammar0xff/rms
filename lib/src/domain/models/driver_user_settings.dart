import 'package:sembast/sembast.dart';
import '../../core/sound/pie_sound_service.dart';
import '../../data/local/local_database.dart';
import '../../data/local/local_stores.dart';

/// Driver-specific user-level settings and personal preferences (NOT global facility settings).
///
/// These preferences belong strictly to the individual logged-in courier user
/// on this terminal device (e.g. vehicle type, default navigation style, sound effects,
/// haptic touch, speed limit alerts, and 3D map perspective).
class DriverUserSettings {
  const DriverUserSettings({
    this.vehicle = 'موتوسيكل 🛵',
    this.defaultNavigation = 'cockpit',
    this.soundEffects = true,
    this.hapticFeedback = true,
    this.mapPerspective3D = true,
    this.speedLimitWarning = true,
  });

  /// Selected vehicle mode (موتوسيكل 🛵, سكوتر 🛴, دراجة 🚲, سيارة 🚗).
  final String vehicle;

  /// Default navigation experience ('cockpit' for in-app 3D HUD, 'google_maps' for external).
  final String defaultNavigation;

  /// Whether auditory chime feedback is enabled for this courier.
  final bool soundEffects;

  /// Whether tactile vibration is triggered on actions for supported mobile devices.
  final bool hapticFeedback;

  /// Default 3D perspective tilt on map canvas.
  final bool mapPerspective3D;

  /// Whether speedometer triggers warning when exceeding speed threshold.
  final bool speedLimitWarning;

  DriverUserSettings copyWith({
    String? vehicle,
    String? defaultNavigation,
    bool? soundEffects,
    bool? hapticFeedback,
    bool? mapPerspective3D,
    bool? speedLimitWarning,
  }) {
    return DriverUserSettings(
      vehicle: vehicle ?? this.vehicle,
      defaultNavigation: defaultNavigation ?? this.defaultNavigation,
      soundEffects: soundEffects ?? this.soundEffects,
      hapticFeedback: hapticFeedback ?? this.hapticFeedback,
      mapPerspective3D: mapPerspective3D ?? this.mapPerspective3D,
      speedLimitWarning: speedLimitWarning ?? this.speedLimitWarning,
    );
  }

  Map<String, Object?> toRecord() {
    return {
      'vehicle': vehicle,
      'defaultNavigation': defaultNavigation,
      'soundEffects': soundEffects,
      'hapticFeedback': hapticFeedback,
      'mapPerspective3D': mapPerspective3D,
      'speedLimitWarning': speedLimitWarning,
    };
  }

  factory DriverUserSettings.fromRecord(Map<String, Object?>? map) {
    if (map == null) return const DriverUserSettings();
    return DriverUserSettings(
      vehicle: map['vehicle'] as String? ?? 'موتوسيكل 🛵',
      defaultNavigation: map['defaultNavigation'] as String? ?? 'cockpit',
      soundEffects: map['soundEffects'] as bool? ?? true,
      hapticFeedback: map['hapticFeedback'] as bool? ?? true,
      mapPerspective3D: map['mapPerspective3D'] as bool? ?? true,
      speedLimitWarning: map['speedLimitWarning'] as bool? ?? true,
    );
  }

  static String storageKey(String? uid) =>
      'driver_user_settings_${uid != null && uid.isNotEmpty ? uid : 'default'}';

  /// Loads preferences for [uid] from the Sembast config store.
  static Future<DriverUserSettings> load(LocalDatabase? db, String? uid) async {
    if (db == null) return const DriverUserSettings();
    try {
      final key = storageKey(uid);
      final record = await LocalStores.config.record(key).get(db.db);
      final settings = DriverUserSettings.fromRecord(record);
      PieSoundService.instance.enabled = settings.soundEffects;
      return settings;
    } catch (_) {
      return const DriverUserSettings();
    }
  }

  /// Persists preferences for [uid] into the Sembast config store.
  static Future<void> save(
    LocalDatabase? db,
    String? uid,
    DriverUserSettings settings,
  ) async {
    PieSoundService.instance.enabled = settings.soundEffects;
    if (db == null) return;
    try {
      final key = storageKey(uid);
      await LocalStores.config.record(key).put(db.db, settings.toRecord());
    } catch (_) {}
  }
}
