import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/models/transaction.dart';

import 'matchers.dart';

/// schemaVersion 1 → 2 のマイグレーション検証。
///
/// v1 では amount に CHECK 制約が無く 0 以下の金額を保存できたため、
/// 既にそういうデータが入った端末でも移行が失敗しないことを確かめる。
/// インメモリ DB では接続を閉じると中身が消えてしまうので、
/// ここだけはテンポラリのファイル DB を使う（実端末のファイルには触らない）。

/// v1 時点の transactions テーブル定義（CHECK 制約なし）
const _v1TransactionsTable = '''
CREATE TABLE transactions (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  member_id INTEGER NOT NULL REFERENCES members (id),
  category_id INTEGER NOT NULL REFERENCES categories (id),
  amount REAL NOT NULL,
  spent_at INTEGER NOT NULL,
  memo TEXT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ledgercore_migration');
    dbFile = File('${tempDir.path}/ledgercore.sqlite');
  });
  tearDown(() async => tempDir.delete(recursive: true));

  /// v1 相当の DB ファイルを作り、指定した金額の取引を入れておく。
  /// メモには `金額 <値>` を入れ、移行後に元の行を追えるようにする。
  /// 戻り値は「金額 → その行の id」。移行で id が保たれることの検証に使う。
  Future<Map<double, int>> seedV1(List<double> amounts) async {
    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    addTearDown(db.close);
    // onCreate で v2 のスキーマが作られるので、transactions だけ v1 相当に戻す
    await db.customStatement('PRAGMA foreign_keys = OFF');
    await db.customStatement('DROP TABLE transactions');
    await db.customStatement(_v1TransactionsTable);

    final categoryId = (await db.getCategories()).first.id;
    final memberId = (await db.getMembers()).first.id;
    // drift は DateTime を unix 秒（int）で保存する
    final at = DateTime(2026, 7, 10).millisecondsSinceEpoch ~/ 1000;

    final ids = <double, int>{};
    for (final amount in amounts) {
      await db.customStatement(
        'INSERT INTO transactions '
        '(member_id, category_id, amount, spent_at, memo, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [memberId, categoryId, amount, at, '金額 $amount', at, at],
      );
      final row = await db
          .customSelect('SELECT last_insert_rowid() AS id')
          .getSingle();
      ids[amount] = row.read<int>('id');
    }

    await db.customStatement('PRAGMA user_version = 1');
    await db.close();
    return ids;
  }

  test('v1 に 0 以下の取引が残っていても移行できる', () async {
    final ids = await seedV1([1500, -2000, 0, -0.5, 800]);

    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    addTearDown(db.close);

    final txns = await db.getAllTransactions();
    // 負の値は絶対値に補正、0 は削除される
    expect(
      txns.map((t) => t.amount).toList()..sort(),
      [0.5, 800.0, 1500.0, 2000.0],
    );
    // 金額以外の列は移行後も保持される
    final refund = txns.firstWhere((t) => t.amount == 2000);
    expect(refund.memo, '金額 -2000.0');
    expect(refund.spentAt, DateTime(2026, 7, 10));
    // 名前が空でないだけでは、別カテゴリにすり替わっても気付けない
    expect(refund.categoryName, (await db.getCategories()).first.name);
    expect(refund.userName, '自分');

    // id が保たれること。id は updateTransaction / deleteTransaction のキーで、
    // 振り直されると移行直後に「編集したら別の行が書き換わる」ことになる
    expect(refund.id, ids[-2000.0]);
    expect(
      txns.firstWhere((t) => t.amount == 1500).id,
      ids[1500.0],
    );
  });

  test('汚いデータを掃除したあとでも CHECK 制約が付く', () async {
    // 掃除（UPDATE/DELETE）と制約付与（alterTable）が両方走る組み合わせを通す
    await seedV1([1500, -2000, 0]);

    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    addTearDown(db.close);

    expect((await db.getAllTransactions()).length, 2);

    final categoryId = (await db.getCategories()).first.id;
    final memberId = (await db.getMembers()).first.id;
    Future<void> insert(double amount) => db.insertTransaction(
          TransactionRequest(
            userId: memberId,
            categoryId: categoryId,
            amount: amount,
            spentAt: DateTime(2026, 7, 11),
          ),
        );

    await expectLater(insert(-1), throwsAmountCheckViolation);
    await expectLater(insert(0), throwsAmountCheckViolation);
    // 正側の境界は通る
    await insert(0.01);
    expect((await db.getAllTransactions()).length, 3);
  });

  test('移行後も外部キー制約が効いている', () async {
    // alterTable はテーブルを作り直すので、REFERENCES が新テーブルに
    // 引き継がれたかを直接確かめる。落ちると移行済み端末だけ
    // 参照先の無い取引を作れてしまい、innerJoin で一覧から消える
    await seedV1([1000]);

    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    addTearDown(db.close);

    final memberId = (await db.getMembers()).first.id;
    await expectLater(
      db.insertTransaction(TransactionRequest(
        userId: memberId,
        categoryId: 9999, // 存在しないカテゴリ
        amount: 100,
        spentAt: DateTime(2026, 7, 11),
      )),
      throwsForeignKeyViolation,
    );
  });

  test('0 以下の取引が無い v1 でも移行できる', () async {
    await seedV1([1000, 2000]);

    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    addTearDown(db.close);

    final txns = await db.getAllTransactions();
    expect(txns.map((t) => t.amount).toList()..sort(), [1000.0, 2000.0]);
  });
}
