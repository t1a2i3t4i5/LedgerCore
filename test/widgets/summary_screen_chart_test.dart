import 'package:drift/native.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/models/transaction.dart';
import 'package:ledger_app/providers/summary_provider.dart';
import 'package:ledger_app/screens/summary_screen.dart';
import 'package:ledger_app/widgets/category_pie_chart.dart';
import 'package:provider/provider.dart';

/// サマリー画面にグラフが組み込まれていることを、インメモリ DB 込みで確認する。
/// 実端末のファイルには触らない（database_test.dart と同じ方針）。
void main() {
  late AppDatabase db;

  // 画面が表示する月を実時刻から切り離す（seed と表示で月がずれないように）
  final fixedNow = DateTime(2026, 7, 15);

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> pumpSummary(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SummaryProvider(db, clock: () => fixedNow),
        child: const MaterialApp(home: Scaffold(body: SummaryScreen())),
      ),
    );
    // initState の postFrameCallback で fetch が走るので落ち着かせる
    await tester.pumpAndSettle();
  }

  testWidgets('取引があるとカテゴリ別セクションにドーナツグラフが出る',
      (tester) async {
    final cats = await db.getCategories();
    final memberId = (await db.getMembers()).first.id;

    for (final (i, cat) in cats.take(3).indexed) {
      await db.insertTransaction(TransactionRequest(
        userId: memberId,
        categoryId: cat.id,
        amount: (i + 1) * 1000,
        spentAt: DateTime(fixedNow.year, fixedNow.month, 5),
      ));
    }

    await pumpSummary(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(CategoryPieChart), findsOneWidget);
    expect(find.byType(PieChart), findsOneWidget);
  });

  testWidgets('取引ゼロの月ではグラフを描かず例外も出ない', (tester) async {
    await pumpSummary(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(CategoryPieChart), findsOneWidget);
    expect(find.byType(PieChart), findsNothing);
  });
}
