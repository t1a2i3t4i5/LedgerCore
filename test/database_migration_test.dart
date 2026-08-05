import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/models/transaction.dart';

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
  /// 戻り値は投入した取引の (金額, メモ) の並び。
  Future<void> seedV1(List<double> amounts) async {
    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    // onCreate で v2 のスキーマが作られるので、transactions だけ v1 相当に戻す
    await db.customStatement('PRAGMA foreign_keys = OFF');
    await db.customStatement('DROP TABLE transactions');
    await db.customStatement(_v1TransactionsTable);

    final categoryId = (await db.getCategories()).first.id;
    final memberId = (await db.getMembers()).first.id;
    // drift は DateTime を unix 秒（int）で保存する
    final at = DateTime(2026, 7, 10).millisecondsSinceEpoch ~/ 1000;

    for (final amount in amounts) {
      await db.customStatement(
        'INSERT INTO transactions '
        '(member_id, category_id, amount, spent_at, memo, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [memberId, categoryId, amount, at, '金額 $amount', at, at],
      );
    }

    await db.customStatement('PRAGMA user_version = 1');
    await db.close();
  }

  test('v1 に 0 以下の取引が残っていても移行できる', () async {
    await seedV1([1500, -2000, 0, -0.5, 800]);

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
    expect(refund.categoryName, isNotEmpty);
    expect(refund.userName, '自分');
  });

  test('移行後は CHECK 制約が効いて 0 以下を insert できない', () async {
    await seedV1([1000]);

    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    addTearDown(db.close);

    final categoryId = (await db.getCategories()).first.id;
    final memberId = (await db.getMembers()).first.id;
    await expectLater(
      db.insertTransaction(TransactionRequest(
        userId: memberId,
        categoryId: categoryId,
        amount: -1,
        spentAt: DateTime(2026, 7, 11),
      )),
      throwsA(isA<Exception>()),
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
