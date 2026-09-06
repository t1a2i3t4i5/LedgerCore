class MemberBalance {
  final int memberId;
  final String memberName;
  final double paid;

  /// このメンバーが最終的に負担する金額。2人でない場合は算出しない。
  final double? share;

  /// 正 = 払い過ぎ（受け取るべき）、負 = 払い不足（支払うべき）。
  /// 2人でない場合は算出しない。
  final double? balance;

  const MemberBalance({
    required this.memberId,
    required this.memberName,
    required this.paid,
    required this.balance,
    required this.share,
  });
}

/// 2人の間で必要になる送金。
class SplitSettlement {
  final MemberBalance from;
  final MemberBalance to;
  final double amount;

  const SplitSettlement({
    required this.from,
    required this.to,
    required this.amount,
  });
}

/// 2人分の負担額と、必要ならその間の送金。
class SplitPair {
  final double lowerShare;
  final double higherShare;
  final SplitSettlement? settlement;

  const SplitPair({
    required this.lowerShare,
    required this.higherShare,
    required this.settlement,
  });
}

class SplitResult {
  final int year;
  final int month;
  final double total;
  final List<MemberBalance> members;

  /// メンバーがちょうど2人のときだけ算出する。
  final SplitPair? pair;

  const SplitResult({
    required this.year,
    required this.month,
    required this.total,
    required this.members,
    required this.pair,
  });
}
