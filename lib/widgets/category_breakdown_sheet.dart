import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/summary.dart';
import 'category_breakdown_row.dart';
import 'chart_palette.dart';
import 'period_format.dart';

/// 月内のカテゴリ別支出を全件表示する BottomSheet。
///
/// [items] はホームで並べ替え済みのスナップショットを受け取る。ここでは DB や
/// Provider を参照せず、表示中に並び順や内容を更新しない。
class CategoryBreakdownSheet extends StatelessWidget {
  const CategoryBreakdownSheet({
    super.key,
    required this.items,
    required this.total,
    required this.year,
    required this.month,
  });

  final List<CategorySummaryItem> items;
  final double total;
  final int year;
  final int month;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        // showDragHandle が本文の外側に確保する48pxを先に引き、シート全体を
        // 画面高の80%以内に収める。SafeAreaもこの制約の内側に含める。
        maxHeight: math.max(
          0.0,
          MediaQuery.sizeOf(context).height * 0.8 - kMinInteractiveDimension,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${formatPeriod(year, month)}のカテゴリ別',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: '閉じる',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return CategoryBreakdownRow(
                      categoryName: item.categoryName,
                      amount: item.total,
                      total: total,
                      color: categoryColor(
                        item.categoryId,
                        colorValue: item.categoryColorValue,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
