# Offline Capability Matrix

Maintained as a versioned policy (see `lib/src/domain/offline/offline_capability.dart`), not scattered screen checks.

| Feature | Offline capability | Required behavior |
| --- | --- | --- |
| POS | Full (approved basic ops) | Create/edit eligible orders from cached config |
| Menu | Cached read | Use last synchronized menu and pricing |
| Customers | Cached read / local creation | Sync new/updated records later |
| Cash payments | Local recording | Mark local + pending sync |
| External card payments | Integration-dependent | Never claim unverified success |
| Kitchen | Local queue | Process local orders, persist status |
| Printing | Conditional | Supported local integration only |
| Delivery assignment | Restricted | Cached or flag-permitted provisional auto-assign only |
| Driver updates | Queueable | Persist locally, sync later |
| Customer collection | Queueable w/ safeguards | Financial confirmation stays pending |
| Driver settlement | Restricted | Draft offline; final needs validation |
| Inventory | Conditional | Local movements, flag conflicts |
| Purchasing | Queueable | Raise/receive/cancel orders offline; stock posts and payable updates locally |
| Suppliers | Cached read / local creation | Record payments offline; sync new/updated records later; never overpay |
| Reports | Cached read (local read-model) | Compute from append-only stores; show freshness + pending sync |
| Branches / consolidation | Cached read (live + cached aggregates) | Device branch read live; other branches from last synced aggregate, mark stale/missing |
| User management | Online only | No offline permission changes |
| Refunds | Restricted | Online workflow unless authorized |
| Configuration | Cached read | Changes need authorized server workflow |
