import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/models/transaction.dart';
import 'package:ledger_app/providers/summary_provider.dart';

import 'seed.dart';

void main() {
  late AppDatabase db;
  late SummaryProvider provider;

  final fixedNow = DateTime(2026, 7, 15);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    provider = SummaryProvider(db, clock: () => fixedNow);
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

  group('前月との比較', () {
    for (final (year, month) in [(2026, 1), (2024, 3)]) {
      test('$year年$month月と前月を半開区間で取得する', () async {
        final start = DateTime(year, month);
        final previousStart = DateTime(year, month - 1);
        await seed(previousStart.subtract(const Duration(seconds: 1)), 9000);
        await seed(previousStart, 300);
        await seed(start.subtract(const Duration(seconds: 1)), 700);
        await seed(start, 400);
        await seed(
          DateTime(year, month + 1).subtract(const Duration(seconds: 1)),
          720,
        );
        await seed(DateTime(year, month + 1), 8000);

        await provider.goToMonth(year, month);

        expect(provider.error, isNull);
        expect(provider.summary!.year, year);
        expect(provider.summary!.month, month);
        expect(provider.summary!.total, 1120);
        expect(provider.summary!.transactionCount, 2);
        expect(provider.comparison!.previousTotal, 1000);
        expect(provider.comparison!.amountChange, 120);
        expect(provider.split!.total, 1120);
      });
    }

    test('再取得で当月の件数と前月の編集・削除を反映する', () async {
      await seed(DateTime(2026, 6, 15), 1000);
      await seed(DateTime(2026, 7, 15), 1120);
      await provider.fetch();
      expect(provider.summary!.transactionCount, 1);
      expect(provider.comparison!.amountChange, 120);

      final previous = (await db.getTransactionsByMonth(2026, 6)).single;
      await db.updateTransaction(
        previous.id,
        TransactionInput(
          memberId: previous.memberId,
          categoryId: previous.categoryId,
          amount: 2000,
          spentAt: previous.spentAt,
        ),
      );
      await seed(DateTime(2026, 7, 20), 880);
      await provider.fetch();
      expect(provider.summary!.transactionCount, 2);
      expect(provider.comparison!.previousTotal, 2000);
      expect(provider.comparison!.amountChange, 0);

      await db.deleteTransaction(previous.id);
      await provider.fetch();
      expect(provider.comparison!.previousTotal, 0);
      expect(provider.comparison!.amountChange, 2000);
    });
  });

  test('月次サマリーと精算を同じ表示月で取得する', () async {
    await seed(DateTime(2025, 7, 5), 250);
    await seed(DateTime(2026, 7, 5), 700);

    await provider.fetch();

    expect(provider.summary!.year, 2026);
    expect(provider.summary!.month, 7);
    expect(provider.summary!.total, 700);
    expect(provider.split!.year, 2026);
    expect(provider.split!.month, 7);
    expect(provider.split!.total, 700);
  });

  test('取引が無くてもエラーにならず空の月次結果を返す', () async {
    await provider.fetch();

    expect(provider.error, isNull);
    expect(provider.summary!.total, 0);
    expect(provider.summary!.byCategory, isEmpty);
    expect(provider.comparison!.previousTotal, 0);
    expect(provider.split!.total, 0);
  });
}
