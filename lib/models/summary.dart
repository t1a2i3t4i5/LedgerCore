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

class MonthlySummaryResponse {
  final int year;
  final int month;
  final double total;
  final List<CategorySummaryItem> byCategory;
  final List<UserSummaryItem> byUser;

  const MonthlySummaryResponse({
    required this.year,
    required this.month,
    required this.total,
    required this.byCategory,
    required this.byUser,
  });
}
