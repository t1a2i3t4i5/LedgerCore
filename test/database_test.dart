import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/models/transaction.dart';

import 'matchers.dart';

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

    await db.insertTransaction(
      TransactionInput(
        memberId: memberId,
        categoryId: catId,
        amount: 1000,
        spentAt: DateTime(2026, 7, 1),
      ),
    );
    await db.insertTransaction(
      TransactionInput(
        memberId: memberId,
        categoryId: catId,
        amount: 2000,
        spentAt: DateTime(2026, 7, 31, 23, 59),
      ),
    );
    // 8/1 00:00 は 7月に含まれない（半開区間の上限）
    await db.insertTransaction(
      TransactionInput(
        memberId: memberId,
        categoryId: catId,
        amount: 9999,
        spentAt: DateTime(2026, 8, 1),
      ),
    );

    final julyTxns = await db.getTransactionsByMonth(2026, 7);
    expect(julyTxns.length, 2);
    expect(julyTxns.map((t) => t.amount), containsAll([1000.0, 2000.0]));
    // JOIN で名前が引ける
    expect(julyTxns.first.categoryName, isNotEmpty);
    expect(julyTxns.first.memberName, '自分');
  });

  test('取引の更新と削除', () async {
    final cats = await db.getCategories();
    final members = await db.getMembers();
    await db.insertTransaction(
      TransactionInput(
        memberId: members.first.id,
        categoryId: cats.first.id,
        amount: 500,
        spentAt: DateTime(2026, 7, 10),
      ),
    );

    var txns = await db.getTransactionsByMonth(2026, 7);
    expect(txns.length, 1);
    final id = txns.first.id;

    await db.updateTransaction(
      id,
      TransactionInput(
        memberId: members.first.id,
        categoryId: cats.first.id,
        amount: 750,
        spentAt: DateTime(2026, 7, 10),
      ),
    );
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

    await db.insertTransaction(
      TransactionInput(
        memberId: m1,
        categoryId: cats.first.id,
        amount: 1000,
        spentAt: DateTime(2026, 7, 5),
      ),
    );

    final summary = await db.getMonthlySummary(2026, 7);
    expect(summary.total, 1000);

    final split = await db.getSplit(2026, 7);
    expect(split.fairShare, 500);
    expect(split.members.length, 2);
    final b = split.members.firstWhere((m) => m.memberId == m2);
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
      await db.insertTransaction(
        TransactionInput(
          memberId: memberId,
          categoryId: catId,
          amount: 100,
          spentAt: d,
        ),
      );
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

    await db.insertTransaction(
      TransactionInput(
        memberId: memberId,
        categoryId: food,
        amount: 1000,
        spentAt: DateTime(2026, 4, 10),
      ),
    );
    await db.insertTransaction(
      TransactionInput(
        memberId: memberId,
        categoryId: transport,
        amount: 300,
        spentAt: DateTime(2026, 4, 20),
      ),
    );
    await db.insertTransaction(
      TransactionInput(
        memberId: memberId,
        categoryId: food,
        amount: 500,
        spentAt: DateTime(2025, 11, 3),
      ),
    );

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
      await db.insertTransaction(
        TransactionInput(
          memberId: memberId,
          categoryId: catId,
          amount: 100,
          spentAt: d,
        ),
      );
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

  test('0 以下・小数・上限超過の金額は insert できない', () async {
    final cats = await db.getCategories();
    final members = await db.getMembers();

    Future<void> insert(double amount) => db.insertTransaction(
      TransactionInput(
        memberId: members.first.id,
        categoryId: cats.first.id,
        amount: amount,
        spentAt: DateTime(2026, 7, 10),
      ),
    );

    // CHECK (amount > 0 AND amount <= kMaxAmount AND 整数) に弾かれる
    await expectLater(insert(-500), throwsAmountCheckViolation);
    await expectLater(insert(0), throwsAmountCheckViolation);
    // 小数は画面のどこにも表示されないので DB でも受け付けない。
    // 0.4 を 3 件入れると一覧は 3 行とも「¥0」・合計は「¥1」になる
    await expectLater(insert(0.4), throwsAmountCheckViolation);
    await expectLater(insert(1234.5), throwsAmountCheckViolation);
    await expectLater(insert(kMaxAmount + 1), throwsAmountCheckViolation);
    // Infinity は `> 0` を満たすので、上限が無いと通ってしまう
    await expectLater(insert(double.infinity), throwsAmountCheckViolation);

    expect(await db.getAllTransactions(), isEmpty);

    // 正の整数は通る。上限そのものも通る（境界は含む）
    await insert(500);
    await insert(kMaxAmount);
    expect(
      (await db.getAllTransactions()).map((t) => t.amount).toList()..sort(),
      [500.0, kMaxAmount],
    );
  });

  test('NaN の金額は NOT NULL に弾かれる', () async {
    // SQLite は NaN を NULL として保存するため、CHECK ではなく NOT NULL で
    // 落ちる。マイグレーションで NaN を掃除しなくてよい根拠がこれ
    final cats = await db.getCategories();
    final members = await db.getMembers();

    await expectLater(
      db.insertTransaction(
        TransactionInput(
          memberId: members.first.id,
          categoryId: cats.first.id,
          amount: double.nan,
          spentAt: DateTime(2026, 7, 10),
        ),
      ),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'メッセージ',
          contains('NOT NULL constraint failed'),
        ),
      ),
    );
    expect(await db.getAllTransactions(), isEmpty);
  });

  test('0 以下・小数・上限超過の金額には update できない', () async {
    final cats = await db.getCategories();
    final members = await db.getMembers();
    await db.insertTransaction(
      TransactionInput(
        memberId: members.first.id,
        categoryId: cats.first.id,
        amount: 500,
        spentAt: DateTime(2026, 7, 10),
      ),
    );
    final id = (await db.getAllTransactions()).single.id;

    Future<void> updateTo(double amount) => db.updateTransaction(
      id,
      TransactionInput(
        memberId: members.first.id,
        categoryId: cats.first.id,
        amount: amount,
        spentAt: DateTime(2026, 7, 10),
      ),
    );

    await expectLater(updateTo(-1), throwsAmountCheckViolation);
    await expectLater(updateTo(0), throwsAmountCheckViolation);
    await expectLater(updateTo(750.5), throwsAmountCheckViolation);
    await expectLater(updateTo(kMaxAmount + 1), throwsAmountCheckViolation);

    // 元の値のまま残る
    expect((await db.getAllTransactions()).single.amount, 500);
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

  test('取引を削除するとカテゴリが削除できるようになる', () async {
    await db.insertCategory('臨時費');
    final target = (await db.getCategories()).firstWhere(
      (c) => c.name == '臨時費',
    );
    final members = await db.getMembers();
    await db.insertTransaction(
      TransactionInput(
        memberId: members.first.id,
        categoryId: target.id,
        amount: 500,
        spentAt: DateTime(2026, 7, 10),
      ),
    );

    // 取引が参照している間は ON DELETE 未指定（NO ACTION）で弾かれる
    await expectLater(db.deleteCategory(target.id), throwsForeignKeyViolation);

    await db.deleteTransaction((await db.getAllTransactions()).single.id);

    // 取引を消せば制約が解ける
    await db.deleteCategory(target.id);
    expect(
      (await db.getCategories()).map((c) => c.name),
      isNot(contains('臨時費')),
    );
  });

  test('取引を削除するとメンバーが削除できるようになる', () async {
    await db.insertMember('パートナー');
    final target = (await db.getMembers()).firstWhere((m) => m.name == 'パートナー');
    final cats = await db.getCategories();
    await db.insertTransaction(
      TransactionInput(
        memberId: target.id,
        categoryId: cats.first.id,
        amount: 500,
        spentAt: DateTime(2026, 7, 10),
      ),
    );

    await expectLater(db.deleteMember(target.id), throwsForeignKeyViolation);

    await db.deleteTransaction((await db.getAllTransactions()).single.id);

    await db.deleteMember(target.id);
    expect(
      (await db.getMembers()).map((m) => m.name),
      isNot(contains('パートナー')),
    );
  });

  test('getSplit の月レンジは半開区間 [月初, 翌月初)', () async {
    final cats = await db.getCategories();
    final members = await db.getMembers();
    for (final d in [
      DateTime(2026, 6, 30, 23, 59, 59), // 前月末 → 含まない
      DateTime(2026, 7, 1), // 月初 → 含む
      DateTime(2026, 7, 31, 23, 59, 59), // 月末 → 含む
      DateTime(2026, 8, 1), // 翌月初 → 含まない
    ]) {
      await db.insertTransaction(
        TransactionInput(
          memberId: members.first.id,
          categoryId: cats.first.id,
          amount: 100,
          spentAt: d,
        ),
      );
    }

    final split = await db.getSplit(2026, 7);
    expect(split.total, 200);
  });

  test('getSplit の12月は翌年1月を巻き込まない', () async {
    final cats = await db.getCategories();
    final members = await db.getMembers();
    for (final e
        in {
          DateTime(2026, 12, 31): 300.0,
          DateTime(2027, 1, 1): 700.0,
        }.entries) {
      await db.insertTransaction(
        TransactionInput(
          memberId: members.first.id,
          categoryId: cats.first.id,
          amount: e.value,
          spentAt: e.key,
        ),
      );
    }

    final split = await db.getSplit(2026, 12);
    expect(split.total, 300);
    expect(split.year, 2026);
    expect(split.month, 12);
  });
}
