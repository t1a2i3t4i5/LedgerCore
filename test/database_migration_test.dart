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
/// 固定スキーマと移行ヘルパの再生成手順は docs/db-schema.md の
/// 「スキーマを変更するとき」を参照（コマンドの正本はそちら）。
///
/// このファイルは移行の終点をリテラルで持たない。起点は
/// [GeneratedHelper.versions]（生成物）を回し、終点は常にその最新版にする。
/// `migrateAndValidate(db, 3)` のように終点をリテラルで書くと、drift は
/// `AppDatabase.schemaVersion` ではなく引数の値まで移行するため、
/// schemaVersion を上げてもテストは古い版までを見たままグリーンになる。

/// 固定スキーマの最新版。移行の終点であり、参照スキーマの出どころでもある。
final _latestVersion = GeneratedHelper.versions.last;

/// 移行の起点になりうるバージョン（最新版以外のすべて）。
final _oldVersions =
    GeneratedHelper.versions.where((v) => v != _latestVersion).toList();

/// amount に CHECK（正・整数・上限）が入ったバージョン。
///
/// これ以降を起点にすると、汚いデータの seed そのものが CHECK 違反で落ちる。
const _amountCheckVersion = 3;

/// 小数・上限超過を保存できた起点バージョン。
///
/// リテラルの `[1, 2]` を置かない。`schemaVersion` が上がると `_oldVersions`
/// に新しい版が加わるが、その版は CHECK 済みなので掃除の検証には使えない。
/// 生成物から導出しておけば、人手でこのリストを追従させる必要がない。
final _versionsWithDirtyAmount =
    _oldVersions.where((v) => v < _amountCheckVersion).toList();

/// `members.mail` を削除したバージョン。これより前が「mail を持つ版」。
const _mailDropVersion = 4;

/// `members.mail` が存在した起点バージョン。
///
/// ここもリテラルの `[1, 2, 3]` を置かない。`schemaVersion` が上がると
/// `_oldVersions` に mail を持たない版が加わり、seed の INSERT が
/// 「そんな列は無い」で落ちるようになる。
final _versionsWithMail =
    _oldVersions.where((v) => v < _mailDropVersion).toList();

/// カテゴリの色と並び順を追加したバージョン。
const _categoryCustomizationVersion = 5;

/// 色と並び順を持たない起点バージョン。
final _versionsWithoutCategoryCustomization =
    _oldVersions.where((v) => v < _categoryCustomizationVersion).toList();

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
      reason:
          'drift_schemas/ の再生成が漏れている。docs/db-schema.md の「スキーマを変更するとき」を実行すること',
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

      await verifier.migrateAndValidate(
        db,
        _latestVersion,
        options: _validation,
      );
    });
  }

  test('カテゴリの色と並び順を持たない起点バージョンが存在する', () {
    expect(_versionsWithoutCategoryCustomization, isNotEmpty);
    expect(
      _versionsWithoutCategoryCustomization.every(
        (version) => version < _categoryCustomizationVersion,
      ),
      isTrue,
    );
  });

  for (final from in _versionsWithoutCategoryCustomization) {
    test('v$from のカテゴリは名前・ID順・取引との関連を保って移行する', () async {
      final schema = await verifier.schemaAt(from);
      addTearDown(schema.close);

      final raw = schema.rawDatabase;
      raw.execute('INSERT INTO categories (name) VALUES (?)', ['先のカテゴリ']);
      final firstCategoryId = raw.lastInsertRowId;
      raw.execute('INSERT INTO categories (name) VALUES (?)', ['後のカテゴリ']);
      final secondCategoryId = raw.lastInsertRowId;
      raw.execute('INSERT INTO members (name) VALUES (?)', [_memberName]);
      final memberId = raw.lastInsertRowId;
      final at = DateTime(2026, 7, 10).millisecondsSinceEpoch ~/ 1000;
      raw.execute(
        'INSERT INTO transactions '
        '(member_id, category_id, amount, spent_at, memo, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [memberId, secondCategoryId, 1000, at, '移行確認', at, at],
      );

      final db = AppDatabase.forTesting(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(
        db,
        _latestVersion,
        options: _validation,
      );

      final categories = await db.getCategories();
      expect(
        categories.map((category) => (category.id, category.name)).toList(),
        [(firstCategoryId, '先のカテゴリ'), (secondCategoryId, '後のカテゴリ')],
      );
      expect(categories.map((category) => category.sortOrder), [
        firstCategoryId,
        secondCategoryId,
      ]);
      expect(
        categories.every((category) => category.colorValue == null),
        isTrue,
      );

      final transaction = (await db.getAllTransactions()).single;
      expect(transaction.categoryId, secondCategoryId);
      expect(transaction.categoryName, '後のカテゴリ');
      expect(transaction.memo, '移行確認');
    });
  }

  for (final from in _versionsWithoutCategoryCustomization) {
    test('v$from では最も古い「その他」だけが固定カテゴリになる', () async {
      final schema = await verifier.schemaAt(from);
      addTearDown(schema.close);

      final raw = schema.rawDatabase;
      // 名前が完全一致する行のうち最も古い 1 件だけを固定にする。
      // v4 以前は同名カテゴリを追加できたので重複も seed する。
      for (final name in [_categoryName, 'その他', 'その他', 'その他の出費']) {
        raw.execute('INSERT INTO categories (name) VALUES (?)', [name]);
      }
      final firstOtherId =
          raw
                  .select(
                    "SELECT MIN(id) AS id FROM categories WHERE name = 'その他'",
                  )
                  .single['id']
              as int;

      final db = AppDatabase.forTesting(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(
        db,
        _latestVersion,
        options: _validation,
      );

      final categories = await db.getCategories();
      final fixed = categories.where((category) => category.isFixed).toList();
      expect(fixed, hasLength(1));
      expect(fixed.single.id, firstOtherId);
      // 固定カテゴリは一覧の末尾へ回り、同名の 2 件目と部分一致は通常行に残る
      expect(categories.last.id, firstOtherId);
      expect(
        categories
            .where((category) => !category.isFixed)
            .map((category) => category.name),
        [_categoryName, 'その他', 'その他の出費'],
      );
    });
  }

  test('v1 に 0 以下の取引が残っていても移行できる', () async {
    // v1 は amount に CHECK 制約が無く、0 以下の金額を保存できた
    final (db, ids) = await migrateFrom(1, [1500, -2000, 0, -0.5, 800]);

    final txns = await db.getAllTransactions();
    // 負の値は絶対値に補正、0 は削除される。
    // -0.5 は 0.5 に補正されたあと v3 の四捨五入で 1 になる
    expect(txns.map((t) => t.amount).toList()..sort(), [
      1.0,
      800.0,
      1500.0,
      2000.0,
    ]);
    // 金額以外の列は移行後も保持される
    final refund = txns.firstWhere((t) => t.amount == 2000);
    expect(refund.memo, '金額 -2000.0');
    expect(refund.spentAt, DateTime(2026, 7, 10));
    // 名前が空でないだけでは、別カテゴリにすり替わっても気付けない
    expect(refund.categoryName, _categoryName);
    expect(refund.memberName, _memberName);

    // id が保たれること。id は updateTransaction / deleteTransaction のキーで、
    // 振り直されると移行直後に「編集したら別の行が書き換わる」ことになる
    expect(refund.id, ids[-2000.0]);
    expect(txns.firstWhere((t) => t.amount == 1500).id, ids[1500.0]);
  });

  // 起点は `_oldVersions` 全部ではない。小数や上限超過を保存できたのは CHECK が
  // 整数と上限を強制する前の版だけで、v3 以降を起点にすると seed の INSERT 自体が
  // CHECK 違反で落ちる。「小数を持ちうる古い版」であって「最新版以外」ではない。
  //
  // この一覧が空になると、掃除の検証も順序依存（DELETE を UPDATE より先に置く）の
  // 守りも黙って消える。導出が壊れていないことを 1 本のテストで押さえておく。
  test('小数を持ちうる起点バージョンが存在する', () {
    expect(_versionsWithDirtyAmount, isNotEmpty);
    // 掃除の検証に使えない版が混ざっていないこと
    expect(
      _versionsWithDirtyAmount.every((v) => v < _amountCheckVersion),
      isTrue,
    );
  });

  for (final from in _versionsWithDirtyAmount) {
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
      TransactionInput(
        memberId: memberId,
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
      db.insertTransaction(
        TransactionInput(
          memberId: memberId,
          categoryId: 9999, // 存在しないカテゴリ
          amount: 100,
          spentAt: DateTime(2026, 7, 11),
        ),
      ),
      throwsForeignKeyViolation,
    );
  });

  test('掃除の必要が無い v1 でも移行できる', () async {
    final (db, _) = await migrateFrom(1, [1000, 2000]);

    final txns = await db.getAllTransactions();
    expect(txns.map((t) => t.amount).toList()..sort(), [1000.0, 2000.0]);
  });

  // 起点は `_oldVersions` 全部ではない。mail に値を入れられるのは列があった版だけで、
  // 削除後の版を起点にすると seed の INSERT が「そんな列は無い」で落ちる。
  //
  // この一覧が空になると、members の作り直しの検証も黙って消える。
  test('mail を持つ起点バージョンが存在する', () {
    expect(_versionsWithMail, isNotEmpty);
    expect(_versionsWithMail.every((v) => v < _mailDropVersion), isTrue);
  });

  for (final from in _versionsWithMail) {
    test('v$from の members.mail は列ごと消え、メンバーと取引の紐づけは残る', () async {
      // members はテーブルの作り直しで mail を落とす。作り直しは新テーブルへの
      // コピーなので、行が消える・id が振り直されるという壊れ方をしうる。
      // id が変わると transactions.member_id が別人（または存在しない行）を
      // 指すことになり、innerJoin で取引が一覧から丸ごと消える。
      final schema = await verifier.schemaAt(from);
      addTearDown(schema.close);

      final raw = schema.rawDatabase;
      raw.execute('INSERT INTO categories (name) VALUES (?)', [_categoryName]);
      final categoryId = raw.lastInsertRowId;
      // mail に実際の値を入れられるのはこの版まで。値ごと消えることを確かめる
      raw.execute('INSERT INTO members (name, mail) VALUES (?, ?)', [
        '先住',
        'old@example.com',
      ]);
      final firstId = raw.lastInsertRowId;
      // 2 人目を入れて、取引はこちらに紐づける。1 人だけだと id が
      // 振り直されても偶然一致してしまい、ずれを検出できない
      raw.execute('INSERT INTO members (name, mail) VALUES (?, ?)', [
        _memberName,
        null,
      ]);
      final secondId = raw.lastInsertRowId;

      final at = DateTime(2026, 7, 10).millisecondsSinceEpoch ~/ 1000;
      raw.execute(
        'INSERT INTO transactions '
        '(member_id, category_id, amount, spent_at, memo, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [secondId, categoryId, 1000, at, 'メモ', at, at],
      );

      final db = AppDatabase.forTesting(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(
        db,
        _latestVersion,
        options: _validation,
      );

      // mail は列ごと消えている。migrateAndValidate もスキーマ一致で見るが、
      // このイシューの主題なので名指しで押さえる
      final columns = await db.customSelect('PRAGMA table_info(members)').get();
      expect(columns.map((r) => r.read<String>('name')).toList(), [
        'id',
        'name',
      ]);

      // 行は 2 件とも残り、id も名前も保たれる
      final members = await db.getMembers();
      expect(members.map((m) => (m.id, m.name)).toList(), [
        (firstId, '先住'),
        (secondId, _memberName),
      ]);

      // 取引は 2 人目に紐づいたまま JOIN できる
      final txns = await db.getAllTransactions();
      expect(txns.single.memberId, secondId);
      expect(txns.single.memberName, _memberName);
      expect(txns.single.memo, 'メモ');
    });
  }

  test('members を作り直しても外部キー制約は効いたまま', () async {
    // members の作り直しは DROP TABLE を挟む。transactions 側の REFERENCES が
    // 途中の一時テーブル名に書き換わっていると、移行後だけ存在しない
    // メンバーの取引を作れてしまい、innerJoin で一覧から消える
    final schema = await verifier.schemaAt(_versionsWithMail.last);
    addTearDown(schema.close);

    final raw = schema.rawDatabase;
    raw.execute('INSERT INTO categories (name) VALUES (?)', [_categoryName]);
    raw.execute('INSERT INTO members (name) VALUES (?)', [_memberName]);

    final db = AppDatabase.forTesting(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, _latestVersion, options: _validation);

    final categoryId = (await db.getCategories()).first.id;
    await expectLater(
      db.insertTransaction(
        TransactionInput(
          memberId: 9999, // 存在しないメンバー
          categoryId: categoryId,
          amount: 100,
          spentAt: DateTime(2026, 7, 11),
        ),
      ),
      throwsForeignKeyViolation,
    );
  });
}
