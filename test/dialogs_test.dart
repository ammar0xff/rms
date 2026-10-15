import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/core/theme/app_theme.dart';
import 'package:rms/src/domain/models/inventory_item.dart';
import 'package:rms/src/domain/models/supplier.dart';
import 'package:rms/src/features/accounting/accounting_screen.dart';
import 'package:rms/src/features/customers/customers_screen.dart';
import 'package:rms/src/features/delivery/delivery_screen.dart';
import 'package:rms/src/features/inventory/inventory_screen.dart';
import 'package:rms/src/features/menu/menu_screen.dart';
import 'package:rms/src/features/pos/pos_screen.dart';
import 'package:rms/src/features/purchasing/purchasing_screen.dart';

/// Every dialog in the app, at phone and PC widths.
///
/// Dialogs are the one surface the screen sweeps never mount, and the one
/// most likely to overflow a 390px viewport. Each case opens the real
/// dialog through showDialog and proves its content renders; nothing here
/// taps save (that would write through a fake into throwing stubs).
Future<void> _pumpDialog(
  WidgetTester tester,
  Widget dialog,
  Size size,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => showDialog(
                context: context,
                builder: (_) => dialog,
              ),
            );
            return const SizedBox();
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _phone = Size(390, 844);
const _desktop = Size(1440, 900);

final _items = [
  InventoryItemModel(
    id: 'i1',
    name: 'دجاج متبل بكمية كبيرة للشواء',
    unit: 'كجم',
    onHand: 2,
    reorderAt: 10,
  ),
  InventoryItemModel(
    id: 'i2',
    name: 'أرز',
    unit: 'كجم',
    onHand: 50,
    reorderAt: 10,
  ),
];

final _supplier = SupplierModel(
  id: 's1',
  name: 'مورد اللحوم الرئيسي للفرع',
  payable: 1250.5,
);

void main() {
  group('dialogs at 390px', () {
    testWidgets('pos payment', (t) async {
      await _pumpDialog(t, const PosPaymentDialog(total: 240.75), _phone);
      expect(find.text('أكّد التحصيل'), findsOneWidget);
    });
    testWidgets('collection', (t) async {
      await _pumpDialog(t, const CollectionDialog(total: 240.75), _phone);
      expect(find.textContaining('240.75'), findsOneWidget);
    });
    testWidgets('close session', (t) async {
      await _pumpDialog(t, const CloseSessionDialog(expected: 740.75), _phone);
      expect(find.text('عِدّ واقفل الجلسة'), findsOneWidget);
    });
    testWidgets('menu item', (t) async {
      await _pumpDialog(t, const MenuItemDialog(), _phone);
      expect(find.text('صنف جديد'), findsOneWidget);
    });
    testWidgets('stock movement', (t) async {
      await _pumpDialog(t, StockMovementDialog(items: _items), _phone);
      expect(find.text('تسجيل حركة مخزون'), findsOneWidget);
    });
    testWidgets('stock count', (t) async {
      await _pumpDialog(t, StockCountDialog(items: _items), _phone);
      expect(find.text('جرد المخزون'), findsOneWidget);
    });
    testWidgets('customer', (t) async {
      await _pumpDialog(t, const CustomerDialog(), _phone);
      expect(find.text('عميل جديد'), findsOneWidget);
    });
    testWidgets('supplier', (t) async {
      await _pumpDialog(t, const SupplierDialog(), _phone);
      expect(find.text('إضافة مورد'), findsOneWidget);
    });
    testWidgets('pay supplier', (t) async {
      await _pumpDialog(
          t, PaySupplierDialog(supplier: _supplier), _phone);
      expect(find.textContaining('تسديد'), findsOneWidget);
    });
    testWidgets('purchase', (t) async {
      await _pumpDialog(
        t,
        PurchaseDialog(suppliers: [_supplier], items: _items),
        _phone,
      );
      expect(find.text('أمر شراء جديد'), findsOneWidget);
    });
  });

  group('dialogs at 1440px', () {
    testWidgets('pos payment', (t) async {
      await _pumpDialog(t, const PosPaymentDialog(total: 240.75), _desktop);
      expect(find.text('أكّد التحصيل'), findsOneWidget);
    });
    testWidgets('collection', (t) async {
      await _pumpDialog(t, const CollectionDialog(total: 240.75), _desktop);
      expect(find.textContaining('240.75'), findsOneWidget);
    });
    testWidgets('close session', (t) async {
      await _pumpDialog(
          t, const CloseSessionDialog(expected: 740.75), _desktop);
      expect(find.text('عِدّ واقفل الجلسة'), findsOneWidget);
    });
    testWidgets('menu item', (t) async {
      await _pumpDialog(t, const MenuItemDialog(), _desktop);
      expect(find.text('صنف جديد'), findsOneWidget);
    });
    testWidgets('stock movement', (t) async {
      await _pumpDialog(t, StockMovementDialog(items: _items), _desktop);
      expect(find.text('تسجيل حركة مخزون'), findsOneWidget);
    });
    testWidgets('stock count', (t) async {
      await _pumpDialog(t, StockCountDialog(items: _items), _desktop);
      expect(find.text('جرد المخزون'), findsOneWidget);
    });
    testWidgets('customer', (t) async {
      await _pumpDialog(t, const CustomerDialog(), _desktop);
      expect(find.text('عميل جديد'), findsOneWidget);
    });
    testWidgets('supplier', (t) async {
      await _pumpDialog(t, const SupplierDialog(), _desktop);
      expect(find.text('إضافة مورد'), findsOneWidget);
    });
    testWidgets('pay supplier', (t) async {
      await _pumpDialog(
          t, PaySupplierDialog(supplier: _supplier), _desktop);
      expect(find.textContaining('تسديد'), findsOneWidget);
    });
    testWidgets('purchase', (t) async {
      await _pumpDialog(
        t,
        PurchaseDialog(suppliers: [_supplier], items: _items),
        _desktop,
      );
      expect(find.text('أمر شراء جديد'), findsOneWidget);
    });
  });
}
