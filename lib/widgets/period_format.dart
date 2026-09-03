/// 期間（年・年月）の表示ラベルを組み立てる。
///
/// `'$year年$month月'` を画面ごとに書くと、月選択のヘッダとグラフのツールチップで
/// 書式が食い違う。[widgets/amount_format.dart] が金額に対してしているのと同じで、
/// **年月の整形はここだけを通す**。
///
/// [models/summary.dart] の `PeriodTotal` が表示用の文字列を持たないのは、
/// 軸の幅に応じてどこまで書くかが画面ごとに変わるため。その判断を引き受けるのが
/// このファイルで、長い形（[formatPeriod]）と短い形（[formatPeriodShort]）を
/// 対で持つ。
library;

/// 期間を `2026年7月` の形にする。[month] が null なら `2026年`。
///
/// 月選択のヘッダ・集計画面の合計カード・推移グラフのツールチップ・
/// 取引追加画面の案内（日付行の案内テキストと保存後の SnackBar）が使う。
/// ツールチップが長い形を使うのは、軸ラベルが幅に応じて間引かれるため
/// （間引かれた棒をタップしたときにどの期間か分からなくなる）。
///
/// 取引追加画面の 2 か所を通しているのは、そこが**月選択のヘッダと並べて
/// 読ませる文言**だから。「表示中の 2026年7月 とは別の月です」の年月だけ形が
/// 違うと、同じ画面で 2 通りの書式が同時に出る。
String formatPeriod(int year, int? month) =>
    month == null ? '$year年' : '$year年$month月';

/// 軸に載せる短い形。年の中の月は年が自明なので落とし、`7月` にする。
/// [month] が null なら `2026年`（年別の推移では年が唯一の識別子）。
///
/// 12 本並ぶ月別グラフに `2026年7月` を並べると、360px 幅では 1 本あたり
/// 約 22px しかないので必ず重なる。fl_chart は重なっても例外を出さないため、
/// 長い形を軸に使うと**静かに読めない図**になる。
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
