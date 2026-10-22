import 'package:flutter/foundation.dart';
import '../../core/logging/app_logger.dart';
import '../../data/services/print_service.dart';
import '../models/facility_settings.dart';
import '../models/order.dart';
import '../models/order_type.dart';
import 'receipt_printer/receipt_printer.dart';

/// Cross-platform receipt and invoice printing service.
///
/// Supports:
/// - Instant browser printing dialog for thermal receipts (80mm/58mm standard roll)
/// - Background network ESC/POS thermal printer queues (on native platforms)
/// - Clean Arabic RTL layout with tax compliance details
class ReceiptPrintService {
  ReceiptPrintService._();

  static final ReceiptPrinterTransport _transport = createReceiptPrinterTransport();

  /// Triggers full printing flow for an [Order].
  static Future<bool> printOrder({
    required Order order,
    FacilitySettings? facility,
    PrintService? printService,
    String? paymentMethod,
    double? paidAmount,
    double? changeDue,
  }) async {
    final ref = (order.canonicalOrderNumber?.isNotEmpty == true)
        ? order.canonicalOrderNumber!
        : (order.provisionalOrderNumber.isNotEmpty
            ? order.provisionalOrderNumber
            : order.localId);

    final safeTotal = order.total.isFinite ? order.total : 0.0;
    final safeSubtotal = order.subtotal.isFinite ? order.subtotal : 0.0;
    final safeTax = order.taxAmount.isFinite ? order.taxAmount : 0.0;
    final safeService = order.serviceAmount.isFinite ? order.serviceAmount : 0.0;

    final payload = {
      'orderRef': ref,
      'total': safeTotal,
      'subtotal': safeSubtotal,
      'tax': safeTax,
      'service': safeService,
      'method': paymentMethod ?? 'نقدي',
      'items': order.items
          .map((i) => {
                'name': i.name,
                'qty': i.quantity,
                'price': i.unitPrice,
                'total': i.unitPrice * i.quantity,
                if (i.modifiers.isNotEmpty) 'modifiers': i.modifiers.join(', '),
                if (i.note != null && i.note!.isNotEmpty) 'note': i.note,
              })
          .toList(),
    };

    // 1. Web browser printable thermal receipt (triggered immediately to preserve transient user activation)
    bool didPrint = false;
    try {
      final html = buildReceiptHtml(
        order: order,
        facility: facility ?? const FacilitySettings(),
        paymentMethod: paymentMethod,
        paidAmount: paidAmount,
        changeDue: changeDue,
      );

      didPrint = _transport.printHtml(html);
    } catch (e) {
      AppLogger.error('Receipt print failed', e);
    }

    // 2. Native / Socket ESC/POS print if available (async background queue)
    try {
      if (printService != null) {
        await printService.printReceipt(ref, payload);
      }
    } catch (e) {
      AppLogger.warn('ESC/POS print queue warning: $e');
    }

    return didPrint || kIsWeb;
  }

  /// Opens the receipt in a dedicated browser tab for standalone printing.
  static bool openOrderInTab({
    required Order order,
    FacilitySettings? facility,
    String? paymentMethod,
    double? paidAmount,
    double? changeDue,
  }) {
    try {
      final html = buildReceiptHtml(
        order: order,
        facility: facility ?? const FacilitySettings(),
        paymentMethod: paymentMethod,
        paidAmount: paidAmount,
        changeDue: changeDue,
      );
      return _transport.openHtmlInTab(html);
    } catch (e) {
      AppLogger.error('Open receipt tab failed', e);
      return false;
    }
  }


  /// Generates self-contained HTML for an 80mm/58mm thermal receipt.
  static String buildReceiptHtml({
    required Order order,
    required FacilitySettings facility,
    String? paymentMethod,
    double? paidAmount,
    double? changeDue,
  }) {
    final ref = (order.canonicalOrderNumber?.isNotEmpty == true)
        ? order.canonicalOrderNumber!
        : (order.provisionalOrderNumber.isNotEmpty
            ? order.provisionalOrderNumber
            : order.localId);

    final title = facility.receiptName.isNotEmpty
        ? facility.receiptName
        : (facility.nameAr.isNotEmpty ? facility.nameAr : 'PIE Restaurant');

    final safeTotal = order.total.isFinite ? order.total : 0.0;
    final safeSubtotal = order.subtotal.isFinite ? order.subtotal : 0.0;
    final safeTax = order.taxAmount.isFinite ? order.taxAmount : 0.0;
    final safeService = order.serviceAmount.isFinite ? order.serviceAmount : 0.0;

    final channelName = switch (order.orderType) {
      OrderType.dineIn => 'صالة',
      OrderType.takeaway => 'تيك أواي',
      OrderType.delivery => 'دليفري',
    };

    final dateStr =
        '${order.createdAt.year}-${order.createdAt.month.toString().padLeft(2, '0')}-${order.createdAt.day.toString().padLeft(2, '0')}';
    final timeStr =
        '${order.createdAt.hour.toString().padLeft(2, '0')}:${order.createdAt.minute.toString().padLeft(2, '0')}';

    final itemsRows = StringBuffer();
    for (final item in order.items) {
      final lineTotal = item.unitPrice * item.quantity;
      itemsRows.writeln('''
        <tr>
          <td style="font-weight: 700; padding: 4px 0;">${item.name}</td>
          <td style="text-align: center; padding: 4px 0;">${item.quantity}</td>
          <td style="text-align: left; font-weight: 700; padding: 4px 0;">${lineTotal.toStringAsFixed(2)}</td>
        </tr>
      ''');
      if (item.modifiers.isNotEmpty || (item.note != null && item.note!.isNotEmpty)) {
        final extras = [
          if (item.modifiers.isNotEmpty) item.modifiers.join(', '),
          if (item.note != null && item.note!.isNotEmpty) item.note!,
        ].join(' - ');
        itemsRows.writeln('''
          <tr>
            <td colspan="3" style="font-size: 11px; color: #444; padding-bottom: 3px;">• $extras</td>
          </tr>
        ''');
      }
    }

    final currency = facility.currency.isNotEmpty ? facility.currency : 'ج.م';
    final footer = facility.receiptFooter.isNotEmpty
        ? facility.receiptFooter
        : 'شكراً لزيارتكم! نسعد بخدمتكم دائماً';

    return '''
<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
  <meta charset="utf-8">
  <title>فاتورة #$ref</title>
  <style>
    @media print {
      @page {
        margin: 0;
        size: 80mm auto;
      }
      body, .receipt-root {
        margin: 0 !important;
        padding: 4px 8px !important;
        width: 72mm !important;
      }
      .print-actions {
        display: none !important;
      }
    }
    body, .receipt-root {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Cairo", "Arial", sans-serif;
      width: 72mm;
      max-width: 100%;
      margin: 0 auto;
      padding: 10px;
      color: #000;
      background: #fff;
      font-size: 12.5px;
      line-height: 1.35;
      box-sizing: border-box;
      direction: rtl;
    }
    .print-actions {
      text-align: center;
      margin-bottom: 12px;
      padding-bottom: 8px;
      border-bottom: 1px solid #ddd;
    }
    .print-btn {
      background: #0070F3;
      color: #fff;
      border: none;
      padding: 8px 16px;
      font-size: 14px;
      font-weight: 700;
      border-radius: 6px;
      cursor: pointer;
      font-family: inherit;
    }
    .header { text-align: center; margin-bottom: 8px; }
    .store-name { font-size: 18px; font-weight: 800; margin: 0; }
    .branch-name { font-size: 12px; color: #333; margin-top: 2px; }
    .tax-id { font-size: 11px; color: #444; margin-top: 2px; }
    .divider { border-top: 1px dashed #000; margin: 6px 0; }
    .meta-row { display: flex; justify-content: space-between; font-size: 11.5px; margin: 2px 0; }
    .table { width: 100%; border-collapse: collapse; margin: 6px 0; }
    .table th { border-bottom: 1px solid #000; padding: 4px 0; font-size: 12px; }
    .total-row { display: flex; justify-content: space-between; font-size: 12px; margin: 2px 0; }
    .grand-total {
      display: flex;
      justify-content: space-between;
      font-size: 16px;
      font-weight: 800;
      border-top: 2px solid #000;
      border-bottom: 2px solid #000;
      padding: 5px 0;
      margin: 6px 0;
    }
    .footer { text-align: center; font-size: 11px; margin-top: 10px; padding-top: 6px; }
  </style>
</head>
<body>
  <div class="print-actions">
    <button onclick="window.print()" class="print-btn">🖨️ طباعة الفاتورة الآن</button>
  </div>
  <div class="receipt-root" dir="rtl">
    <div class="header">
      <div class="store-name">$title</div>
      ${facility.activeBranchName.isNotEmpty ? '<div class="branch-name">فرع: ${facility.activeBranchName}</div>' : ''}
      ${facility.taxId.isNotEmpty ? '<div class="tax-id">الرقم الضريبي: ${facility.taxId}</div>' : ''}
      <div class="tax-id">فاتورة ضريبية مبسطة</div>
    </div>

    <div class="divider"></div>

    <div class="meta-row">
      <span>رقم الفاتورة:</span>
      <strong style="font-size: 13px;">#$ref</strong>
    </div>
    <div class="meta-row">
      <span>نوع الطلب:</span>
      <strong>$channelName</strong>
    </div>
    <div class="meta-row">
      <span>التاريخ والوقت:</span>
      <span>$dateStr • $timeStr</span>
    </div>

    <div class="divider"></div>

    <table class="table">
      <thead>
        <tr>
          <th style="text-align: right;">الصنف</th>
          <th style="text-align: center; width: 35px;">الكمية</th>
          <th style="text-align: left; width: 55px;">الإجمالي</th>
        </tr>
      </thead>
      <tbody>
        $itemsRows
      </tbody>
    </table>

    <div class="divider"></div>

    <div class="total-row">
      <span>المجموع الجزئي:</span>
      <span>${safeSubtotal.toStringAsFixed(2)} $currency</span>
    </div>
    ${safeService > 0 ? '<div class="total-row"><span>خدمة الصالة:</span><span>' + safeService.toStringAsFixed(2) + ' ' + currency + '</span></div>' : ''}
    ${safeTax > 0 ? '<div class="total-row"><span>ضريبة القيمة المضافة:</span><span>' + safeTax.toStringAsFixed(2) + ' ' + currency + '</span></div>' : ''}

    <div class="grand-total">
      <span>الإجمالي النهائي:</span>
      <span>${safeTotal.toStringAsFixed(2)} $currency</span>
    </div>

    <div class="total-row">
      <span>طريقة الدفع:</span>
      <span>${paymentMethod ?? 'نقدي'}</span>
    </div>
    ${paidAmount != null && paidAmount > 0 ? '<div class="total-row"><span>المبلغ المستلم:</span><span>' + paidAmount.toStringAsFixed(2) + ' ' + currency + '</span></div>' : ''}
    ${changeDue != null && changeDue > 0 ? '<div class="total-row" style="font-weight: 700;"><span>الباقي للعميل:</span><span>' + changeDue.toStringAsFixed(2) + ' ' + currency + '</span></div>' : ''}

    <div class="divider"></div>
    <div class="footer">$footer</div>
  </div>
  <script>
    if (window.opener) {
      setTimeout(function() {
        try { window.print(); } catch(_) {}
      }, 400);
    }
  </script>
</body>
</html>
''';
  }
}
