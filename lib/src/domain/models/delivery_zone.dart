/// Region-based delivery zone with static delivery fees configured exclusively by the branch manager.
class DeliveryZone {
  const DeliveryZone({
    required this.id,
    required this.name,
    required this.fee,
    this.minOrderAmount = 0.0,
    this.estimatedMinutes = 30,
    this.active = true,
  });

  final String id;
  final String name;
  final double fee;
  final double minOrderAmount;
  final int estimatedMinutes;
  final bool active;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'fee': fee,
        'minOrderAmount': minOrderAmount,
        'estimatedMinutes': estimatedMinutes,
        'active': active,
      };

  Map<String, dynamic> toRecord() => toMap();

  factory DeliveryZone.fromMap(Map<String, dynamic> map) {
    return DeliveryZone(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      fee: (map['fee'] as num?)?.toDouble() ?? 0.0,
      minOrderAmount: (map['minOrderAmount'] as num?)?.toDouble() ?? 0.0,
      estimatedMinutes: (map['estimatedMinutes'] as num?)?.toInt() ?? 30,
      active: map['active'] as bool? ?? true,
    );
  }

  factory DeliveryZone.fromRecord(Map<String, dynamic> record) =>
      DeliveryZone.fromMap(record);

  DeliveryZone copyWith({
    String? id,
    String? name,
    double? fee,
    double? minOrderAmount,
    int? estimatedMinutes,
    bool? active,
  }) {
    return DeliveryZone(
      id: id ?? this.id,
      name: name ?? this.name,
      fee: fee ?? this.fee,
      minOrderAmount: minOrderAmount ?? this.minOrderAmount,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      active: active ?? this.active,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeliveryZone &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
