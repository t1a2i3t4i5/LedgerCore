/// 金額として認める上限（999,999,999,999 円）。
///
/// 上限が無いと桁を打ち続けるだけで `double` が `Infinity` に飽和する。
/// `Infinity` は `> 0` を満たすので、上限を設けないと入力側の validator も
/// DB の CHECK もすり抜け、円グラフの構成比が `Inf / Inf = NaN` になって
/// グラフ全体が壊れる。
///
/// 参照するのは次の 3 か所。片方だけ変えると「画面では通るのに保存で落ちる」
/// 状態になるので、必ずここを直す。
///
/// - 入力の桁数制限（`widgets/amount_input_formatter.dart`。この値から導出）
/// - 入力の validator（`screens/add_transaction_screen.dart`）と
///   フィルターの範囲チェック（`screens/transaction_filter_sheet.dart`）
/// - DB の CHECK 制約（`db/database.dart`）
///
/// **これはスキーマ定義値でもある。** `CREATE TABLE` の CHECK 制約に
/// リテラルとして焼き込まれる（`drift_schemas/drift_schema_v3.json` にも
/// 記録されている）ため、変更するときは値を書き換えるだけでは足りない。
/// `schemaVersion` のインクリメント・`onUpgrade` の追加・固定スキーマの
/// 再生成まで必要（手順は CLAUDE.md「DB スキーマ変更時の注意」）。
/// 怠ると、既存端末は旧 CHECK・新規端末は新 CHECK という食い違いになる。
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
