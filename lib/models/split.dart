class MemberBalance {
  final int memberId;
  final String memberName;
  final double paid;

  /// 正 = 払い過ぎ（受け取るべき）、負 = 払い不足（支払うべき）
  final double balance;

  const MemberBalance({
    required this.memberId,
    required this.memberName,
    required this.paid,
    required this.balance,
  });
}

class SplitResult {
  final int year;
  final int month;
  final double total;
  final double fairShare;
  final List<MemberBalance> members;
  final String settlement;

  const SplitResult({
    required this.year,
    required this.month,
    required this.total,
    required this.fairShare,
    required this.members,
    required this.settlement,
  });
}
