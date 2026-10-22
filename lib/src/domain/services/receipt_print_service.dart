import 'package:flutter/foundation.dart';
import '../../core/logging/app_logger.dart';
import '../../data/services/print_service.dart';
import '../models/cash_session.dart';
import '../models/delivery.dart';
import '../models/facility_settings.dart';
import '../models/kitchen_ticket.dart';
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
          <td style="font-weight: 700; padding: 4px 0;">${_escapeHtml(item.name)}</td>
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
            <td colspan="3" style="font-size: 11px; color: #444; padding-bottom: 3px;">• ${_escapeHtml(extras)}</td>
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
      <div class="store-name">${_escapeHtml(title)}</div>
      ${facility.activeBranchName.isNotEmpty ? '<div class="branch-name">فرع: ' + _escapeHtml(facility.activeBranchName) + '</div>' : ''}
      ${facility.taxId.isNotEmpty ? '<div class="tax-id">الرقم الضريبي: ' + _escapeHtml(facility.taxId) + '</div>' : ''}
      <div class="tax-id">فاتورة ضريبية مبسطة</div>
    </div>

    <div class="divider"></div>

    <div class="meta-row">
      <span>رقم الفاتورة:</span>
      <strong style="font-size: 13px;">#${_escapeHtml(ref)}</strong>
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
    <div class="footer">${_escapeHtml(footer)}</div>
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

  /// HTML entity escaping helper to prevent malformed DOM and injection
  static String _escapeHtml(String? text) {
    if (text == null || text.isEmpty) return '';
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  /// Triggers full printing flow for a [KitchenTicketModel].
  static Future<bool> printKitchenTicket({
    required KitchenTicketModel ticket,
    FacilitySettings? facility,
    PrintService? printService,
  }) async {
    bool didPrint = false;
    try {
      final html = buildKitchenTicketHtml(
        ticket: ticket,
        facility: facility ?? const FacilitySettings(),
      );
      didPrint = _transport.printHtml(html);
    } catch (e) {
      AppLogger.error('Kitchen ticket web print failed', e);
    }

    try {
      if (printService != null) {
        await printService.printKitchenTicket(ticket);
      }
    } catch (e) {
      AppLogger.warn('Kitchen ticket ESC/POS queue warning: $e');
    }

    return didPrint || kIsWeb;
  }

  /// Opens the kitchen ticket in a dedicated browser tab.
  static bool openKitchenTicketInTab({
    required KitchenTicketModel ticket,
    FacilitySettings? facility,
  }) {
    try {
      final html = buildKitchenTicketHtml(
        ticket: ticket,
        facility: facility ?? const FacilitySettings(),
      );
      return _transport.openHtmlInTab(html);
    } catch (e) {
      AppLogger.error('Open kitchen ticket tab failed', e);
      return false;
    }
  }

  /// Triggers full printing flow for a [CashSession] Z-Report.
  static Future<bool> printZReport({
    required CashSession session,
    FacilitySettings? facility,
    required double expectedCash,
    required double countedCash,
    required double variance,
    Map<int, int>? counts,
    String? cashierName,
  }) async {
    try {
      final html = buildZReportHtml(
        session: session,
        facility: facility ?? const FacilitySettings(),
        expectedCash: expectedCash,
        countedCash: countedCash,
        variance: variance,
        counts: counts,
        cashierName: cashierName,
      );
      return _transport.printHtml(html) || kIsWeb;
    } catch (e) {
      AppLogger.error('Z-Report print failed', e);
      return false;
    }
  }

  /// Opens the Z-Report in a dedicated browser tab.
  static bool openZReportInTab({
    required CashSession session,
    FacilitySettings? facility,
    required double expectedCash,
    required double countedCash,
    required double variance,
    Map<int, int>? counts,
    String? cashierName,
  }) {
    try {
      final html = buildZReportHtml(
        session: session,
        facility: facility ?? const FacilitySettings(),
        expectedCash: expectedCash,
        countedCash: countedCash,
        variance: variance,
        counts: counts,
        cashierName: cashierName,
      );
      return _transport.openHtmlInTab(html);
    } catch (e) {
      AppLogger.error('Open Z-Report tab failed', e);
      return false;
    }
  }

  /// Triggers full printing flow for a [DeliveryModel] driver slip.
  static Future<bool> printDeliverySlip({
    required DeliveryModel delivery,
    FacilitySettings? facility,
    Order? order,
  }) async {
    try {
      final html = buildDeliverySlipHtml(
        delivery: delivery,
        facility: facility ?? const FacilitySettings(),
        order: order,
      );
      return _transport.printHtml(html) || kIsWeb;
    } catch (e) {
      AppLogger.error('Delivery slip print failed', e);
      return false;
    }
  }

  /// Opens the Delivery slip in a dedicated browser tab.
  static bool openDeliverySlipInTab({
    required DeliveryModel delivery,
    FacilitySettings? facility,
    Order? order,
  }) {
    try {
      final html = buildDeliverySlipHtml(
        delivery: delivery,
        facility: facility ?? const FacilitySettings(),
        order: order,
      );
      return _transport.openHtmlInTab(html);
    } catch (e) {
      AppLogger.error('Open delivery slip tab failed', e);
      return false;
    }
  }

  /// Generates self-contained HTML for an 80mm/58mm thermal kitchen order ticket.
  static String buildKitchenTicketHtml({
    required KitchenTicketModel ticket,
    required FacilitySettings facility,
  }) {
    final title = facility.receiptName.isNotEmpty
        ? facility.receiptName
        : (facility.nameAr.isNotEmpty ? facility.nameAr : 'PIE Restaurant');

    final dateStr =
        '${ticket.createdAt.year}-${ticket.createdAt.month.toString().padLeft(2, '0')}-${ticket.createdAt.day.toString().padLeft(2, '0')}';
    final timeStr =
        '${ticket.createdAt.hour.toString().padLeft(2, '0')}:${ticket.createdAt.minute.toString().padLeft(2, '0')}';

    final itemsHtml = StringBuffer();
    for (final item in ticket.items) {
      itemsHtml.writeln('''
        <div style="font-size: 15px; font-weight: 800; padding: 6px 0; border-bottom: 1px dashed #ccc;">
          • ${_escapeHtml(item)}
        </div>
      ''');
    }

    return '''
<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
  <meta charset="utf-8">
  <title>بون مطبخ #${ticket.orderRef}</title>
  <style>
    @media print {
      @page { margin: 0; size: 80mm auto; }
      body, .receipt-root { margin: 0 !important; padding: 4px 8px !important; width: 72mm !important; }
      .print-actions { display: none !important; }
    }
    body, .receipt-root {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Cairo", "Arial", sans-serif;
      width: 72mm;
      max-width: 100%;
      margin: 0 auto;
      padding: 10px;
      color: #000;
      background: #fff;
      font-size: 13px;
      line-height: 1.35;
      box-sizing: border-box;
      direction: rtl;
    }
    .print-actions { text-align: center; margin-bottom: 12px; padding-bottom: 8px; border-bottom: 1px solid #ddd; }
    .print-btn { background: #E11D48; color: #fff; border: none; padding: 8px 16px; font-size: 14px; font-weight: 700; border-radius: 6px; cursor: pointer; font-family: inherit; }
    .header { text-align: center; margin-bottom: 8px; }
    .station-badge { display: inline-block; background: #000; color: #fff; padding: 4px 12px; font-size: 16px; font-weight: 800; border-radius: 4px; margin-bottom: 6px; }
    .order-ref { font-size: 24px; font-weight: 900; margin: 4px 0; }
    .divider { border-top: 2px dashed #000; margin: 8px 0; }
    .meta-row { display: flex; justify-content: space-between; font-size: 12px; margin: 2px 0; }
  </style>
</head>
<body>
  <div class="print-actions">
    <button onclick="window.print()" class="print-btn">🖨️ طباعة بون المطبخ</button>
  </div>
  <div class="receipt-root" dir="rtl">
    <div class="header">
      <div class="station-badge">*** محطة: ${_escapeHtml(ticket.station)} ***</div>
      <div style="font-size: 12px; color: #555;">${_escapeHtml(title)}</div>
      <div class="order-ref">طلب #${_escapeHtml(ticket.orderRef)}</div>
    </div>
    <div class="divider"></div>
    <div class="meta-row">
      <span>رقم البون:</span>
      <strong>#${_escapeHtml(ticket.id)}</strong>
    </div>
    <div class="meta-row">
      <span>وقت الطلب:</span>
      <span>$dateStr • $timeStr</span>
    </div>
    <div class="divider"></div>
    <div style="margin: 8px 0;">
      $itemsHtml
    </div>
    <div class="divider"></div>
    <div style="text-align: center; font-size: 11px; margin-top: 6px;">
      *** استعجال فوري - جودة الطهي ***
    </div>
  </div>
  <script>
    if (window.opener) {
      setTimeout(function() { try { window.print(); } catch(_) {} }, 400);
    }
  </script>
</body>
</html>
''';
  }

  /// Generates self-contained HTML for an 80mm/58mm thermal Z-Report (تقفيل الوردية).
  static String buildZReportHtml({
    required CashSession session,
    required FacilitySettings facility,
    required double expectedCash,
    required double countedCash,
    required double variance,
    Map<int, int>? counts,
    String? cashierName,
  }) {
    final title = facility.receiptName.isNotEmpty
        ? facility.receiptName
        : (facility.nameAr.isNotEmpty ? facility.nameAr : 'PIE Restaurant');

    final currency = facility.currency.isNotEmpty ? facility.currency : 'ج.م';

    final openDateStr =
        '${session.openedAt.year}-${session.openedAt.month.toString().padLeft(2, '0')}-${session.openedAt.day.toString().padLeft(2, '0')} ${session.openedAt.hour.toString().padLeft(2, '0')}:${session.openedAt.minute.toString().padLeft(2, '0')}';
    final closeDate = session.closedAt ?? DateTime.now();
    final closeDateStr =
        '${closeDate.year}-${closeDate.month.toString().padLeft(2, '0')}-${closeDate.day.toString().padLeft(2, '0')} ${closeDate.hour.toString().padLeft(2, '0')}:${closeDate.minute.toString().padLeft(2, '0')}';

    final varianceLabel = variance == 0
        ? '<strong style="color: #059669;">مطابق تماماً (0.00 $currency)</strong>'
        : (variance > 0
            ? '<strong style="color: #059669;">زيادة بالدرج: +${variance.toStringAsFixed(2)} $currency</strong>'
            : '<strong style="color: #DC2626;">عجز بالدرج: -${variance.abs().toStringAsFixed(2)} $currency</strong>');

    final denomsHtml = StringBuffer();
    if (counts != null && counts.isNotEmpty) {
      denomsHtml.writeln('''
        <div style="font-weight: 700; margin-top: 8px; margin-bottom: 4px; font-size: 11.5px;">تفاصيل جرد الفئات النقدية:</div>
        <table style="width: 100%; border-collapse: collapse; font-size: 11px;">
      ''');
      for (final entry in counts.entries) {
        if (entry.value > 0) {
          final denom = entry.key;
          final count = entry.value;
          final subtotal = denom * count;
          final label = denom == 1 ? 'عملات معدنية' : 'ورقة $denom $currency';
          denomsHtml.writeln('''
            <tr>
              <td style="padding: 2px 0;">$label</td>
              <td style="text-align: center; padding: 2px 0;">× $count</td>
              <td style="text-align: left; font-weight: 700; padding: 2px 0;">${subtotal.toStringAsFixed(2)}</td>
            </tr>
          ''');
        }
      }
      denomsHtml.writeln('</table>');
    }

    return '''
<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
  <meta charset="utf-8">
  <title>تقرير تقفيل وردية Z #${session.id}</title>
  <style>
    @media print {
      @page { margin: 0; size: 80mm auto; }
      body, .receipt-root { margin: 0 !important; padding: 4px 8px !important; width: 72mm !important; }
      .print-actions { display: none !important; }
    }
    body, .receipt-root {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Cairo", "Arial", sans-serif;
      width: 72mm;
      max-width: 100%;
      margin: 0 auto;
      padding: 10px;
      color: #000;
      background: #fff;
      font-size: 12px;
      line-height: 1.35;
      box-sizing: border-box;
      direction: rtl;
    }
    .print-actions { text-align: center; margin-bottom: 12px; padding-bottom: 8px; border-bottom: 1px solid #ddd; }
    .print-btn { background: #0F172A; color: #fff; border: none; padding: 8px 16px; font-size: 14px; font-weight: 700; border-radius: 6px; cursor: pointer; font-family: inherit; }
    .header { text-align: center; margin-bottom: 8px; }
    .store-name { font-size: 16px; font-weight: 800; margin: 0; }
    .report-title { font-size: 15px; font-weight: 800; margin: 4px 0; text-decoration: underline; }
    .divider { border-top: 1px dashed #000; margin: 6px 0; }
    .meta-row { display: flex; justify-content: space-between; font-size: 11px; margin: 2px 0; }
    .summary-box { background: #f8fafc; border: 1px solid #cbd5e1; padding: 6px; border-radius: 4px; margin: 6px 0; }
    .signatures { display: flex; justify-content: space-between; margin-top: 24px; padding-top: 8px; border-top: 1px dashed #999; font-size: 11px; }
  </style>
</head>
<body>
  <div class="print-actions">
    <button onclick="window.print()" class="print-btn">🖨️ طباعة تقرير تقفيل الوردية Z</button>
  </div>
  <div class="receipt-root" dir="rtl">
    <div class="header">
      <div class="store-name">${_escapeHtml(title)}</div>
      ${facility.activeBranchName.isNotEmpty ? '<div style="font-size: 11px;">فرع: ' + _escapeHtml(facility.activeBranchName) + '</div>' : ''}
      <div class="report-title">تقرير تقفيل الوردية اليومي (Z-Close)</div>
      <div style="font-size: 10.5px; color: #555;">معرف الوردية: #${_escapeHtml(session.id)}</div>
    </div>
    <div class="divider"></div>
    <div class="meta-row">
      <span>فتح الوردية:</span>
      <span>$openDateStr</span>
    </div>
    <div class="meta-row">
      <span>إغلاق الوردية:</span>
      <span>$closeDateStr</span>
    </div>
    ${cashierName != null && cashierName.isNotEmpty ? '<div class="meta-row"><span>مسؤول الوردية:</span><strong>' + _escapeHtml(cashierName) + '</strong></div>' : ''}
    <div class="divider"></div>
    <div class="meta-row">
      <span>الرصيد الافتتاحي (عهدة الدرج):</span>
      <strong>${session.openingFloat.toStringAsFixed(2)} $currency</strong>
    </div>
    <div class="meta-row">
      <span>الرصيد المتوقع بالدفتر:</span>
      <strong>${expectedCash.toStringAsFixed(2)} $currency</strong>
    </div>
    <div class="meta-row">
      <span>الرصيد الفعلي المجرود:</span>
      <strong>${countedCash.toStringAsFixed(2)} $currency</strong>
    </div>
    <div class="summary-box">
      <div class="meta-row">
        <span>الفارق النهائي:</span>
        <span>$varianceLabel</span>
      </div>
    </div>
    $denomsHtml
    <div class="divider"></div>
    <div class="signatures">
      <div>توقيع الكاشير:<br><br>........................</div>
      <div>توقيع المشرف / المدير:<br><br>........................</div>
    </div>
  </div>
  <script>
    if (window.opener) {
      setTimeout(function() { try { window.print(); } catch(_) {} }, 400);
    }
  </script>
</body>
</html>
''';
  }

  /// Generates self-contained HTML for an 80mm/58mm thermal delivery driver slip (بون سائق التوصيل).
  static String buildDeliverySlipHtml({
    required DeliveryModel delivery,
    required FacilitySettings facility,
    Order? order,
  }) {
    final title = facility.receiptName.isNotEmpty
        ? facility.receiptName
        : (facility.nameAr.isNotEmpty ? facility.nameAr : 'PIE Restaurant');

    final currency = facility.currency.isNotEmpty ? facility.currency : 'ج.م';

    final dateStr =
        '${delivery.createdAt.year}-${delivery.createdAt.month.toString().padLeft(2, '0')}-${delivery.createdAt.day.toString().padLeft(2, '0')}';
    final timeStr =
        '${delivery.createdAt.hour.toString().padLeft(2, '0')}:${delivery.createdAt.minute.toString().padLeft(2, '0')}';

    final itemsHtml = StringBuffer();
    if (order != null && order.items.isNotEmpty) {
      itemsHtml.writeln('''
        <div style="font-weight: 700; margin-top: 6px; margin-bottom: 4px; font-size: 11.5px;">أصناف الطلب:</div>
        <table style="width: 100%; border-collapse: collapse; font-size: 11.5px;">
      ''');
      for (final item in order.items) {
        itemsHtml.writeln('''
          <tr>
            <td style="padding: 3px 0; font-weight: 700;">${_escapeHtml(item.name)}</td>
            <td style="text-align: center; padding: 3px 0;">× ${item.quantity}</td>
          </tr>
        ''');
        if (item.modifiers.isNotEmpty || (item.note != null && item.note!.isNotEmpty)) {
          final extras = [
            if (item.modifiers.isNotEmpty) item.modifiers.join(', '),
            if (item.note != null && item.note!.isNotEmpty) item.note!,
          ].join(' - ');
          itemsHtml.writeln('''
            <tr>
              <td colspan="2" style="font-size: 10.5px; color: #444; padding-bottom: 2px;">• ${_escapeHtml(extras)}</td>
            </tr>
          ''');
        }
      }
      itemsHtml.writeln('</table>');
    }

    return '''
<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
  <meta charset="utf-8">
  <title>بون توصيل #${delivery.orderRef}</title>
  <style>
    @media print {
      @page { margin: 0; size: 80mm auto; }
      body, .receipt-root { margin: 0 !important; padding: 4px 8px !important; width: 72mm !important; }
      .print-actions { display: none !important; }
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
    .print-actions { text-align: center; margin-bottom: 12px; padding-bottom: 8px; border-bottom: 1px solid #ddd; }
    .print-btn { background: #0284C7; color: #fff; border: none; padding: 8px 16px; font-size: 14px; font-weight: 700; border-radius: 6px; cursor: pointer; font-family: inherit; }
    .header { text-align: center; margin-bottom: 8px; }
    .badge { display: inline-block; background: #0284C7; color: #fff; padding: 3px 10px; font-size: 13px; font-weight: 800; border-radius: 4px; }
    .order-ref { font-size: 22px; font-weight: 900; margin: 4px 0; }
    .divider { border-top: 1px dashed #000; margin: 6px 0; }
    .meta-row { display: flex; justify-content: space-between; font-size: 11.5px; margin: 2px 0; }
    .address-card { background: #f0f9ff; border: 1.5px solid #bae6fd; padding: 8px; border-radius: 6px; margin: 6px 0; font-size: 12px; }
    .collect-hero {
      border: 2px solid #000;
      background: #fff;
      padding: 8px;
      text-align: center;
      margin: 8px 0;
      border-radius: 6px;
    }
    .collect-hero .amount {
      font-size: 20px;
      font-weight: 900;
      color: #000;
    }
  </style>
</head>
<body>
  <div class="print-actions">
    <button onclick="window.print()" class="print-btn">🖨️ طباعة بون السائق</button>
  </div>
  <div class="receipt-root" dir="rtl">
    <div class="header">
      <div class="badge">بون تسليم سائق الدليفري</div>
      <div style="font-size: 12px; color: #444; margin-top: 3px;">${_escapeHtml(title)}</div>
      <div class="order-ref">أوردر #${_escapeHtml(delivery.orderRef)}</div>
    </div>
    <div class="divider"></div>
    <div class="meta-row">
      <span>تاريخ وتوقيت البون:</span>
      <span>$dateStr • $timeStr</span>
    </div>
    <div class="address-card">
      <div style="font-weight: 800; margin-bottom: 3px;">📍 عنوان التوصيل:</div>
      <div style="font-size: 13px; font-weight: 700;">${_escapeHtml(delivery.address)}</div>
    </div>
    <div class="collect-hero">
      <div style="font-size: 12px; font-weight: 700;">المطلوب تحصيله كاش من العميل:</div>
      <div class="amount">${delivery.amount.toStringAsFixed(2)} $currency</div>
    </div>
    $itemsHtml
    <div class="divider"></div>
    <div style="text-align: center; font-size: 11px; margin-top: 8px;">
      توقيع استلام السائق: ........................
    </div>
  </div>
  <script>
    if (window.opener) {
      setTimeout(function() { try { window.print(); } catch(_) {} }, 400);
    }
  </script>
</body>
</html>
''';
  }
}
