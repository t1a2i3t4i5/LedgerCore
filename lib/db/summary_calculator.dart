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

/// 割り勘を計算する。全メンバーで均等割りし、各自の過不足と精算文を求める。
/// サーバの SummaryService.getSplit を端末側に移植したもの。
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
  final memberCount = members.isEmpty ? 1 : members.length;
  final fairShare = _roundHalfUp2(total / memberCount);

  final balances =
      members.map((m) {
        final paid = paidByMember[m.id] ?? 0.0;
        return MemberBalance(
          memberId: m.id,
          memberName: m.name,
          paid: paid,
          balance: paid - fairShare,
        );
      }).toList();

  return SplitResult(
    year: year,
    month: month,
    total: total,
    fairShare: fairShare,
    members: balances,
    settlement: _buildSettlement(balances),
  );
}

/// 小数第2位で四捨五入（HALF_UP）。fairShare は非負なので away-from-zero と一致する。
double _roundHalfUp2(double v) => (v * 100).roundToDouble() / 100;

/// 精算メッセージを生成する。
/// 正の残高（払い過ぎ）＝受け取り側、負の残高（払い不足）＝支払い側。
String _buildSettlement(List<MemberBalance> balances) {
  final creditors =
      balances.where((b) => b.balance > 0).toList()
        ..sort((a, b) => b.balance.compareTo(a.balance));
  final debtors =
      balances.where((b) => b.balance < 0).toList()
        ..sort((a, b) => a.balance.compareTo(b.balance));

  if (creditors.isEmpty || debtors.isEmpty) {
    return '精算不要';
  }

  // 2人の場合の簡易メッセージ
  if (balances.length == 2 && creditors.length == 1 && debtors.length == 1) {
    final debtor = debtors.first;
    final creditor = creditors.first;
    return '${debtor.memberName} → ${creditor.memberName} に ${_yen(debtor.balance.abs())} 円支払う';
  }

  // 3人以上は一覧形式
  final sb = StringBuffer();
  for (final d in debtors) {
    sb.writeln('${d.memberName} は ${_yen(d.balance.abs())} 円の支払いが必要');
  }
  return sb.toString().trim();
}

/// 金額を整数円の文字列にする（表示用）。
String _yen(double v) => v.round().toString();
