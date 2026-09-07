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

  Future<void> pumpSummary(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 690);
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
}
