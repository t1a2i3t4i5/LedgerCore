import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/models/transaction.dart';
import 'package:ledger_app/providers/summary_provider.dart';
import 'package:ledger_app/screens/summary_screen.dart';
import 'package:ledger_app/widgets/monthly_summary_chips.dart';
import 'package:ledger_app/widgets/settlement_summary_card.dart';
import 'package:provider/provider.dart';

import '../seed.dart';

/// ホームが月表示だけに絞られていることを、実際の画面で確認する。
void main() {
  late AppDatabase db;
  final fixedNow = DateTime(2026, 7, 15);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedMembers(db);
  });
  tearDown(() async => db.close());

  Future<void> seed(DateTime spentAt, double amount) async {
    await db.insertTransaction(
      TransactionInput(
        memberId: (await db.getMembers()).first.id,
        categoryId: (await db.getCategories()).first.id,
        amount: amount,
        spentAt: spentAt,
      ),
    );
  }

  Future<void> pumpSummary(
    WidgetTester tester, {
    Size size = const Size(360, 690),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SummaryProvider(db, clock: () => fixedNow),
        child: const MaterialApp(home: Scaffold(body: SummaryScreen())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('期間タブを出さず、表示月の集計だけを描く', (tester) async {
    await seed(DateTime(2025, 7, 5), 250);
    await seed(DateTime(2026, 6, 5), 300);
    await seed(DateTime(2026, 7, 5), 700);

    await pumpSummary(tester);

    expect(find.byType(SegmentedButton<SummaryPeriod>), findsNothing);
    expect(find.text('月'), findsNothing);
    expect(find.text('年'), findsNothing);
    expect(find.text('全期間'), findsNothing);
    expect(find.text('2026年7月'), findsOneWidget);
    expect(find.text('¥700'), findsWidgets);
    expect(find.byType(MonthlySummaryChips), findsOneWidget);
    expect(find.byType(SettlementSummaryCard), findsOneWidget);
    expect(find.text('カテゴリ別'), findsOneWidget);
    expect(find.text('メンバー別'), findsOneWidget);
  });

  testWidgets('取引ゼロで中身が短くても引っ張って再取得できる', (tester) async {
    await pumpSummary(tester);
    expect(find.text('¥0'), findsOneWidget);

    await seed(DateTime(2026, 7, 5), 700);
    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    expect(find.text('¥700'), findsWidgets);
  });

  testWidgets('狭い画面でも2人のメンバー別をスクロール前に表示する', (tester) async {
    await db.customStatement('DELETE FROM members');
    final members = await seedMembers(db, const ['たいち', 'みく']);
    final categories = (await db.getCategories()).take(4).toList();
    for (final (index, category) in categories.indexed) {
      await db.insertTransaction(
        TransactionInput(
          memberId: members[index ~/ 2].id,
          categoryId: category.id,
          amount: (index + 1) * 1000,
          spentAt: DateTime(2026, 7, 5),
        ),
      );
    }

    // 添付画面でナビゲーションバーより上に使える高さに合わせる。
    await pumpSummary(tester, size: const Size(320, 663));

    final viewportBottom = tester.getRect(find.byType(ListView)).bottom;
    expect(
      tester.getCenter(find.text('カテゴリ別')).dy,
      lessThan(tester.getCenter(find.text('メンバー別')).dy),
    );
    expect(
      tester.getCenter(find.text('たいち')).dy,
      tester.getCenter(find.text('みく')).dy,
    );
    expect(tester.takeException(), isNull);
    for (final label in ['メンバー別', 'たいち', 'みく', '¥3,000', '¥7,000']) {
      final rect = tester.getRect(find.text(label).last);
      expect(rect.top, greaterThanOrEqualTo(0), reason: '$label が上端の外にある');
      expect(
        rect.bottom,
        lessThanOrEqualTo(viewportBottom),
        reason: '$label がスクロール前の表示範囲に収まっていない',
      );
    }
  });
}
