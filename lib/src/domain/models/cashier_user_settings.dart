import 'package:sembast/sembast.dart';

import 'order_type.dart';
import '../../core/sound/pie_sound_service.dart';
import '../../data/local/local_database.dart';
import '../../data/local/local_stores.dart';

/// Cashier-specific user-level settings (NOT global facility settings).
///
/// These preferences belong strictly to the individual logged-in cashier user
/// on this terminal device (e.g. personal sound effects, tactile feedback,
/// preferred default order type, auto-open receipt on payment, and quick cash tender presets).
class CashierUserSettings {
  const CashierUserSettings({
    this.soundEffects = true,
    this.hapticFeedback = true,
    this.defaultOrderType = OrderType.takeaway,
    this.autoOpenReceipt = true,
    this.fastCheckoutAutoClear = true,
    this.quickTenderPresets = const [50, 100, 200, 500],
    this.compactGridView = false,
  });

  /// Whether auditory feedback is enabled for this user.
  final bool soundEffects;

  /// Whether haptic touch feedback is triggered for this user on supported devices.
  final bool hapticFeedback;

  /// Default order channel pre-selected when opening or resetting a cart.
  final OrderType defaultOrderType;

  /// Whether the thermal receipt preview modal opens automatically upon order checkout.
  final bool autoOpenReceipt;

  /// Whether the POS cart automatically resets to empty after completing payment.
  final bool fastCheckoutAutoClear;

  /// Preset quick tender cash amounts displayed during checkout dialog.
  final List<int> quickTenderPresets;

  /// Compact item grid layout density in the POS screen.
  final bool compactGridView;

  CashierUserSettings copyWith({
    bool? soundEffects,
    bool? hapticFeedback,
    OrderType? defaultOrderType,
    bool? autoOpenReceipt,
    bool? fastCheckoutAutoClear,
    List<int>? quickTenderPresets,
    bool? compactGridView,
  }) {
    return CashierUserSettings(
      soundEffects: soundEffects ?? this.soundEffects,
      hapticFeedback: hapticFeedback ?? this.hapticFeedback,
      defaultOrderType: defaultOrderType ?? this.defaultOrderType,
      autoOpenReceipt: autoOpenReceipt ?? this.autoOpenReceipt,
      fastCheckoutAutoClear: fastCheckoutAutoClear ?? this.fastCheckoutAutoClear,
      quickTenderPresets: quickTenderPresets ?? this.quickTenderPresets,
      compactGridView: compactGridView ?? this.compactGridView,
    );
  }

  Map<String, Object?> toRecord() {
    return {
      'soundEffects': soundEffects,
      'hapticFeedback': hapticFeedback,
      'defaultOrderType': defaultOrderType.name,
      'autoOpenReceipt': autoOpenReceipt,
      'fastCheckoutAutoClear': fastCheckoutAutoClear,
      'quickTenderPresets': quickTenderPresets,
      'compactGridView': compactGridView,
    };
  }

  factory CashierUserSettings.fromRecord(Map<String, Object?>? map) {
    if (map == null) return const CashierUserSettings();
    final orderTypeName = map['defaultOrderType'] as String?;
    final orderType = OrderType.values.firstWhere(
      (e) => e.name == orderTypeName,
      orElse: () => OrderType.takeaway,
    );
    final presetsRaw = map['quickTenderPresets'];
    List<int> presets = const [50, 100, 200, 500];
    if (presetsRaw is List) {
      presets = presetsRaw.whereType<num>().map((e) => e.toInt()).toList();
      if (presets.isEmpty) presets = const [50, 100, 200, 500];
    }
    return CashierUserSettings(
      soundEffects: map['soundEffects'] as bool? ?? true,
      hapticFeedback: map['hapticFeedback'] as bool? ?? true,
      defaultOrderType: orderType,
      autoOpenReceipt: map['autoOpenReceipt'] as bool? ?? true,
      fastCheckoutAutoClear: map['fastCheckoutAutoClear'] as bool? ?? true,
      quickTenderPresets: presets,
      compactGridView: map['compactGridView'] as bool? ?? false,
    );
  }

  static String storageKey(String? uid) => 'cashier_user_settings_${uid != null && uid.isNotEmpty ? uid : 'default'}';

  /// Loads the persisted cashier user settings from the local database config store.
  static Future<CashierUserSettings> load(LocalDatabase? db, String? uid) async {
    if (db == null) return const CashierUserSettings();
    try {
      final key = storageKey(uid);
      final record = await LocalStores.config.record(key).get(db.db);
      final settings = CashierUserSettings.fromRecord(record);
      PieSoundService.instance.enabled = settings.soundEffects;
      return settings;
    } catch (_) {
      return const CashierUserSettings();
    }
  }

  /// Persists cashier user settings to the local database config store.
  static Future<void> save(LocalDatabase? db, String? uid, CashierUserSettings settings) async {
    PieSoundService.instance.enabled = settings.soundEffects;
    if (db == null) return;
    try {
      final key = storageKey(uid);
      await LocalStores.config.record(key).put(db.db, settings.toRecord());
    } catch (_) {}
  }
}
