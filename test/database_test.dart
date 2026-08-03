import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/models/transaction.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test('初回起動でデフォルトカテゴリ10件と既定メンバーが投入される', () async {
    final cats = await db.getCategories();
    expect(cats.length, 10);
    expect(cats.map((c) => c.name), contains('食費'));

    final members = await db.getMembers();
    expect(members.length, 1);
    expect(members.first.name, '自分');
  });

  test('取引の追加と月レンジ（半開区間）取得', () async {
    final cats = await db.getCategories();
    final members = await db.getMembers();
    final catId = cats.first.id;
    final memberId = members.first.id;

    await db.insertTransaction(TransactionRequest(
        userId: memberId,
        categoryId: catId,
        amount: 1000,
        spentAt: DateTime(2026, 7, 1)));
    await db.insertTransaction(TransactionRequest(
        userId: memberId,
        categoryId: catId,
        amount: 2000,
        spentAt: DateTime(2026, 7, 31, 23, 59)));
    // 8/1 00:00 は 7月に含まれない（半開区間の上限）
    await db.insertTransaction(TransactionRequest(
        userId: memberId,
        categoryId: catId,
        amount: 9999,
        spentAt: DateTime(2026, 8, 1)));

    final julyTxns = await db.getTransactionsByMonth(2026, 7);
    expect(julyTxns.length, 2);
    expect(julyTxns.map((t) => t.amount), containsAll([1000.0, 2000.0]));
    // JOIN で名前が引ける
    expect(julyTxns.first.categoryName, isNotEmpty);
    expect(julyTxns.first.userName, '自分');
  });

  test('取引の更新と削除', () async {
    final cats = await db.getCategories();
    final members = await db.getMembers();
    await db.insertTransaction(TransactionRequest(
        userId: members.first.id,
        categoryId: cats.first.id,
        amount: 500,
        spentAt: DateTime(2026, 7, 10)));

    var txns = await db.getTransactionsByMonth(2026, 7);
    expect(txns.length, 1);
    final id = txns.first.id;

    await db.updateTransaction(
        id,
        TransactionRequest(
            userId: members.first.id,
            categoryId: cats.first.id,
            amount: 750,
            spentAt: DateTime(2026, 7, 10)));
    txns = await db.getTransactionsByMonth(2026, 7);
    expect(txns.first.amount, 750);

    await db.deleteTransaction(id);
    txns = await db.getTransactionsByMonth(2026, 7);
    expect(txns, isEmpty);
  });

  test('月次サマリーと割り勘がDB経由で計算できる', () async {
    final cats = await db.getCategories();
    final members = await db.getMembers();
    await db.insertMember('パートナー');
    final allMembers = await db.getMembers();
    final m1 = members.first.id;
    final m2 = allMembers.firstWhere((m) => m.name == 'パートナー').id;

    await db.insertTransaction(TransactionRequest(
        userId: m1,
        categoryId: cats.first.id,
        amount: 1000,
        spentAt: DateTime(2026, 7, 5)));

    final summary = await db.getMonthlySummary(2026, 7);
    expect(summary.total, 1000);

    final split = await db.getSplit(2026, 7);
    expect(split.fairShare, 500);
    expect(split.users.length, 2);
    final b = split.users.firstWhere((u) => u.userId == m2);
    expect(b.balance, -500);
  });

  test('期間指定（半開区間）で取引を取得できる', () async {
    final cats = await db.getCategories();
    final members = await db.getMembers();
    final catId = cats.first.id;
    final memberId = members.first.id;

    for (final d in [
      DateTime(2026, 2, 28),
      DateTime(2026, 3, 1),
      DateTime(2026, 5, 31, 23, 59),
      DateTime(2026, 6, 1),
    ]) {
      await db.insertTransaction(TransactionRequest(
          userId: memberId, categoryId: catId, amount: 100, spentAt: d));
    }

    // [3/1, 6/1) → 3/1 と 5/31 23:59 の2件。2/28 と 6/1 は範囲外
    final txns = await db.getTransactionsByRange(
      DateTime(2026, 3, 1),
      DateTime(2026, 6, 1),
    );
    expect(txns.length, 2);
    expect(txns.map((t) => t.spentAt.month), containsAll([3, 5]));

    final all = await db.getAllTransactions();
    expect(all.length, 4);
  });

  test('年次サマリーと年別合計がDB経由で計算できる', () async {
    final cats = await db.getCategories();
    final members = await db.getMembers();
    final memberId = members.first.id;
    final food = cats.firstWhere((c) => c.name == '食費').id;
    final transport = cats.firstWhere((c) => c.name == '交通費').id;

    await db.insertTransaction(TransactionRequest(
        userId: memberId,
        categoryId: food,
        amount: 1000,
        spentAt: DateTime(2026, 4, 10)));
    await db.insertTransaction(TransactionRequest(
        userId: memberId,
        categoryId: transport,
        amount: 300,
        spentAt: DateTime(2026, 4, 20)));
    await db.insertTransaction(TransactionRequest(
        userId: memberId,
        categoryId: food,
        amount: 500,
        spentAt: DateTime(2025, 11, 3)));

    final yearly = await db.getYearlySummary(2026);
    expect(yearly.total, 1300);
    expect(yearly.byMonth.length, 12);
    expect(yearly.byMonth[3].total, 1300); // 4月
    expect(yearly.byMonth[0].total, 0); // 1月は取引なし
    expect(yearly.byCategory.first.categoryName, '食費');

    final totals = await db.getYearlyTotals();
    expect(totals.map((p) => p.year), [2025, 2026]);
    expect(totals.first.total, 500);
    expect(totals.last.total, 1300);
  });

  test('年レンジの境界をDAO側で正しく絞り込む', () async {
    final cats = await db.getCategories();
    final members = await db.getMembers();
    final catId = cats.first.id;
    final memberId = members.first.id;

    // 前年の大晦日直前 / 対象年の元日 / 対象年の大晦日直前 / 翌年の元日
    for (final d in [
      DateTime(2025, 12, 31, 23, 59, 59),
      DateTime(2026, 1, 1),
      DateTime(2026, 12, 31, 23, 59, 59),
      DateTime(2027, 1, 1),
    ]) {
      await db.insertTransaction(TransactionRequest(
          userId: memberId, categoryId: catId, amount: 100, spentAt: d));
    }

    // 純関数側の年フィルタに頼らず、DAO のレンジ指定そのものを検証する
    final inYear = await db.getTransactionsByRange(
      DateTime(2026, 1, 1),
      DateTime(2027, 1, 1),
    );
    expect(inYear.length, 2);
    expect(inYear.every((t) => t.spentAt.year == 2026), isTrue);

    // 年境界の取引が 1月 と 12月 に振り分けられる
    final yearly = await db.getYearlySummary(2026);
    expect(yearly.total, 200);
    expect(yearly.byMonth.first.total, 100); // 1/1 00:00
    expect(yearly.byMonth.last.total, 100); // 12/31 23:59:59
  });

  test('カテゴリの追加・更新・削除', () async {
    await db.insertCategory('臨時費');
    var cats = await db.getCategories();
    expect(cats.map((c) => c.name), contains('臨時費'));

    final target = cats.firstWhere((c) => c.name == '臨時費');
    await db.updateCategoryName(target.id, '特別費');
    cats = await db.getCategories();
    expect(cats.map((c) => c.name), contains('特別費'));
    expect(cats.map((c) => c.name), isNot(contains('臨時費')));

    await db.deleteCategory(target.id);
    cats = await db.getCategories();
    expect(cats.map((c) => c.name), isNot(contains('特別費')));
  });
}
