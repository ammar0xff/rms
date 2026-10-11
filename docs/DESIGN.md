# RMS — DESIGN.md

Source of truth for UI decisions. Every rule below traces to a concrete
reference so the app looks deliberate, not vibecoded.

## References used

| Source | What we took | Where |
| --- | --- | --- |
| **Refero Styles** (`styles.refero.design`) | Vercel/Linear-grade density: 3-tier elevation, 1px borders, tiny type scale, locked 20px section rhythm, hover `white/1.2%` | `lib/src/core/theme/` |
| Refero "Brex — single ember" | One restrained domain accent instead of the default indigo/purple | `AppColors.brand = #F5A524` |
| **UI/UX Pro Max** (`uupm.cc`) | Data-visualization honesty (axis computed from data, never faked), chart/type scale, UX-rule discipline | `_SalesCard`, `charts.dart` |
| **Framer** | Animation/motion restraint: 120–150ms micro-transitions only, no infinite/attention-seeking motion | `AnimatedContainer` durations |
| **21st.dev** | Production component anatomy: outlined ghost buttons, `w-px h-3` inline dividers, status = 5px dot + text (not badges) | `buttons.dart`, `status.dart` |

## Tokens

### Elevation (three tiers)
Color | Role
--- | ---
`#0A0A0C` | page base, sidebar
`#101012` | hero/content cards
`#0E0E10` | secondary/compact cards
`#0C0C0E` | sunken / table header rows

Borders: `#1A1A1E` strong · `#16161A` subtle · `#131315` faint · `#1E1E22` control (buttons, inputs). No glass, no gradients, no glow.

### Foreground
`#FAFAFA` fg · `#E4E4E7` bright · `#A1A1AA` secondary · `#71717A` muted · `#52525B` dim · `#3F3F46` ghost.

Status colors (one per meaning): emerald `#34D399` · red `#F87171` · amber `#FBBF24` · blue `#60A5FA`. Accent: `#F5A524`.

### Type scale
Sizes differ by role — nothing is 16px.

| Role | Size | Notes |
| --- | --- | --- |
| Hero KPI | 44px, w600, `-1.6` tracking | one per page |
| Secondary KPI | 20px, w600, `-0.4` tracking | max 3 per row |
| Page title / nav | 13px / 12.5px | sidebar 220px wide |
| Section heading | 12px w500 | `#A1A1AA` |
| Table header | 9.5px, w500, `+0.8` tracking, uppercase | distinct from cells |
| Table cell | 11.5px | primary col w500 |
| Dates / dim | 10.5px | near-invisible but present |

Every number uses `tabularFigures` + OpenType `cv02 cv03 cv11` (`AppText._num`).

### Spacing (locked rhythm)
- All section gaps: **20px** (`AppSpacing.section`). Card grid gap: **12px**.
- Page padding 24px, top bar 48px, sidebar 220px.

## Composition rules

1. **Hero KPI is full-width** — the most important number gets its own card (never the "4 equal stat cards" grid).
2. **Secondary KPIs are 3 compact cards**, value + delta on the same line.
3. **Chart is full-width** with supplementary stats *docked* in the footer (`border-t` + `w-px` dividers) — no orphaned stat pills.
4. **Table + aside** use `1fr / fixed` split, not 50/50.
5. Table typographic hierarchy: primary column w500, amounts semibold+colored, IDs/dates dimmed right-aligned `tabular-nums`.

## Behaviors (per UX guidelines)

- Empty/loading states render skeleton-style muted surfaces rather than empty cards.
- Status is always a dot → never colorful badges (one color per semantic).
- Motion is 120–150ms and only for hover/state change.
- Numbers never overflow: `Flexible` + ellipsis in dense rows.

## Anti-patterns consciously avoided

Equal-grid KPIs · glassmorphism/glow · gradient buttons · 16px body text ·
icon-in-stat-card · centered stat values · text-base defaults ·
hardcoded chart axis labels · stacked micro-bar with an invisible 4% segment.