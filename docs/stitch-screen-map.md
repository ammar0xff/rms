# Stitch screen map

Authoritative source: Stitch project `17082616717859119330`, pulled with
`stitch.download_assets` into `.design-export/` (gitignored — regenerate, never
commit). The design document behind every value in the theme is the project's
`designMd`, not a hand-reading of the generated HTML.

34 screens: 28 mobile (780px wide), 6 desktop (2560px wide).

## Status

`ported` — the screen's structure comes from its design file.
`partial` — some sections ported, the rest is the pre-existing layout.
`todo`   — not started.

| Design screen | Device | Flutter screen | Status |
|---|---|---|---|
| نقطة البيع وبناء الطلب - تطبيق الكاشير | mobile | `pos/pos_screen.dart` | partial |
| الدفع وإنهاء الفاتورة - تطبيق الكاشير | mobile | POS payment dialog | partial |
| تخصيص الموديفايرز وملاحظات الصنف - الكاشير | mobile | POS customise sheet | partial |
| نقطة البيع وبناء الطلب - محطة العمل المكتبية | desktop | POS wide layout | partial |
| محطة العمل المكتبية المتكاملة - نقطة البيع | desktop | POS wide layout | partial |
| الوردية ولوحة المبيعات - تطبيق الكاشير | mobile | `shift/shift_screen.dart` | partial |
| جرد الكاش وتقفيل الوردية Z-Report - الكاشير | mobile | `accounting/accounting_screen.dart` | partial |
| تسوية العهدة والتقفيل - تطبيق الكاشير | mobile | accounting settlement | partial |
| الوردية وتقفيل الكاش Z-Report - محطة العمل المكتبية | desktop | accounting settlement | todo |
| إدارة الصالة والطاولات - تطبيق الكاشير | mobile | `tables/tables_screen.dart` | partial |
| خريطة الصالة والطاولات - محطة العمل المكتبية | desktop | `tables/tables_screen.dart` | todo |
| قائمة الأوردرات النشطة ومسار الطلعة - الطيار | mobile | `delivery/delivery_screen.dart` | partial |
| توصيل وملاحة الدليفري - الطيار | mobile | driver navigate sheet | partial |
| تعذر التسليم ومرتجع الأوردر - الطيار | mobile | driver fail flow | partial |
| تفاصيل بون التوصيل والفاتورة - الطيار | mobile | driver receipt sheet | partial |
| تسوية وتوريد عهدة الكاش - الطيار | mobile | driver custody sheet | partial |
| سجل التوصيل والأرشيف اليومي - الطيار | mobile | `delivery/trip_log_screen.dart` | todo |
| إدارة أسطول التوصيل والدليفري المركزي - المدير | mobile | driver list panel | todo |
| لوحة القيادة والمتابعة اللحظية - المدير | mobile | `dashboard/dashboard_screen.dart` | partial |
| مركز الموافقات الإدارية - المدير | mobile | `accounting` approvals | partial |
| تأكيد كود المدير وتفويض العمليات - المدير | mobile | `pin` gate | partial |
| إدارة ومراقبة أوردرات كافة الفروع - المدير | mobile | `triage/triage_screen.dart` | todo |
| شبكة الفروع والتحويل المخزني الطارئ - المدير | mobile | `branches/branches_screen.dart` | todo |
| إدارة المخزون وحركة الخامات - المدير | mobile | `inventory/inventory_screen.dart` | todo |
| المخزون وحركة الخامات - المدير | mobile | `inventory/inventory_screen.dart` | todo |
| أرشيف الفواتير وإعادة الطباعة والإلغاء - الكاشير | mobile | `accounting` archive | partial |
| أرشيف الفواتير والمرتجع - محطة العمل المكتبية | desktop | accounting archive | todo |
| إدارة المستخدمين وصلاحيات الموظفين والورديات - المدير | mobile | `team/team_screen.dart` | todo |
| تشخيص النظام ومفتش الـ Outbox | mobile | `system/system_screen.dart` | partial |
| بوابة التحديثات الآمنة ومفتش AC-35 - مهندس النظام | mobile | update centre | partial |
| فض التعارضات والدمج الثلاثي - مهندس النظام | mobile | `conflicts/conflicts_screen.dart` | todo |
| تخصيص الهوية وإعدادات النظام - مهندس النظام | mobile | `settings/settings_screen.dart` | todo |
| الأوردرات ومتابعة التوصيل - محطة العمل المكتبية | desktop | `triage` wide | todo |
| PIE POS & Delivery Operations System | mobile | app entry / sign-in | todo |

## Rules the port follows

1. **The `designMd` is the source for tokens.** Not a hand-reading of the
   generated HTML. `test/design_system_test.dart` pins every value, quoted from
   the document, so a drift fails CI.
2. **Real data only.** A design section with nothing behind it is ported as a
   structure with an honest empty state, never as invented figures. A POS that
   shows fabricated sales totals is a financial-safety problem.
3. **No dead controls.** Anything the design shows that this app cannot act on
   is omitted, and noted here.
4. **Everything else counts as ours, not Stitch's.** If a widget's markup
   traces to no design file, it is not a port.

## Known omissions

The design was written for five roles including a kitchen display system. This
app has four — KDS was removed — so its crimson accent survives only as the
destructive/error red it doubles as, and no design file is ported for it.
