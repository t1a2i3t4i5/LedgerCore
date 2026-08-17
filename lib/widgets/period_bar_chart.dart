import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/summary.dart';
import 'amount_format.dart';
import 'chart_palette.dart';
import 'period_format.dart';

/// 目盛りの区切り数。0 を含めて [_tickCount] + 1 本のラベルが並ぶ。
const int _tickCount = 4;

/// 軸ラベルの文字サイズ。12 本並ぶ月別グラフに合わせた下限。
const double _labelFontSize = 10;

/// X 軸ラベルの帯の高さ。`'12月'` 1 行ぶん。
const double _bottomTitleHeight = 22;

/// Y 軸が本体を食い潰さない上限（幅に対する割合）。
/// ここに当たったらラベル側を ellipsis で畳む。畳まないとグラフ本体が消える。
const double _maxAxisWidthRatio = 0.4;

/// 期間別の合計を棒グラフで描く。月別・年別で共用する。
///
/// [items] の並び順がそのまま X 軸の左→右になる。月別か年別かは
/// `PeriodTotal.month` が null かどうかで決まり、ラベルの形が変わる
/// （`widgets/period_format.dart` を参照）。
///
/// `AppDatabase` も Provider も参照しない。表示するデータを引数で受け取るだけに
/// してあるので、DB を組み立てずにウィジェットテストできる。
///
/// **必ず固定高さを持つ。** 集計画面はこのウィジェットを `ListView` の子として
/// 置くが、`ListView` の子は高さ制約が非有界なので、高さを自分で決めないと
/// レイアウトが assert で落ちる。
class PeriodBarChart extends StatelessWidget {
  /// 描画する期間別合計。並び順が X 軸の並び順になる。
  final List<PeriodTotal> items;

  /// グラフ本体の高さ。
  final double height;

  const PeriodBarChart({
    super.key,
    required this.items,
    this.height = 200,
  });

  @override
  Widget build(BuildContext context) {
    final maxValue = items.fold<double>(0, (m, i) => math.max(m, i.total));

    // 全件 0 のときに描くと、高さ 0 の棒が並ぶだけの図に軸だけが残る。
    // 取引ゼロの月を含む年は珍しくないので、明示的に受け皿を出す
    if (items.isEmpty || maxValue <= 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('データがありません')),
      );
    }

    final barColor = trendColor(Theme.of(context).colorScheme);
    final labelStyle = (Theme.of(context).textTheme.bodySmall ??
            const TextStyle())
        .copyWith(fontSize: _labelFontSize);
    final textScaler = MediaQuery.textScalerOf(context);

    // 目盛りを 1/2/5 × 10^n の倍数に丸める。formatYenAxis が小数第 1 位までで
    // 足りるのはこの丸めが前提（目盛り幅が最大値の 1/4 以上になる）
    final interval = _niceInterval(maxValue);
    final tickCount = (maxValue / interval).ceil();
    final maxY = tickCount * interval;

    // Y 軸の予約幅は実寸から決める。固定値にすると kMaxAmount で足りず、
    // 広く取り過ぎると 360px でグラフ本体が痩せる
    final axisLabelWidth = [
      for (var i = 0; i <= tickCount; i++)
        _measure(formatYenAxis(i * interval), labelStyle, textScaler),
    ].reduce(math.max);

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final reserved = math.min(
            axisLabelWidth + 12,
            constraints.maxWidth * _maxAxisWidthRatio,
          );
          // 棒 1 本あたりに割り当てられる横幅
          final slot = (constraints.maxWidth - reserved) / items.length;

          final xLabelWidth = items
              .map((i) => _measure(_shortLabel(i), labelStyle, textScaler))
              .reduce(math.max);
          // 隣のラベルと重なるなら間引く。fl_chart は重なっても例外を出さない
          final stride = slot <= 0
              ? items.length
              : math.max(1, ((xLabelWidth + 4) / slot).ceil());
          final barWidth = (slot * 0.5).clamp(3.0, 24.0);

          return BarChart(
            BarChartData(
              minY: 0,
              maxY: maxY,
              alignment: BarChartAlignment.spaceEvenly,
              barGroups: [
                for (var index = 0; index < items.length; index++)
                  BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        // 0 の期間も rod を残す。棒が消えるだけで X 軸には並ぶ
                        toY: items[index].total,
                        color: barColor,
                        width: barWidth,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(2),
                        ),
                      ),
                    ],
                  ),
              ],
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: interval,
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                // 既定では 4 辺すべてに数字が出る。上と右は明示的に消す
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: interval,
                    reservedSize: reserved,
                    getTitlesWidget: (value, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(
                        formatYenAxis(value),
                        style: labelStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: _bottomTitleHeight,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= items.length) {
                        return const SizedBox.shrink();
                      }
                      // 棒グラフの X 軸には SideTitles.interval が効かない
                      // （fl_chart が barGroups を全数走査して 1 群 1 ラベルを
                      // 作るため）。間引きはここで自前でやるしかない
                      if (!_showLabelAt(index, items.length, stride)) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(
                          _shortLabel(items[index]),
                          style: labelStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => barColor,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final item = items[group.x];
                    return BarTooltipItem(
                      // 軸ラベルは間引かれることがあるので、ツールチップ側は
                      // 年月まで出す長い形にする。金額は実額なので formatYen
                      '${formatPeriod(item.year, item.month)}\n'
                      '${formatYen(item.total)}',
                      TextStyle(
                        // 背景に棒と同じ色を敷くので、文字色は輝度から選ぶ
                        color: labelColorOn(barColor),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 軸に載せる短いラベル。
String _shortLabel(PeriodTotal item) =>
    formatPeriodShort(item.year, item.month);

/// [index] のラベルを描くか。
///
/// **末尾を起点に間引く。** 先頭起点にすると、間引きが効いた瞬間に右端
/// （＝いちばん新しい期間）のラベルが落ちることがある。読み手が最初に見るのは
/// 直近なので、そこは必ず残す。
bool _showLabelAt(int index, int count, int stride) =>
    (count - 1 - index) % stride == 0;

/// [rawMax] を [_tickCount] 等分した幅を 1/2/5 × 10^n に切り上げる。
///
/// 目盛り値がこの倍数になるので、万・億・兆に直しても小数 1 桁で収まる
/// （目盛り幅は最大値の 1/4 以上、つまり単位の 0.2 以上になる）。
/// [formatYenAxis] の dartdoc が前提にしているのはこの丸め。
double _niceInterval(double rawMax) {
  if (rawMax <= 0) return 1;
  final raw = rawMax / _tickCount;
  final magnitude =
      math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final n = raw / magnitude;
  final step = n <= 1
      ? 1.0
      : n <= 2
          ? 2.0
          : n <= 5
              ? 5.0
              : 10.0;
  return step * magnitude;
}

/// [text] を実際のスタイルで描いたときの幅。
/// 端末の文字サイズ設定を反映させるため [textScaler] まで渡す。
double _measure(String text, TextStyle style, TextScaler textScaler) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
  )..layout();
  return painter.width;
}
