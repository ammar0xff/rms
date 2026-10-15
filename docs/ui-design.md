# Full UI design plan — five role apps

One family, five uniforms. Same warm theme, type, shell, Egyptian voice.
Each role app is designed around its core loop, for phone first and PC as
a real workstation — not a stretched phone.

Shared blocks (built): `RoleHero`, `KpiCard`, `QuickActionTile`, `FeedRow`,
`Tag`, `StatusText`, `RmsTable`, `SurfaceCard`, `GridRow`/`ResponsiveRow`.
New blocks (to build): `DialogShell`, `ListToolbar` (search + chips +
action), `SegmentedControl`, `ChartCard`, `StatStrip`, `TimelineList`.

Global rules: PC content caps at 1160px centered (`PageBody`). Tables
scroll sideways on phones, fill on PC. Heroes stack figure-under-title
under 560px. Every dialog is pumped at 390px and 1440px. Money stays
tabular; currency suffix lives in labels, not values.

---

## 1. Cashier — الكاشير (amber)

Core loop: open shift → sell → collect → close. Thumb-speed, fat targets.

### 1.1 Shift home (built)
Hero (sales figure + بيع جديد) · KPI strip (orders, avg ticket) · quick
tiles (customers, session) · queue feed. Mobile: stacked. PC: hero figure
beside title, KPIs in a row, queue beside a session-digest side card
(new: today's collections + open/closed state).

### 1.2 POS — البيع
- Mobile (built, keep): category chips + product grid + sticky cart bar +
  cart tab with badge. Add: `SegmentedControl` for order type
  (صالة / تيك أواي / دليفري) above the grid; quick-tender row in cart
  (كاش exact / فيزا) that skips the amount dialog when tendered ≥ total.
- PC (new): three rails — category rail (right, 200px, icons + counts) ·
  product grid (flex, cards with price pills) · docked cart panel (320px:
  lines with steppers, tender buttons, totals, إرسال). No dialog cart.
- Product card (both): name (2-line ellipsis), price pill, station dot,
  unavailable dimmed with نفد tag. Tap adds with a micro check-flash.
- Cart line: name, stepper (−/+ 44px targets), line total, swipe-to-remove
  on mobile; hover remove on PC.
- Checkout sheet (mobile) / docked totals (PC): subtotal, discount row,
  total hero-size, tendered input, باقي readout, ادفع button. Validation
  inline under the field, never a toast alone.
- States: empty grid (مفيش أصناف + ضيف من القائمة CTA), empty cart
  illustration-less centered hint, offline banner (شغال من غير نت).

### 1.3 Customers — العملاء
`ListToolbar` (دوّر + زرار ضيف عميل) · customer cards on mobile (name,
phone tap-to-call, orders count, balance), table on PC. Add/edit in
`DialogShell` (name required inline, phone, notes). Delete asks متأكد؟.

### 1.4 Cash session — الجلسة (inside accounting)
Session hero (open float, expected, counted, variance colored) · open/close
actions · payments feed · approvals with wrap buttons (built). PC: hero +
session form side by side; mobile stacked.

## 2. Chef — المطبخ (dark glass, flame)

Core loop: see ticket → cook → bump. Glanceable from 2 meters, greasy
fingers: 48px+ targets, no hover-dependent UI.

### 2.1 KDS home (built)
Dark panel, day strip, three lanes, state edges, red-late frame, big bump
buttons. PC: lanes share the panel (built). Add: lane auto-scroll to
newest (AnimatedList insertion, no layout change), late-ticket pulse
(subtle opacity loop, respects reduced motion via TickerMode only —
  no setting yet, keep static red if motion is a concern; decided: static).

### 2.2 Menu — القائمة (station-grouped cards, new)
- Group headers per station (المشويات، الفرن…) with counts + نفد count.
- Item card: name, price pill, station tag, big availability switch row
  (متاح toggle, 48px). Search filters across groups; empty group hides.
- PC: two-column card grid under each station header; mobile: single
  column. Add/edit dialog (`DialogShell`): name, price, category dropdown,
  station dropdown, availability switch. Delete asks متأكد؟.
- Toggling availability writes through the same repo path as today
  (sync-safe); optimistic with rollback snackbar on failure.

## 3. Driver — الطريق (blue)

Core loop: next stop → advance → collect → settle. One thumb, sunlight
readable, glove-sized buttons (56px primary).

### 3.1 Driver home (built: hero + KPIs + queue)
Built: GPS nav — hero and every actionable card carry اتجه للعنوان, a
universal maps link (coordinates when stored, encoded address until then)
opened in the phone's maps app via url_launcher. No maps SDK, no keys, no
billing; unit-tested URI builder, loud snackbar when no maps app exists.
To do: route-order badge (المحطة 2 من 5) from queue position. PC: single
centered column (cap 720px, not 1160 — a driver console stays narrow).
Queue rows become `TimelineList` (rail + dot per state + compact card).
Keep: collection dialog, offline notice, empty state.

### 3.2 Collection dialog (both widths)
Amount field (autofocus, numeric), quick chips (المبلغ كامل, +بقشيش؟ —
  no, keep: exact / round-up), method toggle (كاش/فيزا), سجّل button.
Width 400, scrollable content; on 390px it fits by construction (pumped).

## 4. Manager — القيادة (emerald)

Core loop: morning review → intraday glance → close. Numbers first,
drill-down second.

### 4.1 Dashboard home (built: hero + KPIs + chart + alerts)
Add: alert rows navigate (tap low-stock → inventory, tap conflicts →
  conflicts) via push. PC: chart + recent orders side by side (built via
  ResponsiveRow); alerts + sync + branch in a second row (built).

### 4.2 Reports — التقارير
Hero (net sales, freshness tag) · KPI grid (orders, avg ticket, refunds,
cash/card split) · `ChartCard` hourly bars (built) + payments mix bars
(new, horizontal) · inventory/purchasing/cash KvPanels (built) · export
نزّل CSV. PC: KPIs in 4-across, charts side by side. Mobile stacked.

### 4.3 Branches — الفروع
Network hero (total sales, coverage tag) · branch cards: name, city, sales,
orders, collected, stock, pending + stale/missing tags. PC: card grid
3-across; mobile: stacked. Tap drills to a branch detail sheet (sales
trend mini-bars + last sync + pending list) — new, read-only.

### 4.4 Purchasing — المشتريات
Supplier cards/table + order pipeline (ordered → received/cancelled) ·
receive flow (built) · pay flow (built). PC: suppliers left (320px),
orders right. Mobile: tabs (الموردون / الأوامر) — new `SegmentedControl`
mirroring POS pattern.

### 4.5 Inventory — المخزون
Stock hero (on-hand, low count, pending moves) · ledger table (PC) /
movement feed (mobile, `FeedRow`: item + delta colored + reason + time) ·
adjust/count dialog (built patterns). Keep table on PC, feed on mobile —
  same data, purpose-fit.

### 4.6 Team — الفريق
Member rows (avatar initial, name, email, role dropdown) · invite CTA
(pushes console-add instructions — no in-app signup by design) · self-row
locked with أنت tag. PC: table; mobile: cards. Role changes confirm via
snackbar with reason on failure (built).

## 5. Dev — الغرفة (purple)

Core loop: health glance → diagnose → fix. Dense, mono accents, no
hand-holding.

### 5.1 System console (built: hero + KPIs + tools + log)
Keep. Add: tapping a KPI jumps to sync center (push). PC: hero + log
side by side (log is wide content — mono deserves width).

### 5.2 Sync center — المزامنة
Health hero (pending/retry/conflict counts) · policy explainer (built,
collapsible on mobile — new: `ExpansionTile`-style using existing
primitives? build `Collapsible` block) · outbox table (PC, built) /
operation cards (mobile, new: op id + entity + error + retry button) ·
print queue (built). Retry/ack actions per row (manager-gated ack kept).

### 5.3 Conflicts — التعارضات
Strategy explainer (collapsible) · conflict cards (both widths — cards
read better than the matrix on PC too; keep matrix on ≥900px as today,
cards below). Resolve/requeue per card (built logic).

### 5.4 Database — قاعدة البيانات
Store counts grid (built) · mirror counts · prune action with confirm
(built). PC: counts 4-across; add per-store drill sheet (top rows sample,
read-only) — new, helps "numbers look wrong" sessions.

### 5.5 Settings — الإعدادات
Grouped sections (built) · update panel with channel/severity/rollout
steppers (built logic, restyle rows as `FeedRow`) · feature flags list
with switches (built) · diagnostics. PC: two-column section grid;
mobile: stacked. Version row shows latest published tag (built).

### 5.6 Updates flow (prompt + controller UI)
Prompt sheet: version hero, notes, download progress bar, later/update
actions (built). Blocking mode full-screen on mobile, centered 480px
dialog on PC (new distinction).

## 6. Shell (both widths)

- Top bar on EVERY screen, both widths: screen title + sync chip.
  Nothing else — the search and notifications buttons were dead controls
  and the branch pill was a hardcoded label with a fake dropdown arrow,
  so all three go. Per-screen search lives in `ListToolbar` where it can
  actually filter something.
- Mobile: bottom bar (role tabs, active pill in role accent — new),
  المزيد grid (built).
- PC (≥900): sidebar with grouped nav (built) + active rail in role
  accent (new). Sidebar footer: user chip + اخرج.
- Sign-in: centered 420px card both widths (built: أهلاً بيك), demo-mode
  hint, error inline. Splash: app mark + name (built).

## 7. Element inventory (proof matrix)

Dialogs/sheets (pump 390 + 1440): collection, customer add/edit, menu
item add/edit, stock adjust/count, pay supplier, close session, confirm
(متأكد؟ generic), update prompt, branch detail, store drill. Snackbars:
success/error/undo patterns stay. Empty states: icon + heading + benefit
+ single CTA (audit each). Loading: skeletons matching layout for
dashboards/lists (new `Skeleton` block), spinners only for actions.
Charts: MiniBars keep 160px height, x-labels every third (built); mix
bars new. Tables: RmsTable everywhere (built). Tooltips: refresh/export
icon buttons keep text tooltips.

## 8. Build order

0. Desktop sweep green (pending CI on 7fc0b20).
1. New blocks: DialogShell, ListToolbar, SegmentedControl, Collapsible,
   ChartCard(mix bars), TimelineList, Skeleton.
2. Shell accents + sign-in card.
3. Cashier: POS PC rails + mobile tender row + customers + session side.
4. Chef: station menu.
5. Driver: PC column cap + timeline + collection dialog.
6. Manager: reports mix bars + branch detail + purchasing tabs/columns +
   inventory feed + team cards.
7. Dev: sync cards/collapsible + conflicts cards + db drill + settings
   grid + update prompt PC dialog.
8. Element audit + release.
