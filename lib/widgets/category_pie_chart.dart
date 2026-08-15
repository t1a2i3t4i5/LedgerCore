import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/summary.dart';
import 'amount_format.dart';
import 'chart_palette.dart';

/// 構成比がこの割合未満のセクションはラベルを出さない。
/// 狭い扇形に % を載せると隣と重なって読めないため（カテゴリ名は凡例に必ず出る）。
const double _minLabelRatio = 0.05;

/// ドーナツ中央の穴の半径。
const double _centerSpaceRadius = 40;

/// ドーナツの帯の幅。
const double _sectionRadius = 56;

/// グラフ部分の高さ。ListView の中でも崩れないよう固定にする。
/// 円の直径は (_centerSpaceRadius + _sectionRadius) * 2 = 192px なので、
/// これより小さくすると円の上下が切れる。fl_chart は Canvas 直描きなので
/// はみ出しても例外も overflow の縞模様も出ず静かに切れる点に注意。
const double _chartHeight = 220;

/// カテゴリ別の構成比を描くドーナツグラフ。
/// DB には触れず、表示するデータはすべて引数で受け取る。
class CategoryPieChart extends StatelessWidget {
  /// 描画するカテゴリ別合計。並び順はそのままセクションの順序になる
  final List<CategorySummaryItem> items;

  const CategoryPieChart({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final total = items.fold<double>(0, (sum, i) => sum + i.total);

    // 合計 0 のときは割合を計算できないのでグラフを組み立てない
    if (items.isEmpty || total <= 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('データがありません')),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _chartHeight,
          child: PieChart(
            PieChartData(
              sections: items.map((item) => _section(item, total)).toList(),
              centerSpaceRadius: _centerSpaceRadius,
              sectionsSpace: 2,
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 項目が増えても折り返すので横方向にはみ出さない
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: items.map((item) => _Legend(item: item)).toList(),
        ),
      ],
    );
  }

  PieChartSectionData _section(CategorySummaryItem item, double total) {
    final color = categoryColor(item.categoryId);
    final ratio = item.total / total;
    return PieChartSectionData(
      value: item.total,
      color: color,
      radius: _sectionRadius,
      showTitle: ratio >= _minLabelRatio,
      title: formatRatio(item.total, total),
      titleStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: labelColorOn(color),
      ),
    );
  }
}

/// 凡例の 1 項目（色の四角＋カテゴリ名＋金額）。
class _Legend extends StatelessWidget {
  final CategorySummaryItem item;

  const _Legend({required this.item});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: categoryColor(item.categoryId),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        // カテゴリ名はユーザーが編集でき DB 上は 50 文字まで入るので、
        // Flexible で包まないと 25 文字あたりから横にはみ出す
        Flexible(
          child: Text(
            '${item.categoryName} ${formatYen(item.total)}',
            style: Theme.of(context).textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
