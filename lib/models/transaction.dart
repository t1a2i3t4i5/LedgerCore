/// 金額として認める上限（999,999,999,999 円）。
///
/// 上限が無いと桁を打ち続けるだけで `double` が `Infinity` に飽和する。
/// `Infinity` は `> 0` を満たすので、上限を設けないと入力側の validator も
/// DB の CHECK もすり抜け、円グラフの構成比が `Inf / Inf = NaN` になって
/// グラフ全体が壊れる。
///
/// 入力欄（`add_transaction_screen.dart`）と DB の CHECK 制約
/// （`database.dart`）の両方がこの値を参照する。片方だけ変えると
/// 「画面では通るのに保存で落ちる」状態になるので、必ずここを直す。
const kMaxAmount = 999999999999.0;

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
