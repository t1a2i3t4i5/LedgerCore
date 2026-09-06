import '../models/transaction.dart';
import '../models/household_member.dart';
import '../models/summary.dart';
import '../models/split.dart';

/// 取引リストから月次サマリー（カテゴリ別・メンバー別）を組み立てる。
/// カテゴリ別はカテゴリ管理で保存した順序。
MonthlySummary buildMonthlySummary(
  int year,
  int month,
  List<TransactionView> txns,
) {
  final memberTotals = <int, double>{};
  final memberNames = <int, String>{};

  for (final t in txns) {
    memberTotals[t.memberId] = (memberTotals[t.memberId] ?? 0) + t.amount;
    memberNames[t.memberId] = t.memberName;
  }

  final byCategory = _buildCategoryItems(txns);

  final byMember =
      memberTotals.entries
          .map(
            (e) => MemberSummaryItem(
              memberId: e.key,
              memberName: memberNames[e.key]!,
              total: e.value,
            ),
          )
          .toList();

  final total = byCategory.fold<double>(0, (s, i) => s + i.total);

  return MonthlySummary(
    year: year,
    month: month,
    total: total,
    transactionCount: txns.length,
    byCategory: byCategory,
    byMember: byMember,
  );
}

/// 同じ月次集計の純関数で求めた当月・前月の合計から差額を求める。
MonthlyComparisonView buildMonthlyComparison(
  MonthlySummary current,
  MonthlySummary previous,
) => MonthlyComparisonView(
  previousTotal: previous.total,
  amountChange: current.total - previous.total,
);

/// 指定年の年次サマリーを組み立てる。
/// 月別合計は取引の無い月も 0 で埋めた 12 件を返す（グラフの X 軸を欠けさせないため）。
/// txns に他の年の取引が混ざっていても、指定年のものだけを集計する。
YearlySummary buildYearlySummary(int year, List<TransactionView> txns) {
  final inYear = txns.where((t) => t.spentAt.year == year).toList();

  final monthTotals = List<double>.filled(12, 0);
  for (final t in inYear) {
    monthTotals[t.spentAt.month - 1] += t.amount;
  }

  final byMonth = List.generate(
    12,
    (i) => PeriodTotal(year: year, month: i + 1, total: monthTotals[i]),
  );

  return YearlySummary(
    year: year,
    total: monthTotals.fold<double>(0, (s, v) => s + v),
    byMonth: byMonth,
    byCategory: _buildCategoryItems(inYear),
  );
}

/// 年別の合計金額を求める。取引のある年だけを年の昇順で返す。
List<PeriodTotal> buildYearlyTotals(List<TransactionView> txns) {
  final yearTotals = <int, double>{};
  for (final t in txns) {
    yearTotals[t.spentAt.year] = (yearTotals[t.spentAt.year] ?? 0) + t.amount;
  }

  final years = yearTotals.keys.toList()..sort();
  return years.map((y) => PeriodTotal(year: y, total: yearTotals[y]!)).toList();
}

/// カテゴリ別の合計をカテゴリ管理で保存した順序に組み立てる。
List<CategorySummaryItem> _buildCategoryItems(List<TransactionView> txns) {
  final catTotals = <int, double>{};
  final catNames = <int, String>{};
  final catColors = <int, int?>{};
  final catOrders = <int, int>{};
  final catFixed = <int, bool>{};

  for (final t in txns) {
    catTotals[t.categoryId] = (catTotals[t.categoryId] ?? 0) + t.amount;
    catNames[t.categoryId] = t.categoryName;
    catColors[t.categoryId] = t.categoryColorValue;
    catOrders[t.categoryId] = t.categorySortOrder ?? t.categoryId;
    catFixed[t.categoryId] = t.categoryIsFixed;
  }

  return catTotals.entries
      .map(
        (e) => CategorySummaryItem(
          categoryId: e.key,
          categoryName: catNames[e.key]!,
          categoryColorValue: catColors[e.key],
          total: e.value,
        ),
      )
      .toList()
    ..sort((a, b) {
      // 固定カテゴリはカテゴリ管理と同じく常に最後に置く。sort_order だけで
      // 比べると、後から追加したカテゴリが受け皿より下に来て順序がずれる。
      final byFixed = (catFixed[a.categoryId] ?? false ? 1 : 0).compareTo(
        catFixed[b.categoryId] ?? false ? 1 : 0,
      );
      if (byFixed != 0) return byFixed;
      final byOrder = catOrders[a.categoryId]!.compareTo(
        catOrders[b.categoryId]!,
      );
      return byOrder != 0 ? byOrder : a.categoryId.compareTo(b.categoryId);
    });
}

/// 2人の割り勘を計算し、各自の整数円の負担と送金を求める。
SplitResult buildSplit(
  int year,
  int month,
  List<TransactionView> txns,
  List<HouseholdMember> members,
) {
  final paidByMember = <int, double>{};
  for (final t in txns) {
    paidByMember[t.memberId] = (paidByMember[t.memberId] ?? 0) + t.amount;
  }

  final total = paidByMember.values.fold<double>(0, (s, v) => s + v);
  if (members.length != 2) {
    return SplitResult(
      year: year,
      month: month,
      total: total,
      members:
          members
              .map(
                (member) => MemberBalance(
                  memberId: member.id,
                  memberName: member.name,
                  paid: paidByMember[member.id] ?? 0,
                  share: null,
                  balance: null,
                ),
              )
              .toList(),
      pair: null,
    );
  }

  final first = members.first;
  final second = members.last;
  final firstPaid = paidByMember[first.id] ?? 0;
  final secondPaid = paidByMember[second.id] ?? 0;
  final lowerShare = (total / 2).floorToDouble();
  final higherShare = total - lowerShare;

  // 合計が奇数なら、立替額の少ない側が1円多く負担する。合計が奇数の
  // とき2人の立替額は必ず異なるため、端数がある場面で同額にはならない。
  final firstShare = firstPaid < secondPaid ? higherShare : lowerShare;
  final secondShare = total - firstShare;
  final balances = [
    MemberBalance(
      memberId: first.id,
      memberName: first.name,
      paid: firstPaid,
      share: firstShare,
      balance: firstPaid - firstShare,
    ),
    MemberBalance(
      memberId: second.id,
      memberName: second.name,
      paid: secondPaid,
      share: secondShare,
      balance: secondPaid - secondShare,
    ),
  ];

  final debtor = balances.where((member) => member.balance! < 0).firstOrNull;
  final creditor = balances.where((member) => member.balance! > 0).firstOrNull;
  final settlement =
      debtor == null || creditor == null
          ? null
          : SplitSettlement(
            from: debtor,
            to: creditor,
            amount: debtor.balance!.abs(),
          );

  return SplitResult(
    year: year,
    month: month,
    total: total,
    members: balances,
    pair: SplitPair(
      lowerShare: lowerShare,
      higherShare: higherShare,
      settlement: settlement,
    ),
  );
}
