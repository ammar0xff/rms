import 'package:flutter/foundation.dart';

enum TicketState { queued, preparing, ready, completed }

@immutable
class KitchenTicketModel {
  const KitchenTicketModel({
    required this.id,
    required this.orderRef,
    required this.station,
    required this.items,
    required this.state,
    required this.createdAt,
    this.queuedAt,
    this.preparingAt,
    this.readyAt,
    this.completedAt,
    this.provisional = false,
    this.lastModifiedAt,
    this.syncStatus = 'synced',
  });

  final String id;
  final String orderRef;
  final String station;
  final List<String> items;
  final TicketState state;
  final DateTime createdAt;
  final DateTime? queuedAt;
  final DateTime? preparingAt;
  final DateTime? readyAt;
  final DateTime? completedAt;
  final bool provisional;
  final DateTime? lastModifiedAt;
  final String syncStatus;

  int get ageMinutes {
    final now = DateTime.now();
    return now.difference(createdAt).inMinutes;
  }

  Map<String, Object?> toRecord() => {
        'id': id,
        'orderRef': orderRef,
        'station': station,
        'items': items,
        'state': state.name,
        'createdAt': createdAt.toIso8601String(),
        if (queuedAt != null) 'queuedAt': queuedAt!.toIso8601String(),
        if (preparingAt != null) 'preparingAt': preparingAt!.toIso8601String(),
        if (readyAt != null) 'readyAt': readyAt!.toIso8601String(),
        if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
        'provisional': provisional,
        if (lastModifiedAt != null)
          'lastModifiedAt': lastModifiedAt!.toIso8601String(),
        'syncStatus': syncStatus,
      };

  static KitchenTicketModel fromRecord(Map<String, Object?> record) {
    final items = record['items'];
    return KitchenTicketModel(
      id: record['id'] as String,
      orderRef: record['orderRef'] as String,
      station: record['station'] as String,
      items: (items as List).cast<String>(),
      state: TicketState.values.byName(record['state'] as String),
      createdAt: DateTime.parse(record['createdAt'] as String),
      queuedAt: record['queuedAt'] == null
          ? null
          : DateTime.parse(record['queuedAt'] as String),
      preparingAt: record['preparingAt'] == null
          ? null
          : DateTime.parse(record['preparingAt'] as String),
      readyAt: record['readyAt'] == null
          ? null
          : DateTime.parse(record['readyAt'] as String),
      completedAt: record['completedAt'] == null
          ? null
          : DateTime.parse(record['completedAt'] as String),
      provisional: record['provisional'] as bool? ?? false,
      lastModifiedAt: record['lastModifiedAt'] == null
          ? null
          : DateTime.parse(record['lastModifiedAt'] as String),
      syncStatus: record['syncStatus'] as String? ?? 'synced',
    );
  }

  KitchenTicketModel copyWith({
    String? id,
    String? orderRef,
    String? station,
    List<String>? items,
    TicketState? state,
    DateTime? createdAt,
    DateTime? queuedAt,
    DateTime? preparingAt,
    DateTime? readyAt,
    DateTime? completedAt,
    bool? provisional,
    DateTime? lastModifiedAt,
    String? syncStatus,
  }) =>
      KitchenTicketModel(
        id: id ?? this.id,
        orderRef: orderRef ?? this.orderRef,
        station: station ?? this.station,
        items: items ?? this.items,
        state: state ?? this.state,
        createdAt: createdAt ?? this.createdAt,
        queuedAt: queuedAt ?? this.queuedAt,
        preparingAt: preparingAt ?? this.preparingAt,
        readyAt: readyAt ?? this.readyAt,
        completedAt: completedAt ?? this.completedAt,
        provisional: provisional ?? this.provisional,
        lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
        syncStatus: syncStatus ?? this.syncStatus,
      );
}
