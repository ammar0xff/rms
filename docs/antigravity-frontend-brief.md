# PIE — Restaurant Management System · Front-end build brief

Build the complete production front end for **PIE**, a mission-critical, offline-first
restaurant operations system for Egypt and the Gulf. Four role apps behind one sign-in.

**Read this first, because it changes what you do.** The existing front end was rejected as
mediocre. It was flat, uniformly dark, evenly weighted, and typographically lazy — every screen
had the same rhythm, so nothing felt designed. That is the failure to avoid. You are not
tidying it. You are designing it properly, and you are free to make every visual decision.

**Where you have freedom:** layout, composition, density, hierarchy, motion, illustration,
chart treatment, iconography, spatial rhythm, how dramatic the accent usage is, whether depth
comes from tone or light, how the data is arranged on screen.

**Where you do not:** the functional contract in §3. Every screen must be drawable from the
real data model, or it is not a screen — it is a picture.

---

## 1. THE PRODUCT AND ITS REALITIES

Four roles, one app:

- **Cashier** — sells, settles the drawer, closes the shift
- **Driver** — runs a delivery route, navigates, collects cash, returns custody
- **Manager** — watches the operation, approves spending, moves stock, reviews shifts
- **System Admin** — diagnostics, conflicts, updates, identity

A fifth role, the Kitchen Display System, has been **removed**. No kitchen screens, no station
columns, no "fire ticket" state.

### The environment is hostile, and the design must respect it

This is not a consumer app. It runs on cheap Android terminals and phones, in a shawarma shop
with steam and grease, under fluorescent light, at speed, often one-handed, sometimes with wet
hands. An operator is looking at this screen for eight hours.

Consequences you must design around:

- **Sunlight and glare.** Deep dark backgrounds survive washout. Mid-greys do not. Keep the
  canvas genuinely dark and keep the bright ink genuinely bright — the contrast range is doing
  work, not decoration.
- **One hand, thumb-first.** Primary actions sit within thumb reach. Nothing critical in a top
  corner on a phone.
- **Fat fingers.** Hit targets are 44×44 minimum even when the painted box is smaller.
- **Glanceable, not studious.** An operator reads state in under a second. If a number needs
  reading rather than recognising, the hierarchy is wrong.
- **It must work with no network.** Every action writes locally first. The interface must always
  be honest about what is local and what is reconciled — that distinction is the most important
  signal in the whole product.
- **Money.** Wrong numbers are the worst failure this software can have. Never invent a figure.

---

## 2. ART DIRECTION

**The system is dark, RTL-native Arabic, and information-dense.** Beyond that, design it.

**The single most important job:** make the *current operational state* unmistakable at a
glance. Not the total sales, not the branding — the state. Is this synced. Is this mine. Is this
mine and broken. Is this order ready to hand over. A glance must answer that.

### Typography — this is where the last attempt failed

Arabic UI typography is not a font swap. Treat it as a primary design problem.

- **Line height for Arabic is not Latin line height.** Arabic script sits differently: it needs
  more vertical room for diacritics and for the descenders and ascenders that don't exist in
  Latin. Set body copy at a generous 1.7–1.8. Do not inherit a Latin scale.
- **Choose the Arabic face deliberately.** Something with real Arabic drawing, not a Latin font
  with Arabic fallback. Consider IBM Plex Sans Arabic, Noto Sans Arabic, Rubik, Almarai, Cairo,
  Tajawal. Judge it on its Arabic, not its Latin.
- **Numerals are a separate face.** Order numbers, SKUs, till figures, quantities, timers, times
  and IDs should be tabular monospace — they are data, and data must not shift as it updates.
  Candidates: JetBrains Mono, Roboto Mono, IBM Plex Mono, Space Mono.
- **Numerals must stay LTR inside RTL text.** A negative delta or an `MM:SS` timer must not
  reorder. Isolate them.
- **Numerals get far less weight than words** and should not be the loudest thing on a card.
- **Decide your numeral system deliberately** and be consistent — Western Arabic (`0 1 2`) is
  normal in Egyptian business contexts; Eastern Arabic (`٠ ١ ٢`) reads as formal or regional.
  State your choice in a comment.
- **Build a real scale.** Display / heading / subheading / body / label / caption / mono-numeric.
  Most screens should use 3–4 of those, not 7. The last version used everything everywhere and
  nothing stood out.
- **Vary weight and size for hierarchy, not colour.** Using the accent colour to make things
  important is how a screen ends up with eleven competing highlights.

### Colour

Start from a deep, near-black canvas with a slightly cool cast, and build a **tonal ladder** —
a family of surface values from canvas through wells, cards, raised controls, to overlays. A
functional system needs maybe six surfaces. Define them and use them consistently; the ladder is
what makes an interface feel engineered rather than assembled.

**One accent per role**, and it should be genuinely used — the accent is how an operator knows
which app they're in at a glance, from across the room:

| Role | Direction |
|---|---|
| Cashier | warm amber — the till, heat, immediacy |
| Driver | sky blue — open road, transit, distance |
| Manager | emerald — money, growth, calm control |
| System Admin | violet — instrumentation, diagnostics, the machine |

Semantic colours must be *distinguishable at a glance and under stress*, and must never be
confusable with a role accent: pending, synced, conflict, offline, empty.

**Two rules that matter more than they sound.** A colour never appears without meaning — no
decorative tinting. And contrast: every piece of text must clear WCAG AA against the surface it
sits on, including the muted and caption steps, which is where these designs usually fail.

### Depth and light

Depth by tone is the reliable approach, but tone alone goes flat fast. Consider also: very tight
inner highlights on raised surfaces, a soft directional glow on *live* elements only, colour
bloom on the active state, real shadow reserved for things that genuinely float (modals, sticky
bars, dragged items). Whatever you choose, be consistent and restrained — the point is that
things which matter float and things that don't don't.

### Rhythm and density

- A strict 4px spacing base. Small gaps are 4–8px, section gaps 16–24px.
- Group by proximity and shared ground, not by every element having its own border and fill.
- Vary card density: a dense ledger and a single hero should not share a template.
- The screen should feel *composed* — a designer placed every element — not stacked.

### Motion

Restrained and purposeful: state changes, entering figures, list reordering, the update flow.
Fast (120–200ms), eased, never decorative. Respect `prefers-reduced-motion`.

### Language

**Arabic, Egyptian.** Colloquial for sentences, MSA for nouns. Operator-facing microcopy is short
and blunt — this is a working surface, not a marketing one. No English words in operator-facing
chrome. Get the numbers, currency and times right: `ج.م`, `١٢:٤٥ م`.

---

## 3. THE FUNCTIONAL CONTRACT — DO NOT VIOLATE

Every screen must be drawable from these fields. **Do not design a screen around a field that
does not exist, and never invent a metric.**

**Order** — order number, items (name, unit price, quantity, station, modifiers, note), channel
(hall / takeaway / delivery), subtotal, discount, service, tax, total, void flag + reason, created
offline, timestamp, sync status

**Delivery** — id, order ref, address, amount, state (waiting / assigned / on route / delivered /
failed / returned), assigned driver, failure reason, timestamps

**Collection** (driver cash custody) — driver, amount, method, collected time

**Driver** — name

**Table** — code, zone, capacity, state (vacant / occupied / bill requested), party size,
steward, current order ref, running total, seated-at

**Cash session** — opening float, opened-at, closed-at, counted cash, variance, open/closed

**Approval request** — kind (refund / discount / petty cash / void / adjustment), amount, reason,
order ref, requested-at, requested-by, decision note

**Stock movement** — item, delta, reason, at, reference

**Payment** — order ref, amount, method, created-at

**Menu item** — name, price, station, modifier groups, availability

**Customer** — name, phone

**Outbox entry** — entity, operation, status (pending / in progress / retryable failure /
conflict / synced), error text

**Release manifest** — version, severity, rollout percent, min supported, status

**Explicitly absent — do not design around these:** customer email, kitchen or preparation state,
GPS coordinates and live ETA, per-waiter attribution beyond the table's steward, supplier
ratings, payroll, photo attachments.

### Non-negotiables

1. **No fabricated data.** Every figure real or absent. An empty state says what is missing and
   how to create it — never fixture rows dressed as real.
2. **No dead controls.** Every button, chip and toggle does something. If it has no real action
   behind it, it does not appear.
3. **Sync state is always visible** on anything that can be pending, conflicted or offline.
4. **Dark only.** No light theme.
5. **RTL-native**, not a mirrored LTR layout. Navigation and identity pin right; the working
   canvas reads right-to-left naturally.
6. **44×44 minimum hit targets**, even when the painted element is smaller.
7. **Never destructive by default.** Void, cancel and settle actions are explicit, and anything
   irreversible is confirmed.

---

## 4. THE SCREENS

Every screen below, complete and wired, at realistic density with realistic content. Mobile at
**390–780px**. Desktop variants at **1440–2560px** are genuinely different layouts — docked
panels and persistent rails, not the phone layout stretched.

### Cashier

1. **Point of sale** (mobile + desktop) — service mode (hall / named table / takeaway /
   delivery); category rail with live counts; product matrix; **docked receipt panel on the left
   on desktop**; sticky running total on mobile; the fast path to tender visible at all times
2. **Item customisation** (mobile) — required single-choice, optional multi-choice priced
   options, allergens, kitchen note
3. **Checkout** (mobile) — bill breakdown, numeric keypad, quick-tender chips, cash vs card,
   receipt path
4. **Tables floor** (mobile + desktop) — occupancy summary, status pills with counts, table cards
   with code / state / party / steward / elapsed / running bill, per-state action
5. **Shift board** (mobile) — shift state and elapsed, drawer float vs opening float, live
   ticket rail filterable by channel
6. **Cash count and Z-close** (mobile + desktop) — denomination steppers, counted vs expected,
   surplus or shortage stated plainly
7. **Drawer settlement** (mobile)
8. **Invoice archive** (mobile + desktop) — filterable, receipt viewer, reprint, void via
   approval

### Driver

9. **Active trip** (mobile) — trip header, four-phase progress, numbered stops with the current
   one expanded, per-stop actions, start-route call to action
10. **Navigation** (mobile) — next turn, collection reminder, arrived / failed, local GPS log note
11. **Failed delivery and return** (mobile) — reason capture, then the return leg
12. **Receipt** (mobile) — lines, modifiers, notes, totals, landmark
13. **Custody settlement** (mobile) — collected minus per stop, handover code, batch hand-over
14. **Delivery log** (mobile)
15. **Fleet overview** (mobile)

### Manager

16. **Command dashboard** (mobile) — shift state, net sales hero, KPI grid, **sales channel
    breakdown**, hourly volume with the peak marked, alerts that are real thresholds
17. **Approvals centre** (mobile) — typed requests, amount hero, reason, age, PIN-gated approve,
    reject with reason
18. **PIN and delegation** (mobile)
19. **Cross-branch triage** (mobile + desktop)
20. **Branch network and stock transfer** (mobile)
21. **Inventory and movements** (mobile, two screens) — reorder points, movement ledger, and a
    stock count that flags a stale count rather than overwriting
22. **Team and permissions** (mobile) — users, roles, shifts, per-user permission matrix

### System

23. **Diagnostics and outbox inspector** (mobile) — engine status, queue filterable by status with
    per-entry errors, node id
24. **Safe update gateway** (mobile) — unsynced-work guard, in-flight download, failure and retry
25. **Conflict resolution** (mobile)
26. **Identity and settings** (mobile)

---

## 5. HOW THE WORK WILL BE JUDGED

1. **Does it look designed?** Composition, hierarchy and restraint — or is every screen the
   same template?
2. **Is the Arabic typography right?** Generous leading, a real Arabic face, data in mono,
   numerals isolated. This is the most common failure and the most visible.
3. **Is state unmistakable at a glance?** Across a shop, in a second.
4. **Does the density serve a real shift?** Dense, not airy — but legible.
5. **Is every number real?** A POS that shows invented totals is a safety problem, not a
   cosmetic one.
6. **Is every control live?** Or is this a set of pictures?
7. **Does contrast actually pass**, including muted and caption text?
8. **Does it hold up in Arabic**, with correct mirroring, punctuation and numeral handling?
