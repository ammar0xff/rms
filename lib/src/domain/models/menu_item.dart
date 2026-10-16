/// One priced choice inside a group (شيدر +15).
class ModifierOption {
  const ModifierOption({
    required this.id,
    required this.name,
    this.deltaPrice = 0,
  });

  final String id;
  final String name;
  final double deltaPrice;

  Map<String, Object?> toRecord() => {
        'id': id,
        'name': name,
        'deltaPrice': deltaPrice,
      };

  static ModifierOption fromRecord(Map<String, Object?> record) =>
      ModifierOption(
        id: record['id'] as String,
        name: record['name'] as String,
        deltaPrice: (record['deltaPrice'] as num?)?.toDouble() ?? 0,
      );
}

/// One customization group on an item (الحجم single-required, إضافات
/// multi-optional). Empty groups list means no customization.
class ModifierGroup {
  const ModifierGroup({
    required this.id,
    required this.name,
    this.required = false,
    this.multi = false,
    this.options = const [],
  });

  final String id;
  final String name;
  final bool required;
  final bool multi;
  final List<ModifierOption> options;

  Map<String, Object?> toRecord() => {
        'id': id,
        'name': name,
        'required': required,
        'multi': multi,
        'options': options.map((o) => o.toRecord()).toList(),
      };

  static ModifierGroup fromRecord(Map<String, Object?> record) =>
      ModifierGroup(
        id: record['id'] as String,
        name: record['name'] as String,
        required: record['required'] as bool? ?? false,
        multi: record['multi'] as bool? ?? false,
        options: ((record['options'] as List?) ?? [])
            .map((e) => ModifierOption.fromRecord(
                Map<String, Object?>.from(e as Map)))
            .toList(),
      );
}

class MenuItemModel {
  MenuItemModel({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.station,
    this.available = true,
    this.lastModifiedAt,
    this.syncStatus = 'synced',
    this.modifierGroups = const [],
  });

  final String id;
  final String name;
  final String category;
  final double price;
  final String station;
  final bool available;
  final DateTime? lastModifiedAt;
  final String syncStatus;
  final List<ModifierGroup> modifierGroups;

  double get priceSnapshot => price;

  Map<String, Object?> toRecord() => {
        'id': id,
        'name': name,
        'category': category,
        'price': price,
        'station': station,
        'available': available,
        if (lastModifiedAt != null)
          'lastModifiedAt': lastModifiedAt!.toIso8601String(),
        'syncStatus': syncStatus,
        if (modifierGroups.isNotEmpty)
          'modifierGroups':
              modifierGroups.map((g) => g.toRecord()).toList(),
      };

  static MenuItemModel fromRecord(Map<String, Object?> record) => MenuItemModel(
        id: record['id'] as String,
        name: record['name'] as String,
        category: record['category'] as String,
        price: (record['price'] as num).toDouble(),
        station: record['station'] as String,
        available: record['available'] as bool? ?? true,
        lastModifiedAt: record['lastModifiedAt'] == null
            ? null
            : DateTime.parse(record['lastModifiedAt'] as String),
        syncStatus: record['syncStatus'] as String? ?? 'synced',
        modifierGroups: ((record['modifierGroups'] as List?) ?? [])
            .map((e) => ModifierGroup.fromRecord(
                Map<String, Object?>.from(e as Map)))
            .toList(),
      );

  MenuItemModel copyWith({
    String? id,
    String? name,
    String? category,
    double? price,
    String? station,
    bool? available,
    DateTime? lastModifiedAt,
    String? syncStatus,
    List<ModifierGroup>? modifierGroups,
  }) =>
      MenuItemModel(
        id: id ?? this.id,
        name: name ?? this.name,
        category: category ?? this.category,
        price: price ?? this.price,
        station: station ?? this.station,
        available: available ?? this.available,
        lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
        syncStatus: syncStatus ?? this.syncStatus,
        modifierGroups: modifierGroups ?? this.modifierGroups,
      );
}
