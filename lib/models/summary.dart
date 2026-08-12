class CategorySummaryItem {
  final int categoryId;
  final String categoryName;
  final double total;

  const CategorySummaryItem({
    required this.categoryId,
    required this.categoryName,
    required this.total,
  });
}

class UserSummaryItem {
  final int userId;
  final String userName;
  final double total;

  const UserSummaryItem({
    required this.userId,
    required this.userName,
    required this.total,
  });
}

/// 期間（月 or 年）とその合計金額の組。推移グラフの1点に対応する。
/// 表示用のラベルは持たない（軸の幅に応じた整形は画面側の責務）。
class PeriodTotal {
  final int year;

  /// 年別集計では null。月別か年別かの判別にも使う
  final int? month;
  final double total;

  const PeriodTotal({
    required this.year,
    this.month,
    required this.total,
  });
}

class MonthlySummary {
  final int year;
  final int month;
  final double total;
  final List<CategorySummaryItem> byCategory;
  final List<UserSummaryItem> byUser;

  const MonthlySummary({
    required this.year,
    required this.month,
    required this.total,
    required this.byCategory,
    required this.byUser,
  });
}

/// 年次サマリー。月別推移グラフと、その年のカテゴリ別内訳を持つ。
class YearlySummary {
  final int year;
  final double total;

  /// 1〜12月の12件固定。取引の無い月は total が 0
  final List<PeriodTotal> byMonth;

  /// 合計金額の降順
  final List<CategorySummaryItem> byCategory;

  const YearlySummary({
    required this.year,
    required this.total,
    required this.byMonth,
    required this.byCategory,
  });
}
