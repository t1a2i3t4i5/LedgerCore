/// 取引の表示用モデル（端末内DBの JOIN 結果を保持する）
class TransactionResponse {
  final int id;
  final int userId;
  final String userName;
  final int categoryId;
  final String categoryName;
  final double amount;
  final DateTime spentAt;
  final String? memo;

  const TransactionResponse({
    required this.id,
    required this.userId,
    required this.userName,
    required this.categoryId,
    required this.categoryName,
    required this.amount,
    required this.spentAt,
    this.memo,
  });
}

/// 取引の作成・更新に使う入力モデル
class TransactionRequest {
  final int userId;
  final int categoryId;
  final double amount;
  final DateTime spentAt;
  final String? memo;

  const TransactionRequest({
    required this.userId,
    required this.categoryId,
    required this.amount,
    required this.spentAt,
    this.memo,
  });
}
