import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../models/category.dart';
import '../models/household_member.dart';
import '../models/summary.dart';
import '../models/split.dart';
import '../models/transaction.dart';
import 'summary_calculator.dart';

part 'database.g.dart';

/// 初回起動時に投入するデフォルトカテゴリ
const _defaultCategories = [
  '食費',
  '日用品',
  '交通費',
  '光熱費',
  '通信費',
  '住居費',
  '医療費',
  '娯楽費',
  '衣服',
  _fixedCategoryName,
];

/// 削除できない受け皿カテゴリの名前。
///
/// 初回投入と v5 への移行の両方でこの名前を固定の印にする。移行後にユーザーが
/// 改名しても固定は列の値として残るので、ここを参照するのはこの 2 か所だけ。
const _fixedCategoryName = 'その他';

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 50)();
  IntColumn get colorValue => integer().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  // 「その他」のように、分類しきれない取引の受け皿として常に残すカテゴリ。
  // 削除と並べ替えだけを禁じ、名前と色は変えられる。
  BoolColumn get isFixed => boolean().withDefault(const Constant(false))();
}

/// 支出を負担する世帯のメンバー。取引の支払者であり、割り勘の頭割りの分母。
/// アカウントでも認証の主体でもない（このアプリに認証は存在しない）。
class Members extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 50)();
}

class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get memberId => integer().references(Members, #id)();
  IntColumn get categoryId => integer().references(Categories, #id)();
  // 金額は「0 より大きい」「上限以下」「整数」の 3 つを満たす値のみ許す
  // （入力側の validator と二重に防ぐ）。
  //
  // 整数に限る理由: 金額の表示は widgets/amount_format.dart の formatYen() が
  // 一手に担っており、書式 '#,###' で小数部を出さない（画面ごとの定義は無い）。
  // 0.4 円の取引を 3 件入れると一覧は 3 行とも「¥0」・合計は「¥1」になり、
  // 画面上で 0 + 0 + 0 = 1 になる。記録できても読めない値でしかない。
  // この CHECK は formatYen() の書式に依存している。あちらを変えるならここも
  // 見直すこと（formatYen() 側の dartdoc からもここを指している）。
  // 整数判定は drift の式 API に無いので CustomExpression で書く。
  // Infinity は上限の比較と CAST の比較の両方で弾かれる。
  //
  // カラム型は RealColumn のまま。IntColumn にすると表示用モデル・集計・
  // グラフまで int が波及する一方、割り勘の fairShare は「合計 ÷ 人数」で
  // 本質的に小数なので、結局 double が残って中途半端になる。
  //
  // check() の中で自分自身を参照するのは drift が定める書き方なので、
  // 再帰ゲッターの lint は無視する（実際には評価されず SQL の CHECK 句になる）
  // ignore: recursive_getters
  RealColumn get amount =>
      real().check(
        // ignore: recursive_getters
        amount.isBiggerThanValue(0) &
            // ignore: recursive_getters
            amount.isSmallerOrEqualValue(kMaxAmount) &
            const CustomExpression<bool>('amount = CAST(amount AS INTEGER)'),
      )();
  DateTimeColumn get spentAt => dateTime()();
  TextColumn get memo => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();
}

@DriftDatabase(tables: [Categories, Members, Transactions])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'ledgercore'));

  /// テスト用（NativeDatabase.memory() などを注入する）
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      // デフォルトカテゴリと既定メンバーを投入
      await batch((b) {
        b.insertAll(
          categories,
          _defaultCategories.indexed.map(
            (entry) => CategoriesCompanion.insert(
              name: entry.$2,
              sortOrder: Value(entry.$1),
              isFixed: Value(entry.$2 == _fixedCategoryName),
            ),
          ),
        );
        b.insert(members, MembersCompanion.insert(name: '自分'));
      });
    },
    onUpgrade: (m, from, to) async {
      // 未対応のバージョンを黙って素通りさせない。drift の既定 onUpgrade は
      // 「移行が書かれていません」と例外を投げる安全網だが、それを上書きして
      // しまうため、分岐から漏れたら気付けるようにここで落とす。
      if (from < 1 || to > 5) {
        throw StateError('未対応のマイグレーションです: v$from → v$to');
      }
      // drift は onUpgrade をトランザクションで包まない。包まないと
      // customStatement の UPDATE / DELETE がそれぞれ autocommit され、
      // 後続の alterTable（内部で独自のトランザクションを張る）が
      // 容量不足などで失敗したとき、「データは書き換え済み・スキーマは
      // 旧版のまま・user_version も旧版のまま」で固定されてしまう。
      // 全体を 1 つのトランザクションにして全部成功か全部巻き戻しにする。
      //
      // onUpgrade の時点では beforeOpen がまだ走っておらず
      // PRAGMA foreign_keys は OFF なので、alterTable が
      // トランザクション内で PRAGMA を切り替えようとする問題は起きない。
      await transaction(() async {
        // v2 / v3 はどちらも amount の CHECK 制約を変える移行で、SQLite は
        // 既存カラムへの CHECK 追加をサポートしないためテーブルを作り直す。
        // 作り直しは新テーブルへのコピーを伴うので、制約違反の行が残っていると
        // 移行そのものが失敗する。先に既存データを制約に合う形へ整えておく。
        //
        // **データ整形をすべて済ませてから、テーブルごとに一度だけ作り直す。**
        // TableMigration は「そのとき Dart 側に書かれている最新の定義」で
        // テーブルを作るため、v1 の端末で from < 2 のブロック内から呼ぶと
        // v3 の CHECK を持つテーブルに小数のまま流し込むことになり、
        // v1 → 最新の直行だけが移行に失敗する。
        if (from < 2) {
          // 負の金額はマイナス記号の打ち間違いとみなして絶対値に補正し、
          // 0 円は集計上意味を持たない（グラフでも幅 0 のセクションになる）ので削除する。
          await customStatement(
            'UPDATE transactions SET amount = abs(amount) WHERE amount < 0',
          );
          await customStatement('DELETE FROM transactions WHERE amount <= 0');
        }
        if (from < 3) {
          // 上限超過は誤入力とみなして行ごと削除する。桁を打ち続けて
          // Infinity になった行もここで一緒に落ちる（Infinity は
          // どんな有限値より大きい）。NaN は SQLite が NULL として
          // 保存するため、NOT NULL に弾かれて最初から存在しない。
          await customStatement(
            'DELETE FROM transactions WHERE amount > $kMaxAmount',
          );
          // 四捨五入で 0 になる行（0 < amount < 0.5）は v2 と同じ方針で
          // 削除する。**四捨五入より先に消す**のがポイントで、逆順にすると
          // v2 起点の移行が落ちる。v2 のテーブルには CHECK (amount > 0.0) が
          // 付いており、テーブルを作り直す前の UPDATE の時点で 0 を書き込むと
          // 自分自身の制約に弾かれるため（v1 には CHECK が無いので v1 起点
          // では起きず、v2 起点だけが失敗する）。
          await customStatement(
            'DELETE FROM transactions WHERE ROUND(amount) <= 0',
          );
          // 小数は四捨五入する。SQLite の ROUND は half away from zero で、
          // 表示側（widgets/amount_format.dart の formatYen()、書式 '#,###'）
          // と同じ丸め方なので、**行ごとの表示額は変わらない**
          // （1234.5 はどちらも 1,235）。
          //
          // ただし合計は変わりうる。「和を丸めた値」と「丸めた値の和」は
          // 別物なので、100.6 が 2 件あると移行前の合計表示 ¥201 が
          // 移行後は ¥202 になる。0 < amount < 0.5 の行は上で消えるため、
          // その行が寄与していた分も合計から減る。
          await customStatement(
            'UPDATE transactions SET amount = ROUND(amount)',
          );
        }
        // 作り直しは「参照する側（transactions）→ 参照される側（members）」の
        // 順で行う。members を先に落とすと、その間 transactions の外部キーは
        // 存在しないテーブルを指す（onUpgrade 中は PRAGMA foreign_keys が OFF
        // なので実害は出ないが、順序を drift の推奨どおりにしておく）。
        //
        // experimental 扱いだが、制約変更を伴う移行はこれが drift の標準手段。
        if (from < 3) {
          // ignore: experimental_member_use
          await m.alterTable(TableMigration(transactions));
        }
        if (from < 4) {
          // v4 は未使用だった members.mail の削除。SQLite の DROP COLUMN は
          // 3.35 以降にしか無く、端末の SQLite のバージョンは選べないので、
          // ここも CHECK 追加と同じくテーブルの作り直しで落とす。
          // mail は最新の定義に無いためコピー対象から外れ、そのまま消える。
          // ignore: experimental_member_use
          await m.alterTable(TableMigration(members));
        }
        if (from < 5) {
          // 既存カテゴリの色は未設定のままにし、表示側の ID 由来の色へ
          // フォールバックさせる。これにより移行前後で色が変わらない。
          await m.addColumn(categories, categories.colorValue);
          await m.addColumn(categories, categories.sortOrder);
          await m.addColumn(categories, categories.isFixed);
          // 現行の一覧は ID 昇順なので、その順序を初期値として保存する。
          await customStatement('UPDATE categories SET sort_order = id');
          // 初回投入の受け皿カテゴリを固定にする。v4 以前は同名カテゴリを
          // 追加できたので、複数ある場合は最も古い 1 件だけを受け皿にする。
          // 改名・削除済みの端末では一致する行が無く、固定カテゴリを持たない
          // まま移行する（それでよい）。
          await customStatement(
            "UPDATE categories SET is_fixed = 1 "
            "WHERE name = '$_fixedCategoryName' AND id = ("
            "SELECT MIN(id) FROM categories WHERE name = '$_fixedCategoryName'"
            ")",
          );
        }
      });
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  // ---- カテゴリ ----
  Future<List<CategoryView>> getCategories() async {
    final rows =
        await (select(categories)..orderBy([
          // 固定カテゴリは受け皿なので、並べ替えても常に一覧の最後に置く。
          (c) => OrderingTerm(expression: c.isFixed),
          (c) => OrderingTerm(expression: c.sortOrder),
          (c) => OrderingTerm(expression: c.id),
        ])).get();
    return rows
        .map(
          (c) => CategoryView(
            id: c.id,
            name: c.name,
            colorValue: c.colorValue,
            sortOrder: c.sortOrder,
            isFixed: c.isFixed,
          ),
        )
        .toList();
  }

  Future<void> insertCategory(String name, {int? colorValue}) async {
    // 固定カテゴリは常に末尾に置くので、その sort_order は最大値に数えない。
    // 数えると新規カテゴリが固定より下の順序値を持てず、並べ替えの起点がずれる。
    final movable =
        (await getCategories()).where((category) => !category.isFixed).toList();
    final nextOrder =
        movable.isEmpty
            ? 0
            : movable
                    .map((category) => category.sortOrder)
                    .reduce((max, order) => order > max ? order : max) +
                1;
    await into(categories).insert(
      CategoriesCompanion.insert(
        name: name,
        colorValue: Value(colorValue),
        sortOrder: Value(nextOrder),
      ),
    );
  }

  Future<void> updateCategoryName(int id, String name) => (update(categories)
    ..where(
      (c) => c.id.equals(id),
    )).write(CategoriesCompanion(name: Value(name)));

  Future<void> updateCategory(int id, String name, int colorValue) =>
      (update(categories)..where((c) => c.id.equals(id))).write(
        CategoriesCompanion(name: Value(name), colorValue: Value(colorValue)),
      );

  Future<void> reorderCategories(List<int> categoryIds) => transaction(
    () => batch((batch) {
      for (final (index, id) in categoryIds.indexed) {
        batch.update(
          categories,
          CategoriesCompanion(sortOrder: Value(index)),
          where: (category) => category.id.equals(id),
        );
      }
    }),
  );

  Future<void> deleteCategory(int id) async {
    // 画面でも削除ボタンを無効にしているが、受け皿を失うと分類しきれない取引の
    // 行き先が無くなるので、DB 側でも落とす。
    final target =
        await (select(categories)
          ..where((c) => c.id.equals(id))).getSingleOrNull();
    if (target != null && target.isFixed) {
      throw StateError('固定カテゴリは削除できません');
    }
    await (delete(categories)..where((c) => c.id.equals(id))).go();
  }

  // ---- メンバー ----
  Future<List<HouseholdMember>> getMembers() async {
    final rows =
        await (select(members)
          ..orderBy([(m) => OrderingTerm(expression: m.id)])).get();
    return rows.map((m) => HouseholdMember(id: m.id, name: m.name)).toList();
  }

  Future<void> insertMember(String name) =>
      into(members).insert(MembersCompanion.insert(name: name));

  Future<void> updateMemberName(int id, String name) => (update(members)
    ..where((m) => m.id.equals(id))).write(MembersCompanion(name: Value(name)));

  Future<void> deleteMember(int id) =>
      (delete(members)..where((m) => m.id.equals(id))).go();

  // ---- 取引 ----
  /// 指定月の取引を、メンバー名・カテゴリ名を JOIN して取得する。
  /// 月レンジは半開区間 [月初, 翌月初)。
  Future<List<TransactionView>> getTransactionsByMonth(int year, int month) =>
      getTransactionsByRange(
        DateTime(year, month, 1),
        DateTime(year, month + 1, 1),
      );

  /// 期間 [start, end) の取引を、メンバー名・カテゴリ名を JOIN して取得する。
  /// 月・年をまたぐ集計の共通入口。
  Future<List<TransactionView>> getTransactionsByRange(
    DateTime start,
    DateTime end,
  ) => _selectTransactions(start: start, end: end);

  /// 全期間の取引を取得する（年別集計用）。
  Future<List<TransactionView>> getAllTransactions() => _selectTransactions();

  /// 取引をメンバー名・カテゴリ名付きで取得する共通クエリ。
  /// start / end を渡すと半開区間 [start, end) で絞り込む。
  Future<List<TransactionView>> _selectTransactions({
    DateTime? start,
    DateTime? end,
  }) async {
    final query = select(transactions).join([
      innerJoin(members, members.id.equalsExp(transactions.memberId)),
      innerJoin(categories, categories.id.equalsExp(transactions.categoryId)),
    ]);

    Expression<bool>? predicate;
    if (start != null) {
      predicate = transactions.spentAt.isBiggerOrEqualValue(start);
    }
    if (end != null) {
      final upper = transactions.spentAt.isSmallerThanValue(end);
      predicate = predicate == null ? upper : predicate & upper;
    }
    if (predicate != null) {
      query.where(predicate);
    }

    final rows = await query.get();
    return rows.map((row) {
      final t = row.readTable(transactions);
      final m = row.readTable(members);
      final c = row.readTable(categories);
      return TransactionView(
        id: t.id,
        memberId: m.id,
        memberName: m.name,
        categoryId: c.id,
        categoryName: c.name,
        categoryColorValue: c.colorValue,
        categorySortOrder: c.sortOrder,
        categoryIsFixed: c.isFixed,
        amount: t.amount,
        spentAt: t.spentAt,
        memo: t.memo,
      );
    }).toList();
  }

  Future<void> insertTransaction(TransactionInput input) =>
      into(transactions).insert(
        TransactionsCompanion.insert(
          memberId: input.memberId,
          categoryId: input.categoryId,
          amount: input.amount,
          spentAt: input.spentAt,
          memo: Value(input.memo),
        ),
      );

  Future<void> updateTransaction(int id, TransactionInput input) =>
      (update(transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(
          memberId: Value(input.memberId),
          categoryId: Value(input.categoryId),
          amount: Value(input.amount),
          spentAt: Value(input.spentAt),
          memo: Value(input.memo),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<void> deleteTransaction(int id) =>
      (delete(transactions)..where((t) => t.id.equals(id))).go();

  // ---- 集計（端末側で再計算） ----
  Future<MonthlySummary> getMonthlySummary(int year, int month) async {
    final txns = await getTransactionsByMonth(year, month);
    return buildMonthlySummary(year, month, txns);
  }

  /// 指定年の年次サマリー（月別推移＋カテゴリ別内訳）。
  /// 年レンジは半開区間 [1/1, 翌年1/1)。
  Future<YearlySummary> getYearlySummary(int year) async {
    final txns = await getTransactionsByRange(
      DateTime(year, 1, 1),
      DateTime(year + 1, 1, 1),
    );
    return buildYearlySummary(year, txns);
  }

  /// 全期間の年別合計（取引のある年のみ、昇順）。
  Future<List<PeriodTotal>> getYearlyTotals() async {
    final txns = await getAllTransactions();
    return buildYearlyTotals(txns);
  }

  Future<SplitResult> getSplit(int year, int month) async {
    final txns = await getTransactionsByMonth(year, month);
    final memberList = await getMembers();
    return buildSplit(year, month, txns, memberList);
  }
}
