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
  });

  final String id;
  final String name;
  final String category;
  final double price;
  final String station;
  final bool available;
  final DateTime? lastModifiedAt;
  final String syncStatus;

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
      );
}
