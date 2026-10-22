import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/domain/models/facility_settings.dart';
import 'package:rms/src/domain/models/order.dart';
import 'package:rms/src/domain/models/order_type.dart';
import 'package:rms/src/domain/services/receipt_print_service.dart';

void main() {
  group('ReceiptPrintService', () {
    test('builds thermal receipt HTML with all required invoice and tax details', () {
      final now = DateTime(2026, 10, 22, 14, 30);
      final order = Order(
        localId: 'order-123',
        provisionalOrderNumber: 'P-1001',
        canonicalOrderNumber: '1001',
        createdOffline: false,
        createdAt: now,
        orderType: OrderType.takeaway,
        taxAmount: 14.0,
        serviceAmount: 0.0,
        discountAmount: 0.0,
        items: const [
          OrderItem(
            productId: 'pizza-1',
            name: 'بيتزا سوبريم',
            unitPrice: 100.0,
            quantity: 2,
            modifiers: ['إكسترا جبنة'],
            note: 'مقرمشة',
          ),
          OrderItem(
            productId: 'coke-1',
            name: 'كولا كانز',
            unitPrice: 20.0,
            quantity: 1,
          ),
        ],
      );

      const facility = FacilitySettings(
        nameAr: 'مطعم باي الإيطالي',
        receiptName: 'PIE Pizza & Pasta',
        taxId: '345-678-901',
        activeBranchName: 'المعادي',
        receiptFooter: 'شكراً لزيارتكم! نسعد بخدمتكم دائماً',
      );

      final html = ReceiptPrintService.buildReceiptHtml(
        order: order,
        facility: facility,
        paymentMethod: 'نقدي',
        paidAmount: 250.0,
        changeDue: 16.0,
      );

      expect(html, contains('PIE Pizza & Pasta'));
      expect(html, contains('المعادي'));
      expect(html, contains('345-678-901'));
      expect(html, contains('#1001'));
      expect(html, contains('تيك أواي'));
      expect(html, contains('بيتزا سوبريم'));
      expect(html, contains('200.00'));
      expect(html, contains('كولا كانز'));
      expect(html, contains('إكسترا جبنة'));
      expect(html, contains('مقرمشة'));
      expect(html, contains('234.00')); // subtotal(220) + tax(14)
      expect(html, contains('شكراً لزيارتكم'));
    });

    test('printOrder handles execution gracefully without throwing', () async {
      final order = Order(
        localId: 'order-test',
        provisionalOrderNumber: 'P-999',
        createdOffline: true,
        createdAt: DateTime.now(),
        items: const [
          OrderItem(
            productId: 'burger-1',
            name: 'برجر سنجل',
            unitPrice: 75.0,
            quantity: 1,
          ),
        ],
      );

      final result = await ReceiptPrintService.printOrder(order: order);
      expect(result, isNotNull);
    });
  });
}
