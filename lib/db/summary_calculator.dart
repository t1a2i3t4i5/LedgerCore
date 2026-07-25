import '../models/transaction.dart';
import '../models/household_member.dart';
import '../models/summary.dart';
import '../models/split.dart';

/// 取引リストから月次サマリー（カテゴリ別・メンバー別）を組み立てる。
/// カテゴリ別は合計金額の降順（サーバの SUM(amount) DESC を踏襲）。
MonthlySummaryResponse buildMonthlySummary(
  int year,
  int month,
  List<TransactionResponse> txns,
) {
  final catTotals = <int, double>{};
  final catNames = <int, String>{};
  final userTotals = <int, double>{};
  final userNames = <int, String>{};

  for (final t in txns) {
    catTotals[t.categoryId] = (catTotals[t.categoryId] ?? 0) + t.amount;
    catNames[t.categoryId] = t.categoryName;
    userTotals[t.userId] = (userTotals[t.userId] ?? 0) + t.amount;
    userNames[t.userId] = t.userName;
  }

  final byCategory = catTotals.entries
      .map((e) => CategorySummaryItem(
            categoryId: e.key,
            categoryName: catNames[e.key]!,
            total: e.value,
          ))
      .toList()
    ..sort((a, b) => b.total.compareTo(a.total));

  final byUser = userTotals.entries
      .map((e) => UserSummaryItem(
            userId: e.key,
            userName: userNames[e.key]!,
            total: e.value,
          ))
      .toList();

  final total = byCategory.fold<double>(0, (s, i) => s + i.total);

  return MonthlySummaryResponse(
    year: year,
    month: month,
    total: total,
    byCategory: byCategory,
    byUser: byUser,
  );
}

/// 割り勘を計算する。全メンバーで均等割りし、各自の過不足と精算文を求める。
/// サーバの SummaryService.getSplit を端末側に移植したもの。
SplitResponse buildSplit(
  int year,
  int month,
  List<TransactionResponse> txns,
  List<HouseholdMember> members,
) {
  final paidByUser = <int, double>{};
  for (final t in txns) {
    paidByUser[t.userId] = (paidByUser[t.userId] ?? 0) + t.amount;
  }

  final total = paidByUser.values.fold<double>(0, (s, v) => s + v);
  final memberCount = members.isEmpty ? 1 : members.length;
  final fairShare = _roundHalfUp2(total / memberCount);

  final balances = members
      .map((m) {
        final paid = paidByUser[m.id] ?? 0.0;
        return UserBalance(
          userId: m.id,
          userName: m.name,
          paid: paid,
          balance: paid - fairShare,
        );
      })
      .toList();

  return SplitResponse(
    year: year,
    month: month,
    total: total,
    fairShare: fairShare,
    users: balances,
    settlement: _buildSettlement(balances),
  );
}

/// 小数第2位で四捨五入（HALF_UP）。fairShare は非負なので away-from-zero と一致する。
double _roundHalfUp2(double v) => (v * 100).roundToDouble() / 100;

/// 精算メッセージを生成する。
/// 正の残高（払い過ぎ）＝受け取り側、負の残高（払い不足）＝支払い側。
String _buildSettlement(List<UserBalance> balances) {
  final creditors = balances.where((b) => b.balance > 0).toList()
    ..sort((a, b) => b.balance.compareTo(a.balance));
  final debtors = balances.where((b) => b.balance < 0).toList()
    ..sort((a, b) => a.balance.compareTo(b.balance));

  if (creditors.isEmpty || debtors.isEmpty) {
    return '精算不要';
  }

  // 2人の場合の簡易メッセージ
  if (balances.length == 2 && creditors.length == 1 && debtors.length == 1) {
    final debtor = debtors.first;
    final creditor = creditors.first;
    return '${debtor.userName} → ${creditor.userName} に ${_yen(debtor.balance.abs())} 円支払う';
  }

  // 3人以上は一覧形式
  final sb = StringBuffer();
  for (final d in debtors) {
    sb.writeln('${d.userName} は ${_yen(d.balance.abs())} 円の支払いが必要');
  }
  return sb.toString().trim();
}

/// 金額を整数円の文字列にする（表示用）。
String _yen(double v) => v.round().toString();
