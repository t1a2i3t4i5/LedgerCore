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
  RealColumn get amount => real()();
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
  int get schemaVersion => 1;

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
  ) async {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);

    final query = select(transactions).join([
      innerJoin(members, members.id.equalsExp(transactions.memberId)),
      innerJoin(categories, categories.id.equalsExp(transactions.categoryId)),
    ])
      ..where(transactions.spentAt.isBiggerOrEqualValue(start) &
          transactions.spentAt.isSmallerThanValue(end));

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

  Future<SplitResponse> getSplit(int year, int month) async {
    final txns = await getTransactionsByMonth(year, month);
    final memberList = await getMembers();
    return buildSplit(year, month, txns, memberList);
  }
}
