import 'package:flutter/material.dart';

import '../theme/ledger_tokens.dart';
import 'amount_format.dart';
import 'ratio_bar.dart';

/// カテゴリ別集計の 1 行の高さ。
///
/// 28px の数値行、8px の帯、両者の間隔と上下余白を収めつつ、50 文字の
/// カテゴリ名を ellipsis にしても行全体が伸びない値として 64px に固定する。
const double kCategoryBreakdownRowHeight = 64;

/// カテゴリ名・金額・構成比と、その比率を示す帯を 1 行に束ねる。
class CategoryBreakdownRow extends StatelessWidget {
  const CategoryBreakdownRow({
    super.key,
    required this.categoryName,
    required this.amount,
    required this.total,
    required this.color,
  });

  final String categoryName;
  final double amount;
  final double total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: kCategoryBreakdownRowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: [
            SizedBox(
              height: 28,
              child: Row(
                children: [
                  CircleAvatar(radius: 5, backgroundColor: color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      categoryName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatYen(amount),
                    maxLines: 1,
                    style: LedgerTokens.amountSmall.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 42,
                    child: Text(
                      formatRatio(amount, total),
                      maxLines: 1,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            RatioBar(amount: amount, total: total, color: color),
          ],
        ),
      ),
    );
  }
}
