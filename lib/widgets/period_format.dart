/// 期間（年・年月）の表示ラベルを組み立てる。
///
/// `'$year年$month月'` を画面ごとに書くと、月選択のヘッダと取引入力の案内で
/// 書式が食い違う。[widgets/amount_format.dart] が金額に対してしているのと同じで、
/// **年月の整形はここだけを通す**。
library;

/// 期間を `2026年7月` の形にする。[month] が null なら `2026年`。
///
/// 月選択のヘッダ・集計画面の合計カード・取引追加画面の案内
/// （日付行の案内テキストと保存後の SnackBar）が使う。
///
/// 取引追加画面の 2 か所を通しているのは、そこが**月選択のヘッダと並べて
/// 読ませる文言**だから。「表示中の 2026年7月 とは別の月です」の年月だけ形が
/// 違うと、同じ画面で 2 通りの書式が同時に出る。
String formatPeriod(int year, int? month) =>
    month == null ? '$year年' : '$year年$month月';

/// 月セレクタの大見出しに載せる短い形。年は下段へ分けるため、`7月` にする。
/// [month] が null なら `2026年`。
String formatPeriodShort(int year, int? month) =>
    month == null ? '$year年' : '$month月';

/// 月セレクタの二段見出しに使う文字列を、同じ書式の入口からまとめて返す。
///
/// [full] は検索・読み上げ用の `2026年7月`、[primary] は大きく描く `7月`、
/// [secondary] はその下へ描く `2026`。画面側で年・月の接尾辞を組み立てない。
({String full, String primary, String secondary}) formatPeriodHeader(
  int year,
  int month,
) => (
  full: formatPeriod(year, month),
  primary: formatPeriodShort(year, month),
  secondary: '$year',
);
