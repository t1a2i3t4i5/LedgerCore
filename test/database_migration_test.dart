import 'package:drift/native.dart';
// migrations.dart は非推奨。テストは常にネイティブの sqlite3 上で動くので
// ネイティブ版を直接読む（web 版は wasm 用で、このアプリでは使わない）
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/models/transaction.dart';

import 'generated_migrations/schema.dart';
import 'matchers.dart';

/// マイグレーションの検証。実端末で起こりうる経路は「旧バージョン → 最新」だけなので、
/// 固定してある過去バージョンのそれぞれから最新版への移行を通す。
///
/// 起点のスキーマは `drift_schemas/*.json` に固定したものを使い、
/// drift の [SchemaVerifier] に組み立てさせる。手書き DDL で transactions だけ
/// 旧版に差し替える方式だと、検証しているのは「v1 の DB」ではなく
/// 「ほかのテーブルは最新・transactions だけ v1」という実在しない状態になる。
/// 変更していないテーブルの移行漏れを、作り直しが成功することで見逃す。
///
/// 固定スキーマと移行ヘルパの再生成手順は CLAUDE.md の
/// 「スキーマ検証用の生成物」を参照（コマンドの正本はそちら）。
///
/// このファイルは対象バージョンをリテラルで持たない。起点は
/// [GeneratedHelper.versions]（生成物）を回し、終点は常にその最新版にする。
/// `migrateAndValidate(db, 3)` のようにリテラルで書くと、drift は
/// `AppDatabase.schemaVersion` ではなく引数の値まで移行するため、
/// schemaVersion を 4 に上げてもテストは v1 → v3 だけを見たままグリーンになる。

/// 固定スキーマの最新版。移行の終点であり、参照スキーマの出どころでもある。
final _latestVersion = GeneratedHelper.versions.last;

/// 移行の起点になりうるバージョン（最新版以外のすべて）。
final _oldVersions =
    GeneratedHelper.versions.where((v) => v != _latestVersion).toList();

/// 検証を厳しめにする。既定では `validateDropped: false` で
/// 「参照に無いのに実在するテーブル」を見ないため、移行が中間テーブルを
/// 残しても素通りする。有効にしても現状のコードでは追加コストは無い。
const _validation = ValidationOptions(validateDropped: true);

/// 移行前に入れておくカテゴリ名・メンバー名。
///
/// [SchemaVerifier] はテーブルを作るだけで `onCreate` を走らせないため、
/// 既定カテゴリ・既定メンバーは存在しない。参照先は自分で用意する。
const _categoryName = '食費';
const _memberName = '自分';

void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  /// [from] のスキーマで DB を作って取引を入れ、`AppDatabase` で開いて
  /// 最新バージョンへ移行する。
  ///
  /// 取引の投入は生の SQL で行う。transactions の列構成は v1 から変わっておらず、
  /// 変わったのは CHECK 制約だけなので、バージョンごとに型付きの seed を
  /// 用意すると同じ INSERT がバージョンの数だけ並ぶ。
  ///
  /// メモには `金額 <値>` を入れ、移行後に元の行を追えるようにする。
  /// 戻り値は移行後の DB と「金額 → その行の id」。
  /// id は移行で振り直されないことの検証に使う。
  Future<(AppDatabase, Map<double, int>)> migrateFrom(
    int from,
    List<double> amounts,
  ) async {
    final schema = await verifier.schemaAt(from);
    addTearDown(schema.close);

    final raw = schema.rawDatabase;
    raw.execute('INSERT INTO categories (name) VALUES (?)', [_categoryName]);
    final categoryId = raw.lastInsertRowId;
    raw.execute('INSERT INTO members (name) VALUES (?)', [_memberName]);
    final memberId = raw.lastInsertRowId;
    // drift は DateTime を unix 秒（int）で保存する
    final at = DateTime(2026, 7, 10).millisecondsSinceEpoch ~/ 1000;

    final ids = <double, int>{};
    for (final amount in amounts) {
      raw.execute(
        'INSERT INTO transactions '
        '(member_id, category_id, amount, spent_at, memo, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [memberId, categoryId, amount, at, '金額 $amount', at, at],
      );
      ids[amount] = raw.lastInsertRowId;
    }

    final db = AppDatabase.forTesting(schema.newConnection());
    addTearDown(db.close);
    // 移行を走らせたうえで、移行後のスキーマが最新の定義と一致することも見る
    await verifier.migrateAndValidate(db, _latestVersion, options: _validation);
    return (db, ids);
  }

  test('固定スキーマの最新版が AppDatabase.schemaVersion と一致する', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // schemaVersion を上げたのに drift_schemas/ を再生成していないと、
    // 以降のテストは古い版を終点にしたまま緑で通り続ける。ここで先に落とす。
    expect(
      _latestVersion,
      db.schemaVersion,
      reason: 'drift_schemas/ の再生成が漏れている。CLAUDE.md の手順を実行すること',
    );
  });

  test('新規作成時のスキーマが最新の固定スキーマと一致する', () async {
    // 空の DB は user_version = 0 なので onCreate（createAll）が走る。
    // 参照側は drift_schemas/ から起こしたヘルパなので、この 1 本だけが
    // 「lib/db/database.dart の定義」と「固定スキーマ」を直接突き合わせる。
    //
    // 移行のテストだけでは足りない。移行が作り直すのは transactions だけで、
    // categories / members は「ヘルパ旧版が作った形」対「ヘルパ新版の形」の
    // 比較になり、アプリ本体の定義が一度も登場しないため。
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await verifier.migrateAndValidate(db, _latestVersion, options: _validation);
  });

  for (final from in _oldVersions) {
    test('v$from のスキーマから移行すると v$_latestVersion の定義と一致する', () async {
      // データを入れずスキーマの形だけを見る。手書き DDL の方式では
      // categories / members が最初から最新だったため検証できていなかった部分。
      //
      // startAt() ではなく schemaAt() を使う。startAt() は InitializedSchema を
      // 捨てるので、生の in-memory DB を dispose する手段が無くなる。
      final schema = await verifier.schemaAt(from);
      addTearDown(schema.close);

      final db = AppDatabase.forTesting(schema.newConnection());
      addTearDown(db.close);

      await verifier.migrateAndValidate(db, _latestVersion,
          options: _validation);
    });
  }

  test('v1 に 0 以下の取引が残っていても移行できる', () async {
    // v1 は amount に CHECK 制約が無く、0 以下の金額を保存できた
    final (db, ids) = await migrateFrom(1, [1500, -2000, 0, -0.5, 800]);

    final txns = await db.getAllTransactions();
    // 負の値は絶対値に補正、0 は削除される。
    // -0.5 は 0.5 に補正されたあと v3 の四捨五入で 1 になる
    expect(
      txns.map((t) => t.amount).toList()..sort(),
      [1.0, 800.0, 1500.0, 2000.0],
    );
    // 金額以外の列は移行後も保持される
    final refund = txns.firstWhere((t) => t.amount == 2000);
    expect(refund.memo, '金額 -2000.0');
    expect(refund.spentAt, DateTime(2026, 7, 10));
    // 名前が空でないだけでは、別カテゴリにすり替わっても気付けない
    expect(refund.categoryName, _categoryName);
    expect(refund.userName, _memberName);

    // id が保たれること。id は updateTransaction / deleteTransaction のキーで、
    // 振り直されると移行直後に「編集したら別の行が書き換わる」ことになる
    expect(refund.id, ids[-2000.0]);
    expect(
      txns.firstWhere((t) => t.amount == 1500).id,
      ids[1500.0],
    );
  });

  // 起点は `_oldVersions` ではなく明示の [1, 2]。小数や上限超過を保存できたのは
  // CHECK が整数と上限を強制する前の v1 / v2 だけで、v3 以降を起点にすると
  // seed の INSERT 自体が CHECK 違反で落ちる。「小数を持ちうる古い版」の一覧であり、
  // 「最新版以外」ではない。
  for (final from in [1, 2]) {
    test('v$from の小数は四捨五入され、上限超過は削除される', () async {
      final (db, ids) = await migrateFrom(from, [
        1234.5, // 四捨五入して 1235
        0.4, // 四捨五入すると 0 になるので消える
        kMaxAmount + 1, // 上限超過なので消える
        double.infinity, // 桁を打ち続けて飽和した値も上限超過として消える
        800, // そのまま残る
      ]);

      final txns = await db.getAllTransactions();
      expect(txns.map((t) => t.amount).toList()..sort(), [800.0, 1235.0]);
      // 四捨五入した行も id は保たれる
      expect(txns.firstWhere((t) => t.amount == 1235).id, ids[1234.5]);
    });
  }

  test('汚いデータを掃除したあとでも CHECK 制約が付く', () async {
    // 掃除（UPDATE/DELETE）と制約付与（alterTable）が両方走る組み合わせを通す
    final (db, _) = await migrateFrom(1, [1500, -2000, 0]);

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
    await expectLater(insert(0.5), throwsAmountCheckViolation);
    await expectLater(insert(kMaxAmount + 1), throwsAmountCheckViolation);
    // 境界は通る
    await insert(1);
    await insert(kMaxAmount);
    expect((await db.getAllTransactions()).length, 4);
  });

  test('移行後も外部キー制約が効いている', () async {
    // alterTable はテーブルを作り直すので、REFERENCES が新テーブルに
    // 引き継がれたかを直接確かめる。落ちると移行済み端末だけ
    // 参照先の無い取引を作れてしまい、innerJoin で一覧から消える
    final (db, _) = await migrateFrom(1, [1000]);

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

  test('掃除の必要が無い v1 でも移行できる', () async {
    final (db, _) = await migrateFrom(1, [1000, 2000]);

    final txns = await db.getAllTransactions();
    expect(txns.map((t) => t.amount).toList()..sort(), [1000.0, 2000.0]);
  });
}
