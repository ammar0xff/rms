import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/app.dart';
import 'package:rms/src/core/config/firebase_config.dart';
import 'package:rms/src/core/di/app_services.dart';
import 'package:rms/src/data/repositories/branch_repository.dart';
import 'package:rms/src/data/repositories/demo_auth_repository.dart';
import 'package:rms/src/domain/models/branch.dart';

final _now = DateTime(2026, 10, 13, 15);

BranchModel _branch(String id, String name, String code) => BranchModel(
      id: id,
      name: name,
      code: code,
      city: 'القاهرة',
      timezone: 'Africa/Cairo',
      openedAt: DateTime(2020, 1, 1),
    );

/// Serves one fixed consolidated snapshot so the dashboard card can be exercised
/// without a full local store.
class _FakeBranches implements BranchRepository {
  _FakeBranches(this.snapshot);

  final ConsolidationSnapshot snapshot;

  @override
  Future<ConsolidationSnapshot> consolidate({DateTime? now}) async => snapshot;

  @override
  Future<BranchModel?> activeBranch() async => snapshot.localBranch?.branch;

  @override
  Future<List<BranchModel>> listBranches() async =>
      [for (final b in snapshot.branches) b.branch];

  @override
  Future<void> setActiveBranch(String branchId) async {}

  @override
  Future<void> cacheBranches(
    List<BranchModel> branches, {
    bool replace = true,
  }) async {}

  @override
  Future<List<BranchRollup>> cachedAggregates() async => const [];

  @override
  Future<void> cacheAggregate(BranchRollup rollup) async {}
}

ConsolidationSnapshot _snapshot() => ConsolidationSnapshot.from(
      generatedAt: _now,
      branches: [
        _branch('BR-01', 'بوابة الشمال', 'NS-01'),
        _branch('BR-02', 'فرع المعادي', 'MD-02'),
      ],
      aggregates: [
        BranchRollup(
          branchId: 'BR-02',
          orders: 20,
          sales: 200,
          collected: 190,
          inventoryUnits: 8,
          asOf: _now,
        ),
      ],
      local: BranchRollup(
        branchId: 'BR-01',
        orders: 12,
        sales: 500,
        collected: 480,
        inventoryUnits: 30,
        asOf: _now,
      ),
    );

Future<void> _signIn(WidgetTester tester, AppServices services) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(RmsApp(services: services));
  await tester.pumpAndSettle();

  await tester.enterText(find.byType(TextField).at(0), 'ammar@rms.dev');
  await tester.enterText(find.byType(TextField).at(1), 'secret');
  await tester.tap(find.text('دخول'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('dashboard branch card shows the consolidated network totals',
      (tester) async {
    await _signIn(
      tester,
      AppServices(
        config: const FirebaseConfig.empty(),
        auth: DemoAuthRepository(),
        firebaseReady: false,
        branches: _FakeBranches(_snapshot()),
      ),
    );

    // Sourced from the consolidation read-model, not from hardcoded figures.
    expect(find.textContaining('NS-01'), findsOneWidget);
    expect(find.text('مبيعات الشبكة'), findsOneWidget);
    expect(find.text('700.00 ج.م'), findsOneWidget);
    expect(find.text('تغطية الفروع'), findsOneWidget);
    expect(find.text('2 من 2'), findsOneWidget);
  });

  testWidgets('dashboard branch card degrades when no branch store exists',
      (tester) async {
    await _signIn(
      tester,
      AppServices(
        config: const FirebaseConfig.empty(),
        auth: DemoAuthRepository(),
        firebaseReady: false,
      ),
    );

    expect(find.text('توحيد الفروع غير متاح في هذه الجلسة.'), findsOneWidget);
  });
}
