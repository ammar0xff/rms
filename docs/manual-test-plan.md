# Manual test plan — hardware only

Automated tests (663) cover units and fakes. These need a real device because
they cross process, network, timing, or human boundaries CI cannot reach.

Targets the v0.24.0 release (buildNumber 20). Run sections in order — 0 and 0b
prove the shape, 0c proves the new work, 1 proves the update path, 5 proves
display.

## 0. Roles — one APK, four apps (do first)

Sign in as each account in turn. Shared-device sign-out (المزيد → اخرج)
between each; confirm the previous operator's screens are gone.

- [ ] **Driver** (`driver.*@`): bottom bar is التوصيل + المزيد only. No POS,
  no dashboard anywhere — bar, grid, and (wide) sidebar.
- [ ] **Cashier** (`cashier.*@`): lands on POS. No delivery.
- [ ] **Manager**: full bar (لوحة + الصالة 4 tabs), all 17 entries in المزيد
  (16 shared + النظام).
- [ ] **Developer**: system tabs; النظام > الفريق lists users; assign a role
  to another account (never your own — refused); sign in as that account and
  confirm its app changed.
- [ ] **Unknown role** (fresh Firebase user with no document): cashier app,
  never locked out, never promoted.
- [ ] **Ack gating.** With stuck work: cashier sees يتطلب الإقرار مديرًا
  (no button); manager sees إقرار and it works.

## 0b. Data surfaces (post-audit additions)

- [ ] **Customers.** Add a customer (name+phone): appears in the table as
  محلي, syncs to `customers/` in Firestore, flips to مُزامَن. Empty state
  before the first one — never fixture rows.
- [ ] **Menu toggle.** Flip an item's availability: change syncs (check the
  outbox row `upsertMenuItem`), survives a cache refresh.
- [ ] **Dashboard alerts are real.** Put an item under its reorder point:
  appears in التنبيهات; resolve it: green row, no alert.
- [ ] **Database screen (developer).** Counts match console collections;
  prune deletes only synced outbox rows (pending count untouched).
- [ ] **Mirror convergence.** After a full drain, every touched entity has a
  same-id document in its mirror collection carrying server identity.

## 0c. New in v0.24.0

Each case names the screen. On a PC the sidebar appears instead of the bottom
bar; run each at both widths once.

- [ ] **Tables (manager).** الصالة lists the seeded 18 tables with zone chips.
  A vacant table offers تسكين → the sheet seats it (متسكين). مطلوب الشيك moves
  it to مطلوب الشيك; تحرير بعد الدفع frees it and writes an audit row.
- [ ] **Trips (driver).** سجل الرحلات shows today's KPIs. Flip to المرتجعات —
  a delivered stop disappears, a failed one stays. Search by order number
  narrows the list.
- [ ] **Receipt (driver).** البون on a job card lists the real lines from the
  matching order with modifiers and notes; the total matches what was
  collected. For a delivery with no order on the device, it shows the address
  and amount only — no invented lines.
- [ ] **Custody (driver).** عهدتي وتسليمها shows collected cash minus per-stop
  receipts, with a manual handover code. خلّص التسوية settles it; توريد on the
  driver row opens the batch sheet (فرع + مبلغ + مستلم) and the outbox gains
  `settleDriverBatch`.
- [ ] **Assignment (manager).** In المتابعة, تعيين طيار lists drivers with the
  suggested one marked; reassigning an assigned stop requires a reason (the
  outbox payload carries `reason`). Assigning a stale stop shows a conflict and
  lands in التعارضات, never silently overwriting.
- [ ] **Approvals (manager).** A cashier's خصم/مصروف/إلغاء request lands in
  الطلبات with no money moved. Reject demands a reason. Approve with a PIN set
  → wrong PIN refuses, right PIN decides. Voiding an invoice keeps the row
  (audit) and drops it from today's totals.
- [ ] **Count sheet (manager).** In المحاسبة → جلسة النقدية, عِدّ واقفل الجلسة
  opens the denomination steppers (200/100/50/20/10/5). Stepping a value moves
  the counted field and the variance label together (مطابقة تامة / فيه عجز /
  فيه زيادة); typing a number directly still works. Closing posts the counted
  cash and the session flips to مقفولة with the difference shown.
- [ ] **Transfers (manager).** Under شبكة الفروع → تحويلات المخزون, طلب إمداد
  creates a pending row. Walk اعتماد → شحن, then استلام on the destination
  branch: stock posts exactly once (press twice — no double receipt). Cancel
  stays available until the transfer is received, then the row is closed.
- [ ] **Tender (cashier).** الكيباد types straight into المبلغ المدفوع; back
  space deletes; بالظبط and the round-bill chips fill it. Try a second decimal
  point — rejected.
- [ ] **Modifiers (cashier).** An item with an الإضافات group opens the choice
  sheet; the cart line carries the chosen names; the ticket prints them.
- [ ] **Permissions (manager).** النظام > الفريق → the tune icon on a member
  opens the matrix; unchecking تعديل القائمة takes effect for that cashier
  immediately (snackbar denial, no edit). Unchecking everything for the
  cashier leaves them able to take orders.
- [ ] **Snooze (anyone).** Dismiss an optional update prompt, then kill and
  reopen the app: the prompt stays hidden. It returns after 8 hours, not at the
  next start. Dismissing never touches a mandatory one. With unsynced work the
  guard banner still blocks any install.

## 1. Update flow end-to-end (Phase 4)

Setup: install the release APK, sign in, take the app through each case.

- [ ] **Clean update.** Publish a recommended release. Prompt appears as a
  dismissible dialog. Accept → progress bar moves → installer intent fires →
  completed screen → dismissal returns to the app.
- [ ] **AC-35 refusal.** Queue offline work (airplane mode, take an order),
  then accept an update. Install must NOT start; the prompt explains unsynced
  work. Reconnect, let it sync, accept again → installs.
- [ ] **Mandatory blocks.** Publish severity mandatory. Full-screen prompt, no
  dismiss, back gesture trapped. Install to clear it.
- [ ] **Failed retry.** (Force by airplane-moding mid-download.) Failed screen
  offers لاحقًا and إعادة المحاولة. لاحقًا returns to the app; the failure
  is reachable again (not suppressed). Retry re-runs and can succeed.
- [ ] **Deferral scope.** Defer an optional release, then publish a mandatory
  one in the same session. The mandatory screen MUST still appear.
- [ ] **Stale prompt.** Open the prompt (ready), take an order, then press
  install. The fresh backlog must stop it even though the prompt said ready.
- [ ] **Pulled release.** Publish, then delete the manifest doc while the
  pointer names it. Next check clears the offer (withdrawn), no install.
- [ ] **Version honesty.** Settings → الإصدار الحالي matches the APK's
  versionName; build matches versionCode (check via package info).

## 2. Sync behavior

- [ ] **Offline queue + reconnect.** Airplane mode: POS order, delivery
  collect, payment. Each queues visibly (sync center shows real rows, counts
  move). Reconnect → all drain, statuses flip, counts zero.
- [ ] **Retry storm check.** Kill network mid-drain repeatedly. Attempts climb
  with visible backoff gaps (not instant retries); after 8 failures the entry
  parks as requiresUserAction on the conflicts screen — never silent.
- [ ] **No double money.** Double-tap collect / finalize twice fast. Exactly
  one collection, one settle command; second attempt reports already-recorded.
- [ ] **Order numbers.** Two rapid orders get distinct ORD-xxxxx in order; a
  crash-recovery replay reuses its number (no gaps beyond the crash window).

## 3. Money agreement

- [ ] **Taxed totals agree.** Order with tax: cart total == charged payment ==
  order record == delivery amount == printed receipt. Check all four surfaces.
- [ ] **Double-tap submit.** Hammer إرسال للمطبخ twice. Exactly one order, one
- [ ] **Payable math.** Receive a purchase → supplier payable rises by exactly
  the total. Pay it in full → payable reads exactly 0.00 (no 0.0000004).
- [ ] **Cash close.** Counted == expected → variance exactly 0.00, not فرق 0.01.

## 4. State machines

  backward moves rejected with a snackbar; completed tickets never reappear;
  station filter resets to الكل when its station empties.
- [ ] **Delivery runs.** assigned → onRoute → delivered; reopening a delivered
  run refused. Collect-twice confirms only the first.
- [ ] **Tab switches keep the cart.** Build half a cart, visit more,
  come back: cart, search, category intact. Same for the menu/cart tabs.
- [ ] **Sign-in restore.** Kill and relaunch while signed in (Firebase mode):
  no sign-in flash; straight to the shell.

## 5. Display

- [ ] **Demo honesty.** Fresh install with no store: dashboard wears the
  demo banner, never مباشر on fabricated numbers.
- [ ] **Diagnostics.** Settings → تشخيص النظام shows the live log tail after
  forcing an error (e.g. airplane-mode sync); backend state reads distinct
  from never-configured.
  delivery, settings, sync center: no clipped text, no dead buttons, tables
  scroll sideways, dialogs fit with the keyboard up.

## 6. Release hygiene (each publish)

- [ ] APK signer fingerprint matches the pin in docs/release-setup.md.
- [ ] Published sha256 matches the downloaded file.
- [ ] `activeReleases/<platform>` points at the new release id.
- [ ] min-supported keeps stranded reporters eligible (devices that report an
  older version than they are, like the 0.8.0-reporting 0.10.0 build).
