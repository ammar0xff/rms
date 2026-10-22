import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/domain/models/cash_session.dart';
import 'package:rms/src/domain/models/delivery.dart';
import 'package:rms/src/domain/models/facility_settings.dart';
import 'package:rms/src/domain/models/kitchen_ticket.dart';
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

      expect(html, contains('PIE Pizza &amp; Pasta'));
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

    test('properly escapes dangerous HTML entities in receipt', () {
      final order = Order(
        localId: 'order-xss',
        provisionalOrderNumber: 'P-XSS',
        createdOffline: false,
        createdAt: DateTime.now(),
        items: const [
          OrderItem(
            productId: 'p-1',
            name: '<script>alert("xss")</script>',
            unitPrice: 50.0,
            quantity: 1,
            note: '<b>Bold Note</b>',
          ),
        ],
      );

      const facility = FacilitySettings(
        receiptName: 'Store <tag>',
      );

      final html = ReceiptPrintService.buildReceiptHtml(order: order, facility: facility);
      expect(html, isNot(contains('<script>alert')));
      expect(html, contains('&lt;script&gt;alert'));
      expect(html, contains('&lt;b&gt;Bold Note&lt;/b&gt;'));
      expect(html, contains('Store &lt;tag&gt;'));
    });

    test('builds thermal kitchen ticket HTML', () {
      final ticket = KitchenTicketModel(
        id: 'T-GR-01',
        orderRef: '1002',
        station: 'جريل',
        items: ['برجر دوبل × 2 (بدون بصل)', 'فرايز كريسبي'],
        state: TicketState.queued,
        createdAt: DateTime(2026, 10, 22, 15, 0),
        queuedAt: DateTime(2026, 10, 22, 15, 0),
      );

      const facility = FacilitySettings(
        receiptName: 'PIE Grill',
      );

      final html = ReceiptPrintService.buildKitchenTicketHtml(
        ticket: ticket,
        facility: facility,
      );

      expect(html, contains('بون مطبخ'));
      expect(html, contains('محطة: جريل'));
      expect(html, contains('طلب #1002'));
      expect(html, contains('برجر دوبل'));
      expect(html, contains('فرايز كريسبي'));
    });

    test('builds thermal Z-Report HTML with cash denominations and variance', () {
      final session = CashSession(
        id: 'sess-001',
        openedAt: DateTime(2026, 10, 22, 9, 0),
        openingFloat: 500.0,
        expectedCash: 2500.0,
        countedCash: 2550.0,
      );

      const facility = FacilitySettings(
        receiptName: 'PIE Restaurant',
        activeBranchName: 'مدينة نصر',
      );

      final html = ReceiptPrintService.buildZReportHtml(
        session: session,
        facility: facility,
        expectedCash: 2500.0,
        countedCash: 2550.0,
        variance: 50.0,
        counts: {200: 10, 100: 5, 50: 1},
        cashierName: 'أحمد الكاشير',
      );

      expect(html, contains('تقرير تقفيل الوردية اليومي (Z-Close)'));
      expect(html, contains('#sess-001'));
      expect(html, contains('مدينة نصر'));
      expect(html, contains('أحمد الكاشير'));
      expect(html, contains('500.00'));
      expect(html, contains('2500.00'));
      expect(html, contains('2550.00'));
      expect(html, contains('زيادة بالدرج: +50.00'));
      expect(html, contains('ورقة 200'));
      expect(html, contains('توقيع الكاشير'));
    });

    test('builds thermal delivery driver slip HTML', () {
      final delivery = DeliveryModel(
        id: 'del-01',
        orderRef: '1005',
        address: 'شارع 9 المعادي - عمارة 12 الدور 4',
        amount: 320.0,
        state: DeliveryState.assigned,
        createdAt: DateTime(2026, 10, 22, 14, 45),
      );

      final order = Order(
        localId: 'order-1005',
        provisionalOrderNumber: '1005',
        canonicalOrderNumber: '1005',
        createdOffline: false,
        createdAt: DateTime(2026, 10, 22, 14, 45),
        items: const [
          OrderItem(
            productId: 'p-1',
            name: 'بيتزا رانش',
            unitPrice: 160.0,
            quantity: 2,
          ),
        ],
      );

      const facility = FacilitySettings(
        receiptName: 'PIE Delivery',
      );

      final html = ReceiptPrintService.buildDeliverySlipHtml(
        delivery: delivery,
        facility: facility,
        order: order,
      );

      expect(html, contains('بون تسليم سائق الدليفري'));
      expect(html, contains('أوردر #1005'));
      expect(html, contains('شارع 9 المعادي'));
      expect(html, contains('المطلوب تحصيله كاش من العميل:'));
      expect(html, contains('320.00'));
      expect(html, contains('بيتزا رانش'));
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

