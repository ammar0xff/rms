# Stitch review — PIE Restaurant Management System project

Pulled 2026-10-16: 34 screens + Industrial Tactile POS dark design system.
Visually reviewed 7 flagships (cashier POS, shift, driver nav, driver
failed-delivery, manager dashboard, approvals, sysadmin diagnostics).

## Verdict

The Stitch project is a strong **flow catalog**, not a visual target. Its
information architecture is better than ours in three places (approvals,
failed delivery, shift close); its dark-everything theme conflicts with
our light app and must NOT be imported wholesale. Steal flows and density
patterns, keep our theme, type, and Egyptian voice.

## Steal (ranked)

1. **Approvals center depth.** Stitch cards carry: type tag (استرجاع /
   خصم / عهدة), amount hero, reason line, age timer, PIN-gated approve
   (اعتماد واسترجاع PIN), reject-with-reason, and outbox-backed pending
   signatures. Ours has approve/reject rows only. Port: PIN confirm on
   approve, reject-reason dialog, discount + petty-cash (إذن صرف) kinds.
2. **Failed-delivery + return flow.** Stitch has تعذر التسليم ومرتجع
   الأوردر as a first-class flow. We have no failed-delivery path at all:
   a driver who can't deliver can only stall the job. Add: mark-failed
   with reason → return-to-branch → stock back Loosely via adjustment.
3. **Shift close / Z-report.** Stitch treats تقفيل الوردية as its own
   screen (totals, counted vs expected, variance, print Z). Ours folds it
   into accounting. A dedicated close-shift sheet with Z print matches
   how cashiers actually end a night.
4. **Item modifiers + notes.** Stitch has per-item customization
   (الموديفايرز وملاحظات الصنف). Our order lines carry name/qty/price
   only — kitchen accuracy suffers on real orders. Add: optional note
   per cart line, printed on the ticket.
5. **Invoice archive / reprint / void.** Stitch has أرشيف الفواتير with
   reprint + cancel. We print once; reprint-after-the-fact and void with
   approval don't exist. Add: recent-invoices list with reprint, void
   behind manager approval.
6. **Driver stop sequencing UI.** Stitch shows the route polyline +
   stop timeline in-app (we correctly deep-link nav to Maps — keep
   that), but its stop cards (order + amount + COD collected state) are
   denser and better than our queue cards. Adopt the density, not the map.
7. **Table/floor map.** Stitch has خريطة الصالة والطاولات (desktop).
   Only relevant if dine-in table tracking matters; currently out of
   scope — record, don't build.

## Skip

- Full-dark theme. Our light app + dark KDS is the right call for mixed
  lighting (counter daylight, kitchen heat). Dark-everything hurts
  daytime counter readability.
- English chrome mixed into Arabic screens (Stitch's "Report Issue"
  header, "Outbox" inline). Our voice stays fully Egyptian.
- Decorative density: Stitch cards are richer but busier; our FeedRow
  rhythm already tests cleaner at 390px.

## Compatible patterns (already aligned, no work)

Tabular numerals, mono ids/amounts, 4–9px radii, hairline borders,
status dots + tags, role accent colors (amber/flame/sky/emerald/violet
match our five accents almost 1:1).

## Recommended actions

1. PIN-gated approve + reject-reason + discount/petty-cash kinds
   (accounting).
2. Failed-delivery flow with reason + return leg (delivery).
3. Close-shift sheet with Z print (accounting/shift).
4. Cart-line notes → kitchen ticket (pos/kitchen).
5. Invoice archive with reprint + approval-gated void (accounting).
6. Denser driver stop cards (delivery).
