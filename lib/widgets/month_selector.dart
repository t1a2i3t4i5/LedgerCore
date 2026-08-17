import 'package:flutter/material.dart';

import 'period_format.dart';

/// 表示月の選択 UI。前月 / 翌月 / 今月に戻る の 3 ボタンと年月表示を並べる。
///
/// 取引一覧・サマリー・割り勘の 3 画面が同じ形の Row を手で複製していたのを
/// ここに集約したもの。年月の整形そのものは [formatPeriod]（`period_format.dart`）
/// に置いてあるので、書式を変えるときの修正箇所は 1 か所で済む
/// （推移グラフのツールチップと取引追加画面の案内も同じ関数を通る）。
///
/// [AppDatabase] も Provider も参照せず、表示する値とコールバックを引数で
/// 受け取るだけにしてある（`widgets/` の他の部品と同じ条件）。おかげで
/// DB を組み立てずにウィジェットテストできる。
///
/// 外側の余白は持たない。置かれた場所のレイアウトに従わせるため、必要なら
/// 呼び出し側で [Padding] に包む。
class MonthSelector extends StatelessWidget {
  /// 表示する年
  final int year;

  /// 表示する月（1〜12）
  final int month;

  /// 左の矢印を押したとき
  final VoidCallback onPrev;

  /// 右の矢印を押したとき
  final VoidCallback onNext;

  /// 「今月に戻る」を押したとき。null なら無効表示になる
  /// （表示中の月が既に今月のときは null を渡す）
  final VoidCallback? onToday;

  /// 年月の文字スタイル。null なら `titleLarge`
  final TextStyle? style;

  /// 右端に追加で並べるウィジェット（取引一覧のフィルターボタンなど）
  final List<Widget> actions;

  const MonthSelector({
    super.key,
    required this.year,
    required this.month,
    required this.onPrev,
    required this.onNext,
    this.onToday,
    this.style,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: onPrev,
        ),
        // 年月は Flexible で包む。素の Text で置くと、端末の文字サイズを
        // 大きくしたときに Row が溢れて RenderFlex overflow になる。
        // 畳んででもレイアウトを崩さない側を選んでいる
        Flexible(
          child: Text(
            formatPeriod(year, month),
            style: style ?? Theme.of(context).textTheme.titleLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: onNext,
            ),
            IconButton(
              icon: const Icon(Icons.today),
              tooltip: '今月に戻る',
              onPressed: onToday,
            ),
            ...actions,
          ],
        ),
      ],
    );
  }
}
