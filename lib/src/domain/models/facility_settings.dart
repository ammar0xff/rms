/// Terminal facility profile: printed names, tax identity, rates, and
/// printer preferences. Local-first single record (id 'facility'); a future
/// push-to-all would sync it like release manifests do.
class FacilitySettings {
  const FacilitySettings({
    this.nameAr = '',
    this.nameEn = '',
    this.receiptName = '',
    this.taxId = '',
    this.commercialRegister = '',
    this.vatRate = 0.14,
    this.serviceRate = 0.12,
    this.receiptFooter = '',
    this.themePreset = 'amber',
    this.printerCodepage = 'UTF-8',
    this.currency = 'ج.م',
    this.autoAssignDelivery = true,
    this.soundEffectsEnabled = true,
    this.activeBranchId = 'BR-01',
    this.activeBranchName = 'بوابة الشمال',
    this.simulateOffline = false,
  });

  final String nameAr;
  final String nameEn;

  /// Short receipt header (≤24 chars on thermal paper).
  final String receiptName;
  final String taxId;
  final String commercialRegister;
  final double vatRate;
  final double serviceRate;
  final String receiptFooter;
  final String themePreset;
  final String printerCodepage;
  final String currency;

  /// Operational flags: auto-dispatch delivery jobs to drivers, sound FX, branch
  final bool autoAssignDelivery;
  final bool soundEffectsEnabled;
  final String activeBranchId;
  final String activeBranchName;
  final bool simulateOffline;

  FacilitySettings copyWith({
    String? nameAr,
    String? nameEn,
    String? receiptName,
    String? taxId,
    String? commercialRegister,
    double? vatRate,
    double? serviceRate,
    String? receiptFooter,
    String? themePreset,
    String? printerCodepage,
    String? currency,
    bool? autoAssignDelivery,
    bool? soundEffectsEnabled,
    String? activeBranchId,
    String? activeBranchName,
    bool? simulateOffline,
  }) =>
      FacilitySettings(
        nameAr: nameAr ?? this.nameAr,
        nameEn: nameEn ?? this.nameEn,
        receiptName: receiptName ?? this.receiptName,
        taxId: taxId ?? this.taxId,
        commercialRegister: commercialRegister ?? this.commercialRegister,
        vatRate: vatRate ?? this.vatRate,
        serviceRate: serviceRate ?? this.serviceRate,
        receiptFooter: receiptFooter ?? this.receiptFooter,
        themePreset: themePreset ?? this.themePreset,
        printerCodepage: printerCodepage ?? this.printerCodepage,
        currency: currency ?? this.currency,
        autoAssignDelivery: autoAssignDelivery ?? this.autoAssignDelivery,
        soundEffectsEnabled: soundEffectsEnabled ?? this.soundEffectsEnabled,
        activeBranchId: activeBranchId ?? this.activeBranchId,
        activeBranchName: activeBranchName ?? this.activeBranchName,
        simulateOffline: simulateOffline ?? this.simulateOffline,
      );

  Map<String, Object?> toRecord() => {
        'nameAr': nameAr,
        'nameEn': nameEn,
        'receiptName': receiptName,
        'taxId': taxId,
        'commercialRegister': commercialRegister,
        'vatRate': vatRate,
        'serviceRate': serviceRate,
        'receiptFooter': receiptFooter,
        'themePreset': themePreset,
        'printerCodepage': printerCodepage,
        'currency': currency,
        'autoAssignDelivery': autoAssignDelivery,
        'soundEffectsEnabled': soundEffectsEnabled,
        'activeBranchId': activeBranchId,
        'activeBranchName': activeBranchName,
        'simulateOffline': simulateOffline,
      };

  static FacilitySettings fromRecord(Map<String, Object?> record) =>
      FacilitySettings(
        nameAr: record['nameAr'] as String? ?? '',
        nameEn: record['nameEn'] as String? ?? '',
        receiptName: record['receiptName'] as String? ?? '',
        taxId: record['taxId'] as String? ?? '',
        commercialRegister: record['commercialRegister'] as String? ?? '',
        vatRate: (record['vatRate'] as num?)?.toDouble() ?? 0.14,
        serviceRate: (record['serviceRate'] as num?)?.toDouble() ?? 0.12,
        receiptFooter: record['receiptFooter'] as String? ?? '',
        themePreset: record['themePreset'] as String? ?? 'amber',
        printerCodepage: record['printerCodepage'] as String? ?? 'UTF-8',
        currency: record['currency'] as String? ?? 'ج.م',
        autoAssignDelivery: record['autoAssignDelivery'] as bool? ?? true,
        soundEffectsEnabled: record['soundEffectsEnabled'] as bool? ?? true,
        activeBranchId: record['activeBranchId'] as String? ?? 'BR-01',
        activeBranchName: record['activeBranchName'] as String? ?? 'بوابة الشمال',
        simulateOffline: record['simulateOffline'] as bool? ?? false,
      );
}
