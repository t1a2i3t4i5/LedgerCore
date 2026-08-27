import 'package:flutter/material.dart';

import '../theme/ledger_tokens.dart';
import 'amount_format.dart';
import 'ratio_bar.dart';

/// カテゴリ別集計の 1 行の最小高さ。
///
/// 通常の文字倍率で数値行、8px の帯、間隔と上下余白を収める 64px を基準に
/// する。端末の文字倍率を上げたときは、文字の下端を切らないよう必要量だけ伸びる。
const double kCategoryBreakdownRowMinHeight = 64;

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

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: kCategoryBreakdownRowMinHeight,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
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
                ConstrainedBox(
                  // 328px 幅・文字倍率 2.0 で 100.0% を欠けさせず、
                  // kMaxAmount も同じ行へ収められる上限。
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      formatYen(amount),
                      maxLines: 1,
                      style: LedgerTokens.amountSmall.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatRatio(amount, total),
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            RatioBar(amount: amount, total: total, color: color),
          ],
        ),
      ),
    );
  }
}
