# RMS — Restaurant Management System (Flutter, offline-first)

## Repo / remote
- GitHub: https://github.com/ammar0xff/rms — PUBLIC, branch `main`.
- Design references used well: styles.refero.design (Refero Styles), uupm.cc (UI/UX Pro Max),
  21st.dev + framer.com via design-mcp. Rules documented in `docs/DESIGN.md` (each rule cites its source).
- Deploy gotcha: after deploy, GitHub Pages CDN may briefly serve the previous `main.dart.js`
  (no version query in flutter_bootstrap.js load). Verify with `curl` + grep for a new-only string;
  it self-heals within ~a minute.
- Local repo root: `/home/ammar/PIE` (folder name differs from repo name).
- Git identity is not global; commits use inline `-c user.name="ammar0xff" -c user.email="ammar0xff@users.noreply.github.com"`.
- `gh` at `/home/ammar/.local/bin/gh`, authenticated (scopes: gist, read:org, repo, workflow).

## Environment limits
- Flutter SDK is NOT installed locally (Garuda/Arch). No flutter pub get/analyze/test/run locally.
- All compilation/verification happens on GitHub Actions. Push, then check with `gh run watch <id>`.

## CI/CD (works)
- `.github/workflows/ci.yml`: Flutter stable, `flutter analyze --no-fatal-infos` (fails on errors/warnings) + `flutter test`.
- `.github/workflows/deploy-pages.yml`: generates web platform (`flutter create . --platforms web --project-name rms`),
  builds `flutter build web --release --base-href "/<repo name>/"`, deploys via actions/deploy-pages.
- Pages enabled (build_type=workflow). Live: https://ammar0xff.github.io/rms/ (HTTP 200 verified).

## App structure
- Entry: `lib/main.dart` -> `lib/src/app.dart` (themed MaterialApp) -> `AppShell` (`lib/src/core/widgets/app_shell.dart`).
- Theme tokens: `lib/src/core/theme/{app_colors,app_spacing,app_text,app_theme}.dart`.
- Core widgets: `lib/src/core/widgets/` (app_shell, surface_card, status, buttons, rms_table, charts, stat_card, primitives, page, sync_chip).
- State: `lib/src/core/state/sync_monitor.dart` (singleton SyncMonitor.instance).
- Mock data: `lib/src/data/mock/mock_data.dart`.
- Screens (12): dashboard, pos, kitchen, delivery, accounting, menu, inventory, customers, reports, sync, conflicts, settings.
- Phase-0 domain scaffolding: `lib/src/data/local/outbox/`, `lib/src/data/sync/`, `lib/src/domain/`.
- Docs: `docs/` (PRD pdf/xmind/png, architecture.md, offline-capability-matrix.md).

## Design direction (locked)
Dense modern dark dashboard (Vercel/Linear). 3-tier elevation, 1px borders, NO glass/gradient/glow,
tabular numerals, tiny type, dot statuses, warm amber accent #F5A524.

## Gotchas learned
- GridRow (page.dart) wraps its Row in IntrinsicHeight; Row+CrossAxisAlignment.stretch inside a vertical
  SingleChildScrollView causes "BoxConstraints forces an infinite height".
- Dense table/row content uses Flexible + TextOverflow.ellipsis to avoid RenderFlex overflows.
- Widget test renders at desktop viewport (1600x1000); sidebar appears >= 900px width.
- Newer Flutter APIs used: Color.withValues(alpha:), WidgetStateProperty, MediaQuery.sizeOf.
- flutter analyze counts style infos as exit 1 -> CI uses --no-fatal-infos.

## Current state
Design pass applied on top of the 12 screens and shipped: `00df9d7` (design) + `ec8582b` (cleanup).
Changes: AppText tabular/cv02/cv03/cv11 features everywhere; MiniBars gridlines; dashboard chart
axis/peak computed from data (was hardcoded 1.2k/800/400/0 against max 18 — fixed); ghost/secondary
button borders use control token #1E1E22; `docs/DESIGN.md` added. CI + deploy green; live site verified
showing new 20/10/5/0 axis, 12 hour labels, "Peak hour 5:00 PM". `.playwright-mcp/` gitignored.
Next: real local persistence/outbox, or refine screens against the PRD.
