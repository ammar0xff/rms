enum OfflineCapability {
  fullOffline,
  cachedRead,
  localRecording,
  queueable,
  conditional,
  restricted,
  onlineOnly,
}

class OfflinePolicy {
  const OfflinePolicy._();

  static const Map<String, OfflineCapability> byFeature = {
    'pos': OfflineCapability.fullOffline,
    'menu': OfflineCapability.cachedRead,
    'customers': OfflineCapability.localRecording,
    'cashPayments': OfflineCapability.localRecording,
    'externalCardPayments': OfflineCapability.conditional,
    'kitchen': OfflineCapability.queueable,
    'printing': OfflineCapability.conditional,
    'deliveryAssignment': OfflineCapability.restricted,
    'driverUpdates': OfflineCapability.queueable,
    'customerCollection': OfflineCapability.queueable,
    'driverSettlement': OfflineCapability.restricted,
    'inventory': OfflineCapability.conditional,
    'purchasing': OfflineCapability.queueable,
    'suppliers': OfflineCapability.localRecording,
    'reports': OfflineCapability.cachedRead,
    'userManagement': OfflineCapability.onlineOnly,
    'refunds': OfflineCapability.restricted,
    'configuration': OfflineCapability.cachedRead,
  };
}
