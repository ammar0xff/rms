# Manual test plan — hardware only

Automated tests (507) cover units and fakes. These need a real device because
they cross process, network, timing, or human boundaries CI cannot reach.

## 0. Roles — one APK, five apps (do first)

Sign in as each account in turn. Shared-device sign-out (المزيد → اخرج)
between each; confirm the previous operator's screens are gone.

- [ ] **Driver** (`driver.*@`): bottom bar is التوصيل + المزيد only. No POS,
  no kitchen, no dashboard anywhere — bar, grid, and (wide) sidebar.
- [ ] **Cashier** (`cashier.*@`): lands on POS. No kitchen, no delivery.
- [ ] **Chef** (`chef.*@`): lands on kitchen. No POS, no delivery.
- [ ] **Manager**: full bar, all 14 entries in المزيد.
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
  kitchen dispatch, one delivery.
- [ ] **Payable math.** Receive a purchase → supplier payable rises by exactly
  the total. Pay it in full → payable reads exactly 0.00 (no 0.0000004).
- [ ] **Cash close.** Counted == expected → variance exactly 0.00, not فرق 0.01.

## 4. State machines

- [ ] **Kitchen lanes.** queued → preparing → ready → completed advances;
  backward moves rejected with a snackbar; completed tickets never reappear;
  station filter resets to الكل when its station empties.
- [ ] **Delivery runs.** assigned → onRoute → delivered; reopening a delivered
  run refused. Collect-twice confirms only the first.
- [ ] **Tab switches keep the cart.** Build half a cart, visit kitchen/more,
  come back: cart, search, category intact. Same for the menu/cart tabs.
- [ ] **Sign-in restore.** Kill and relaunch while signed in (Firebase mode):
  no sign-in flash; straight to the shell.

## 5. Display

- [ ] **Demo honesty.** Fresh install with no store: dashboard wears the
  demo banner, never مباشر on fabricated numbers.
- [ ] **Diagnostics.** Settings → تشخيص النظام shows the live log tail after
  forcing an error (e.g. airplane-mode sync); backend state reads distinct
  from never-configured.
- [ ] **Phone sweep.** 360px-wide pass over POS, dashboard, kitchen lanes,
  delivery, settings, sync center: no clipped text, no dead buttons, tables
  scroll sideways, dialogs fit with the keyboard up.

## 6. Release hygiene (each publish)

- [ ] APK signer fingerprint matches the pin in docs/release-setup.md.
- [ ] Published sha256 matches the downloaded file.
- [ ] `activeReleases/<platform>` points at the new release id.
- [ ] min-supported keeps stranded reporters eligible (devices that report an
  older version than they are, like the 0.8.0-reporting 0.10.0 build).
