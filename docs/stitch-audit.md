# Stitch screen-by-screen audit

29 of 34 screens visually reviewed 2026-10-16 (4 file downloads API-blocked:
pay_bill, archive_desktop, tables_desktop, zreport_desktop; 1 has no image).
Judged as design only: mistakes inside Stitch's own language, and gaps
against our Flutter app.

## Cashier

1. **نقطة البيع وبناء الطلب (mobile).** Dense grid + sticky cart bar + tender
   row. Works. Mistake: product cards show stepper + price but no station
   tag (ours has it — keep ours). Steal: nothing structural; validates ours.
2. **الوردية ولوحة المبيعات.** Shift hero + KPI strip + queue. Matches our
   console 1:1 in structure. No mistakes. Validates our direction.
3. **الدفع وإنهاء الفاتورة.** Tender modal with denominations + change math.
   Steal: cash denomination shortcuts (ours jumps straight to exact/card).
4. **تخصيص الموديفايرز وملاحظات الصنف.** Required/optional modifier groups,
   allergy flag (حساسية مكسرات), free-text kitchen note, qty + live price
   bar. No mistakes. Steal: the whole pattern — our lines carry no notes.
5. **أرشيف الفواتير وإعادة الطباعة والإلغاء** (no image). Title implies
   reprint + void; matches our gap #5. Cannot judge visuals.
6. **تسوية العهدة والتقفيل.** Settlement breakdown + handover confirm.
   Works. Aligns with our close-session flow; steal the itemized breakdown
   layout.
7. **جرد الكاش وتقفيل الوردية Z-Report** (image blank — generation
   incomplete). Title confirms dedicated Z screen. Cannot judge visuals.
8. **إدارة الصالة والطاولات.** Table grid with occupancy + session timers.
   Works. Out of scope unless dine-in tracking matters.
9. **نقطة البيع (desktop) + المحطة المتكاملة (desktop).** Three-zone
   workstation: grid + docked ledger + keypad/denominations. Validates our
   rails. Steal: numeric keypad + denomination shortcuts for rush tender.

## Driver

10. **توصيل وملاحة الدليفري.** In-app map + stop timeline + COD card.
    Mistake: in-app map duplicates the phone's Maps (battery, offline
    tiles, traffic all worse). Keep our deep-link; steal stop-card density.
11. **قائمة الأوردرات النشطة ومسار الطلعة.** Sequenced stops (المحطة N)
    with COD per stop. Works. Steal: route badge numbering — planned.
12. **تفاصيل بون التوصيل والفاتورة.** Item lines + totals + customer
    confirm + offline-settle note. Works. Our job cards should show the
    item count line the way this does.
13. **تعذر التسليم ومرتجع الأوردر.** Reason-coded failure + return leg.
    No mistakes. Steal entire flow — we have nothing here.
14. **تسوية وتوريد عهدة الكاش.** Breakdown + QR handover + settle CTA.
    Works. QR needs backend; steal the breakdown, defer QR.
15. **سجل التوصيل والأرشيف اليومي.** Daily log with km + per-order cards
    + mini map. Works. Steal: per-day totals strip (km, orders, cash).

## Manager

16. **لوحة القيادة والمتابعة اللحظية.** KPIs + hourly bars + alerts.
    Matches ours. No mistakes. Validates.
17. **مركز الموافقات الإدارية.** Type tags, amount hero, age timer,
    PIN approve, reject-reason, outbox-backed signature. Best screen in
    the project. Steal everything (our gap #1).
18. **تأكيد كود المدير (PIN keypad).** Tactile keypad + approve/deny +
    synced receipt. No mistakes. Steal as the PIN pattern.
19. **إدارة ومراقبة أوردرات كافة الفروع.** Branch-filtered order stream.
    Works. Our dashboard lacks cross-branch orders; steal if multi-branch
    ops matter.
20. **إدارة المخزون وحركة الخامات (×2).** Levels + movement feed +
    low-stock alerts. Matches our feed direction. No mistakes.
21. **شبكة الفروع والتحويل المخزني الطارئ.** Health scores + comparison
    bars + emergency transfer CTA. Steal: inter-branch transfer flow
    (we have none); health-score presentation is decorative — skip.
22. **إدارة المستخدمين والصلاحيات.** Role toggles + per-user PIN +
    shift assignment. Works. Steal: per-user PIN (enables PIN approvals);
    granular permission toggles exceed our fixed-role model — defer.
23. **الأوردرات ومتابعة التوصيل (desktop).** Dense ops columns + rail.
    Works. Our ops console matches in structure.

## Dev / system

24. **تشخيص النظام ومفتش Outbox.** Binary-diagnostic styling, op table,
    queue stats. Content matches ours; styling is harsher. No steal.
25. **فض التعارضات والدمج الثلاثي.** Three-way merge (local/remote/merged
    values + amounts). Best dev screen. Steal: value comparison — our
    requeue-only resolution can't show WHAT differs.
26. **بوابة التحديثات الآمنة ومفتش AC-35.** Pre-install readiness
    checklist (outbox empty, conflicts resolved, notes, gated install).
    No mistakes. Steal: the consolidated checklist — our gate fires
    without showing its work.
27. **تخصيص الهوية وإعدادات النظام.** Theme/role/printer hardware config.
    Steal: printer settings screen (our printing is still stub + blocked
    on scoping — this unblocks the UI half).

## Cross-cutting findings

- **Blank generations:** zreport, cashier_settle, invoice_archive came back
  unpainted (screens still generating or failed). Do not treat them as
  designs; their titles still confirm the flows exist.
- **Mixed-language chrome** on several headers (English titles inside
  Arabic screens). Our fully-Egyptian voice stays.
- **Density without hierarchy** in ops screens (orders_desktop): readable
  on desktop, would crush a phone — never port 1:1 to mobile.
- **No empty/loading states visible** in any capture (all show filled
  demo data). Our empty-state discipline is ahead; keep it while stealing
  filled layouts.
- **Theme conflict stands:** full-dark everywhere. Port patterns, never
  the palette.

## Build order from this audit

1. PIN approvals + reject-reason + discount/petty-cash kinds.
2. Failed-delivery flow with return leg.
3. Update readiness checklist screen (AC-35 shows its work).
4. Three-way conflict values.
5. Cart-line notes → tickets (+ modifiers sheet).
6. Cash denomination shortcuts + keypad tender.
7. Invoice archive + reprint + void.
8. Driver day-totals strip + stop numbering.
9. Printer settings screen.
10. Inter-branch transfer (only if ops need it).
