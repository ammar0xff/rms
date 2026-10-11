import 'package:sembast/sembast.dart';

/// Named collections within the local database.
abstract final class LocalStores {
  static final StoreRef<String, Map<String, Object?>> orders =
      stringMapStoreFactory.store('orders');

  static final StoreRef<String, Map<String, Object?>> outbox =
      stringMapStoreFactory.store('outbox');
}
