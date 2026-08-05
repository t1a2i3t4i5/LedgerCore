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
  'その他',
];

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 50)();
}

/// 割り勘の対象者（旧 User / HouseholdMember の代替）
class Members extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 50)();
  TextColumn get mail => text().nullable()();
}

class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get memberId => integer().references(Members, #id)();
  IntColumn get categoryId => integer().references(Categories, #id)();
  // 支出額なので 0 より大きい値のみ許す（入力側の validator と二重に防ぐ）。
  // check() の中で自分自身を参照するのは drift が定める書き方なので、
  // 再帰ゲッターの lint は無視する（実際には評価されず SQL の CHECK 句になる）
  // ignore: recursive_getters
  RealColumn get amount => real().check(amount.isBiggerThanValue(0))();
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
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // デフォルトカテゴリと既定メンバーを投入
          await batch((b) {
            b.insertAll(
              categories,
              _defaultCategories
                  .map((name) => CategoriesCompanion.insert(name: name)),
            );
            b.insert(members, MembersCompanion.insert(name: '自分'));
          });
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v2 で amount に CHECK (amount > 0) を足すためテーブルを作り直す。
            // 作り直しは新テーブルへのコピーを伴うので、制約違反の行が残っていると
            // 移行そのものが失敗する。先に既存データを制約に合う形へ整えておく。
            //
            // 負の金額はマイナス記号の打ち間違いとみなして絶対値に補正し、
            // 0 円は集計上意味を持たない（グラフでも幅 0 のセクションになる）ので削除する。
            await customStatement(
              'UPDATE transactions SET amount = abs(amount) WHERE amount < 0',
            );
            await customStatement('DELETE FROM transactions WHERE amount <= 0');
            // SQLite は既存カラムへの CHECK 追加ができないため、drift の
            // TableMigration でテーブルごと作り直す。experimental 扱いだが
            // 制約変更を伴う移行はこれが drift の標準手段。
            // ignore: experimental_member_use
            await m.alterTable(TableMigration(transactions));
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  // ---- カテゴリ ----
  Future<List<CategoryResponse>> getCategories() async {
    final rows = await (select(categories)
          ..orderBy([(c) => OrderingTerm(expression: c.id)]))
        .get();
    return rows.map((c) => CategoryResponse(id: c.id, name: c.name)).toList();
  }

  Future<void> insertCategory(String name) =>
      into(categories).insert(CategoriesCompanion.insert(name: name));

  Future<void> updateCategoryName(int id, String name) =>
      (update(categories)..where((c) => c.id.equals(id)))
          .write(CategoriesCompanion(name: Value(name)));

  Future<void> deleteCategory(int id) =>
      (delete(categories)..where((c) => c.id.equals(id))).go();

  // ---- メンバー ----
  Future<List<HouseholdMember>> getMembers() async {
    final rows = await (select(members)
          ..orderBy([(m) => OrderingTerm(expression: m.id)]))
        .get();
    return rows
        .map((m) => HouseholdMember(id: m.id, name: m.name, mail: m.mail))
        .toList();
  }

  Future<void> insertMember(String name, {String? mail}) =>
      into(members).insert(
        MembersCompanion.insert(name: name, mail: Value(mail)),
      );

  Future<void> updateMemberName(int id, String name) =>
      (update(members)..where((m) => m.id.equals(id)))
          .write(MembersCompanion(name: Value(name)));

  Future<void> deleteMember(int id) =>
      (delete(members)..where((m) => m.id.equals(id))).go();

  // ---- 取引 ----
  /// 指定月の取引を、メンバー名・カテゴリ名を JOIN して取得する。
  /// 月レンジは半開区間 [月初, 翌月初)。
  Future<List<TransactionResponse>> getTransactionsByMonth(
    int year,
    int month,
  ) =>
      getTransactionsByRange(
        DateTime(year, month, 1),
        DateTime(year, month + 1, 1),
      );

  /// 期間 [start, end) の取引を、メンバー名・カテゴリ名を JOIN して取得する。
  /// 月・年をまたぐ集計の共通入口。
  Future<List<TransactionResponse>> getTransactionsByRange(
    DateTime start,
    DateTime end,
  ) =>
      _selectTransactions(start: start, end: end);

  /// 全期間の取引を取得する（年別集計用）。
  Future<List<TransactionResponse>> getAllTransactions() =>
      _selectTransactions();

  /// 取引をメンバー名・カテゴリ名付きで取得する共通クエリ。
  /// start / end を渡すと半開区間 [start, end) で絞り込む。
  Future<List<TransactionResponse>> _selectTransactions({
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
      return TransactionResponse(
        id: t.id,
        userId: m.id,
        userName: m.name,
        categoryId: c.id,
        categoryName: c.name,
        amount: t.amount,
        spentAt: t.spentAt,
        memo: t.memo,
      );
    }).toList();
  }

  Future<void> insertTransaction(TransactionRequest r) =>
      into(transactions).insert(TransactionsCompanion.insert(
        memberId: r.userId,
        categoryId: r.categoryId,
        amount: r.amount,
        spentAt: r.spentAt,
        memo: Value(r.memo),
      ));

  Future<void> updateTransaction(int id, TransactionRequest r) =>
      (update(transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(
          memberId: Value(r.userId),
          categoryId: Value(r.categoryId),
          amount: Value(r.amount),
          spentAt: Value(r.spentAt),
          memo: Value(r.memo),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<void> deleteTransaction(int id) =>
      (delete(transactions)..where((t) => t.id.equals(id))).go();

  // ---- 集計（端末側で再計算） ----
  Future<MonthlySummaryResponse> getMonthlySummary(int year, int month) async {
    final txns = await getTransactionsByMonth(year, month);
    return buildMonthlySummary(year, month, txns);
  }

  /// 指定年の年次サマリー（月別推移＋カテゴリ別内訳）。
  /// 年レンジは半開区間 [1/1, 翌年1/1)。
  Future<YearlySummaryResponse> getYearlySummary(int year) async {
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

  Future<SplitResponse> getSplit(int year, int month) async {
    final txns = await getTransactionsByMonth(year, month);
    final memberList = await getMembers();
    return buildSplit(year, month, txns, memberList);
  }
}
