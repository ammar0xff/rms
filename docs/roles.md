# Roles — one APK, five apps

The signed-in account is the key to what is displayed. Same theme everywhere;
different navigation, different landing screen, different reach.

## The roles

| Role | Demo email | Tabs | Sees |
|---|---|---|---|
| Driver | `driver.*@` | التوصيل + المزيد | deliveries, sync center, settings |
| Cashier | `cashier.*@` (default) | الوردية + البيع + المزيد | shift board, POS, dashboard, menu, customers, sync, settings |
| Chef | `chef.*@` | المطبخ + القائمة + المزيد | kitchen (+day strip), menu, dashboard, sync, settings |
| Manager | anything else | full bar | everything, incl. team |
| Developer | `dev.*@`, `developer.*@` | النظام + المزامنة + المزيد | system board, everything, incl. team + database tools |

Anything not listed for a role is unreachable — bottom bar, More grid, and
(wide screens) the filtered sidebar all enforce the same sets. The install
action itself is not role-gated (AC-35 governs it); the stuck-work
acknowledgement is (manager/developer only, with a "requires manager" tag for
everyone else).

## Where roles come from

- **Firebase mode:** `users/{uid}` document, `role` field. Missing or
  unreadable → cashier. The synchronous `currentUser` carries the last
  resolved role so UI gates never see a stale default mid-session.
- **Demo mode:** the email convention above; anything else is a manager so
  demo stays fully explorable.

## Developer database tools

النظام > قاعدة البيانات (developer only): per-store local counts, Firestore
mirror counts, and pruning of acknowledged outbox rows (synced only — never
work). The screen an operator opens when "the numbers look wrong".

## Team management

`النظام > الفريق` (manager/developer): lists `users/{uid}`, assigns roles via
dropdown. Nobody can change their own role. The first account has no document
yet, so it is created directly in the console:

```
users/{uid} = { email: "owner@…", displayName: "…", role: "developer" }
```

Get the uid from Firebase console → Authentication after the first sign-in
attempt (it fails closed, which is expected pre-document).

## Firestore rules

`firestore.rules` in the repo root is the reviewed source; apply it in the
console (Firestore Database > Rules). Summary:

- Everything requires sign-in. No public reads.
- `users/{uid}`: read own; list/read-any and writes need manager/developer.
- `sync_operations/{id}`: signed-in read/write (the sync engine path).
- `counters/{id}`: deny all (clients must never mint order numbers; the Admin
  SDK bypasses rules for publishing).
- `releases/{id}`, `activeReleases/{id}`: signed-in read, deny write
  (transition only — the app tracks GitHub Releases now).

Shared devices sign out from المزيد → خروج. Cached screens clear on every
account change, so the next operator never sees the previous one's state.
