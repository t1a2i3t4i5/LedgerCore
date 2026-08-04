import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/summary.dart';
import 'chart_palette.dart';

/// 構成比がこの割合未満のセクションはラベルを出さない。
/// 狭い扇形に % を載せると隣と重なって読めないため（カテゴリ名は凡例に必ず出る）。
const double _minLabelRatio = 0.05;

final _fmt = NumberFormat('#,###', 'ja_JP');

/// カテゴリ別の構成比を描くドーナツグラフ。
/// DB には触れず、表示するデータはすべて引数で受け取る。
class CategoryPieChart extends StatelessWidget {
  /// 描画するカテゴリ別合計。並び順はそのままセクションの順序になる
  final List<CategorySummaryItem> items;

  /// グラフ部分の高さ。ListView の中でも崩れないよう固定にする
  final double chartHeight;

  const CategoryPieChart({
    super.key,
    required this.items,
    this.chartHeight = 220,
  });

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
          height: chartHeight,
          child: PieChart(
            PieChartData(
              sections: items.map((item) => _section(item, total)).toList(),
              centerSpaceRadius: 40,
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
      radius: 56,
      showTitle: ratio >= _minLabelRatio,
      title: '${(ratio * 100).toStringAsFixed(1)}%',
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
        Text(
          '${item.categoryName} ¥${_fmt.format(item.total)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
