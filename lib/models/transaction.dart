/// 金額として認める上限（999,999,999,999 円）。
///
/// 上限が無いと桁を打ち続けるだけで `double` が `Infinity` に飽和する。
/// `Infinity` は `> 0` を満たすので、上限を設けないと入力側の validator も
/// DB の CHECK もすり抜け、集計画面の構成比が `Inf / Inf = NaN%` になる
/// （`formatRatio` は分母 0 しか逃がさない）。合計は `¥∞` と表示される。
///
/// 参照するのは次の 3 か所。片方だけ変えると「画面では通るのに保存で落ちる」
/// 状態になるので、必ずここを直す。
///
/// - 入力の桁数制限（`widgets/amount_format.dart`。この値から導出）
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
class TransactionView {
  final int id;
  final int memberId;
  final String memberName;
  final int categoryId;
  final String categoryName;
  final int? categoryColorValue;
  final int? categorySortOrder;

  /// カテゴリが削除できない受け皿かどうか。内訳を管理画面と同じ順に並べるため、
  /// 順序値と一緒に持ち回る。
  final bool categoryIsFixed;
  final double amount;
  final DateTime spentAt;
  final String? memo;

  const TransactionView({
    required this.id,
    required this.memberId,
    required this.memberName,
    required this.categoryId,
    required this.categoryName,
    this.categoryColorValue,
    this.categorySortOrder,
    this.categoryIsFixed = false,
    required this.amount,
    required this.spentAt,
    this.memo,
  });
}

/// 取引の作成・更新に使う入力モデル
class TransactionInput {
  final int memberId;
  final int categoryId;
  final double amount;
  final DateTime spentAt;
  final String? memo;

  const TransactionInput({
    required this.memberId,
    required this.categoryId,
    required this.amount,
    required this.spentAt,
    this.memo,
  });
}
