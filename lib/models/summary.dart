class CategorySummaryItem {
  final int categoryId;
  final String categoryName;
  final int? categoryColorValue;
  final double total;

  const CategorySummaryItem({
    required this.categoryId,
    required this.categoryName,
    this.categoryColorValue,
    required this.total,
  });
}

class MemberSummaryItem {
  final int memberId;
  final String memberName;
  final int? memberColorValue;
  final double total;

  const MemberSummaryItem({
    required this.memberId,
    required this.memberName,
    this.memberColorValue,
    required this.total,
  });
}

class MonthlySummary {
  final int year;
  final int month;
  final double total;
  final int transactionCount;
  final List<CategorySummaryItem> byCategory;
  final List<MemberSummaryItem> byMember;

  const MonthlySummary({
    required this.year,
    required this.month,
    required this.total,
    required this.transactionCount,
    required this.byCategory,
    required this.byMember,
  });
}

/// 月次合計の比較。割合の書式と、前月が0円の表示は表示層で決める。
class MonthlyComparisonView {
  final double previousTotal;
  final double amountChange;

  const MonthlyComparisonView({
    required this.previousTotal,
    required this.amountChange,
  });
}
