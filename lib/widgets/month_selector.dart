import 'package:flutter/material.dart';

import '../theme/ledger_tokens.dart';
import 'period_format.dart';

const double _buttonSize = 38;
const double _buttonRadius = 14;
const double _buttonGap = 6;

/// 表示期間の選択 UI。前へ / 次へ / 今へ戻る の 3 ボタンと年月表示を並べる。
///
/// 取引一覧・サマリー・割り勘の 3 画面が同じ形の Row を手で複製していたのを
/// ここに集約したもの。年月の整形は `widgets/period_format.dart` の
/// [formatPeriod] に集約してあるので、書式を変えるときの修正箇所は 1 か所で済む
/// （推移グラフのツールチップと取引追加画面の案内も同じ関数を通る）。
///
/// [month] に null を渡すと `2026年` だけを表示する年単位の選択になる。
/// 集計画面の年モードがこの形で使う。
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

  /// 表示する月（1〜12）。**null なら年だけを表示する。**
  ///
  /// `required` は外していない。省略できるようにすると、渡し忘れが
  /// 年表示に化けて「月選択のつもりが月を出していない」画面が静かに生まれる。
  final int? month;

  /// 左の矢印を押したとき
  final VoidCallback onPrev;

  /// 右の矢印を押したとき
  final VoidCallback onNext;

  /// 「今へ戻る」を押したとき。null なら無効表示になる
  /// （表示中の期間が既に「今」のときは null を渡す）
  final VoidCallback? onToday;

  /// 「今へ戻る」ボタンの tooltip。年単位で使うときは `'今年に戻る'` を渡す。
  final String todayTooltip;

  /// 「今へ戻る」ボタンに表示するラベル。年単位では `'今年'` を渡す。
  ///
  /// 月モードと年モードで同じ右端のボタンを使い、期間を切り替えても
  /// 押す場所が動かないようにする。
  final String todayLabel;

  /// 月または年を大きく描く文字スタイル。null なら 38px の見出し書体
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
    this.todayTooltip = '今月に戻る',
    this.todayLabel = '今月',
    this.style,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        // 年月は Flexible で包む。素の Text で置くと、端末の文字サイズを
        // 大きくしたときに Row が溢れて RenderFlex overflow になる。
        // 畳んででもレイアウトを崩さない側を選んでいる
        Expanded(child: _PeriodTitle(year: year, month: month, style: style)),
        const SizedBox(width: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PeriodButton(
              backgroundColor: colorScheme.primaryContainer,
              foregroundColor: colorScheme.onPrimaryContainer,
              icon: Icons.chevron_left,
              onPressed: onPrev,
            ),
            const SizedBox(width: _buttonGap),
            _PeriodButton(
              backgroundColor: colorScheme.primaryContainer,
              foregroundColor: colorScheme.onPrimaryContainer,
              icon: Icons.chevron_right,
              onPressed: onNext,
            ),
            const SizedBox(width: _buttonGap),
            _TodayButton(
              label: todayLabel,
              tooltip: todayTooltip,
              onPressed: onToday,
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              disabledBackgroundColor: colorScheme.primaryContainer,
              disabledForegroundColor: colorScheme.onPrimaryContainer,
            ),
            ...actions,
          ],
        ),
      ],
    );
  }
}

class _PeriodTitle extends StatelessWidget {
  final int year;
  final int? month;
  final TextStyle? style;

  const _PeriodTitle({required this.year, required this.month, this.style});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final primaryStyle =
        style ??
        textTheme.displaySmall?.copyWith(
          fontSize: 38,
          height: 1,
          letterSpacing: -0.76,
        );

    if (month == null) {
      return Text(
        formatPeriod(year, null),
        style: primaryStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final labels = formatPeriodHeader(year, month!);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: labels.primary,
            // finder と読み上げは従来の長い年月を使う一方、画面には
            // デザイン案どおり月を大きく描く。
            semanticsLabel: labels.full,
            style: primaryStyle,
          ),
          TextSpan(
            text: '\n${labels.secondary}',
            // 上の span が年月全体を読み上げるので、年を重複させない。
            semanticsLabel: '',
            style: LedgerTokens.periodYear,
          ),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _PeriodButton extends StatelessWidget {
  final Color backgroundColor;
  final Color foregroundColor;
  final IconData icon;
  final VoidCallback? onPressed;

  const _PeriodButton({
    required this.backgroundColor,
    required this.foregroundColor,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: _buttonSize,
      child: IconButton(
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: backgroundColor,
          disabledForegroundColor: foregroundColor.withValues(alpha: 0.38),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_buttonRadius),
          ),
        ),
        icon: Icon(icon),
        onPressed: onPressed,
      ),
    );
  }
}

class _TodayButton extends StatelessWidget {
  final String label;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color disabledBackgroundColor;
  final Color disabledForegroundColor;

  const _TodayButton({
    required this.label,
    required this.tooltip,
    required this.onPressed,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.disabledBackgroundColor,
    required this.disabledForegroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: _buttonSize,
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: tooltip,
        style: IconButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: disabledBackgroundColor,
          disabledForegroundColor: disabledForegroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_buttonRadius),
          ),
        ),
        onPressed: onPressed,
        icon: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.5,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              color:
                  onPressed == null ? disabledForegroundColor : foregroundColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
