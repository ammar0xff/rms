import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/local_stores.dart';
import 'package:rms/src/data/local/outbox/outbox_store.dart';
import 'package:rms/src/data/repositories/local_inventory_repository.dart';
import 'package:rms/src/data/repositories/local_order_repository.dart';
import 'package:rms/src/domain/models/inventory_item.dart';
import 'package:rms/src/domain/models/menu_item.dart';
import 'package:rms/src/domain/models/order.dart';
import 'package:rms/src/domain/models/order_draft.dart';
import 'package:rms/src/domain/models/stock_movement.dart';
import 'package:sembast/sembast.dart';

int _testDbSeq = 0;

void main() {
  group('Recipe / BOM Inventory Depletion on POS Checkout', () {
    late LocalDatabase db;
    late OutboxStore outbox;
    late LocalInventoryRepository inventoryRepo;
    late LocalOrderRepository orderRepo;

    setUp(() async {
      db = await LocalDatabase.memory('recipe_depletion_test_${_testDbSeq++}');
      outbox = OutboxStore(db);
      inventoryRepo = LocalInventoryRepository(db, outbox: outbox);
      orderRepo = LocalOrderRepository(
        db,
        outbox: outbox,
        inventory: inventoryRepo,
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('automatically depletes raw ingredients when an order is created', () async {
      // 1. Prime raw ingredients in inventory:
      // Flour: 10.0 kg
      // Mozzarella: 5.0 kg
      final flour = InventoryItemModel(
        id: 'inv-flour',
        name: 'دقيق فاخر',
        unit: 'كجم',
        onHand: 10.0,
        reorderAt: 2.0,
      );
      final cheese = InventoryItemModel(
        id: 'inv-cheese',
        name: 'جبنة موزاريلا',
        unit: 'كجم',
        onHand: 5.0,
        reorderAt: 1.0,
      );
      await inventoryRepo.cacheItems([flour, cheese]);

      // 2. Prime menu item with recipe:
      // Margherita Pizza uses 0.3 kg flour and 0.2 kg cheese
      final pizza = MenuItemModel(
        id: 'item-pizza',
        name: 'بيتزا مارجريتا',
        category: 'بيتزا',
        price: 120.0,
        station: 'pizza_oven',
        recipe: const [
          RecipeIngredient(inventoryItemId: 'inv-flour', quantity: 0.3, unit: 'كجم'),
          RecipeIngredient(inventoryItemId: 'inv-cheese', quantity: 0.2, unit: 'كجم'),
        ],
      );
      await LocalStores.menu.record('item-pizza').put(db.db, pizza.toRecord());

      // 3. Customer orders 2 pizzas
      final draft = OrderDraft(
        items: const [
          OrderItem(
            productId: 'item-pizza',
            name: 'بيتزا مارجريتا',
            unitPrice: 120.0,
            quantity: 2,
            station: 'pizza_oven',
          ),
        ],
      );

      final order = await orderRepo.createOrder(draft);
      expect(order.localId, isNotEmpty);

      // 4. Verify inventory balances decreased appropriately:
      // Flour: 10.0 - (0.3 * 2) = 9.4 kg
      // Cheese: 5.0 - (0.2 * 2) = 4.6 kg
      final updatedItems = await inventoryRepo.listItems();
      final updatedFlour = updatedItems.firstWhere((i) => i.id == 'inv-flour');
      final updatedCheese = updatedItems.firstWhere((i) => i.id == 'inv-cheese');

      expect(updatedFlour.onHand, closeTo(9.4, 0.001));
      expect(updatedCheese.onHand, closeTo(4.6, 0.001));

      // 5. Verify stock movements were recorded with reason: sale and reference to the order
      final movements = await inventoryRepo.listMovements();
      expect(movements.length, 2);

      final flourMove = movements.firstWhere((m) => m.itemId == 'inv-flour');
      expect(flourMove.delta, closeTo(-0.6, 0.001));
      expect(flourMove.reason, StockMovementReason.sale);
      expect(flourMove.reference, 'order:${order.localId}');

      final cheeseMove = movements.firstWhere((m) => m.itemId == 'inv-cheese');
      expect(cheeseMove.delta, closeTo(-0.4, 0.001));
      expect(cheeseMove.reason, StockMovementReason.sale);
      expect(cheeseMove.reference, 'order:${order.localId}');

      // 6. Verify outbox contains pending sync entries for the stock movements
      final pendingEntries = await outbox.all();
      final movementEntries = pendingEntries.where((e) => e.entityType == 'stockMovement').toList();
      expect(movementEntries.length, 2);
    });

    test('ignores items with no recipe gracefully without failing order creation', () async {
      // Water bottle with no recipe
      final water = MenuItemModel(
        id: 'item-water',
        name: 'مياه معدنية',
        category: 'مشروبات',
        price: 10.0,
        station: 'beverages',
        recipe: const [],
      );
      await LocalStores.menu.record('item-water').put(db.db, water.toRecord());

      final draft = OrderDraft(
        items: const [
          OrderItem(
            productId: 'item-water',
            name: 'مياه معدنية',
            unitPrice: 10.0,
            quantity: 5,
          ),
        ],
      );

      final order = await orderRepo.createOrder(draft);
      expect(order.localId, isNotEmpty);

      final movements = await inventoryRepo.listMovements();
      expect(movements, isEmpty);
    });
  });
}
