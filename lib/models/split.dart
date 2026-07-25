class UserBalance {
  final int userId;
  final String userName;
  final double paid;

  /// 正 = 払い過ぎ（受け取るべき）、負 = 払い不足（支払うべき）
  final double balance;

  const UserBalance({
    required this.userId,
    required this.userName,
    required this.paid,
    required this.balance,
  });
}

class SplitResponse {
  final int year;
  final int month;
  final double total;
  final double fairShare;
  final List<UserBalance> users;
  final String settlement;

  const SplitResponse({
    required this.year,
    required this.month,
    required this.total,
    required this.fairShare,
    required this.users,
    required this.settlement,
  });
}
