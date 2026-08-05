import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/models/transaction.dart';
import 'package:ledger_app/providers/transaction_provider.dart';

/// TransactionProvider の削除まわりを確認する。
///
/// DAO 単体の削除は database_test.dart で担保しているので、
/// ここでは「削除が Provider の状態（一覧・合計・フィルター結果）に
/// 正しく波及するか」を見る。
void main() {
  late AppDatabase db;
  late TransactionProvider provider;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    provider = TransactionProvider(db);
    // fetch() は _year/_month の月を読む。既定は今月なので、
    // テストデータの月に合わせて固定しておく
    provider.setYearMonth(2026, 7);
  });
  tearDown(() async => db.close());

  /// 2026/7/10 に [amount] の取引を入れ、その id を返す。
  /// [categoryIndex] で既定カテゴリ 10 件のうちどれを使うか選ぶ。
  ///
  /// insertTransaction が挿入行の id を返さないため金額で引き直している。
  /// 同じ金額を 2 件入れると 2 件目でも 1 件目の id が返るので、
  /// 1 つのテスト内では金額を一意にすること。
  Future<int> seedTransaction({
    required double amount,
    int categoryIndex = 0,
  }) async {
    final cats = await db.getCategories();
    final members = await db.getMembers();
    await db.insertTransaction(TransactionRequest(
      userId: members.first.id,
      categoryId: cats[categoryIndex].id,
      amount: amount,
      spentAt: DateTime(2026, 7, 10),
    ));
    final txns = await db.getTransactionsByMonth(2026, 7);
    return txns.firstWhere((t) => t.amount == amount).id;
  }

  test('delete で一覧から消え、DB にも反映される', () async {
    final targetId = await seedTransaction(amount: 1000);
    await seedTransaction(amount: 2000);
    await provider.fetch();
    expect(provider.transactions.length, 2);

    await provider.delete(targetId);

    // delete は内部で fetch を呼ぶので、呼び出し側の再取得は不要
    expect(provider.transactions.length, 1);
    expect(provider.transactions.map((t) => t.id), isNot(contains(targetId)));
    // Provider のリストだけでなく DB からも消えている
    expect(await db.getTransactionsByMonth(2026, 7), hasLength(1));
  });

  test('delete がリスナーに通知し、最後の通知時点で対象が消えている', () async {
    final targetId = await seedTransaction(amount: 1000);
    await seedTransaction(amount: 2000);
    await provider.fetch();

    // 通知のたびに「そのときリスナーから見えた一覧」を記録する。
    // 回数だけを数えると、fetch() が先頭で loading=true として
    // 削除前の一覧のまま通知する分で条件を満たしてしまい、
    // 「通知は来たが中身が古い」不具合を見逃す
    final seenIds = <List<int>>[];
    provider.addListener(
      () => seenIds.add(provider.transactions.map((t) => t.id).toList()),
    );

    await provider.delete(targetId);

    expect(seenIds, isNotEmpty, reason: '削除で通知が飛ぶこと');
    expect(
      seenIds.last,
      isNot(contains(targetId)),
      reason: '最後の通知時点でリスナーから見える一覧に削除対象が残っていないこと',
    );
    expect(seenIds.last, hasLength(1));
  });

  test('delete 後に filteredTotal が削除分だけ減る', () async {
    final targetId = await seedTransaction(amount: 1500);
    await seedTransaction(amount: 2500);
    await provider.fetch();
    expect(provider.filteredTotal, 4000);

    await provider.delete(targetId);

    expect(provider.filteredTotal, 2500);
  });

  test('フィルター適用中に削除しても filteredTransactions が整合する', () async {
    final cats = await db.getCategories();
    // カテゴリ 0 に 2 件、カテゴリ 1 に 1 件
    final targetId = await seedTransaction(amount: 1000, categoryIndex: 0);
    await seedTransaction(amount: 2000, categoryIndex: 0);
    await seedTransaction(amount: 3000, categoryIndex: 1);
    await provider.fetch();

    provider.setFilters(categoryIds: {cats[0].id});
    expect(provider.filteredTransactions, hasLength(2));
    expect(provider.filteredTotal, 3000);

    await provider.delete(targetId);

    // フィルターは維持されたまま、対象だけが減る
    expect(provider.filteredTransactions, hasLength(1));
    expect(provider.filteredTotal, 2000);
    // フィルター対象外の取引は消えていない
    expect(provider.transactions, hasLength(2));
  });

  test('存在しない id の削除は例外にならない', () async {
    await seedTransaction(amount: 1000);
    await provider.fetch();

    // deleteTransaction は .go() の影響行数を捨てているため、
    // 該当行が無くても黙って成功する（現状の挙動を明文化しておく）
    await expectLater(provider.delete(99999), completes);
    expect(provider.transactions, hasLength(1));
  });
}
