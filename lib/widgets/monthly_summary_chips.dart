import 'package:flutter/material.dart';

import '../models/summary.dart';
import '../theme/ledger_tokens.dart';
import 'amount_format.dart';

/// 合計カードの補足。操作は持たず、狭い幅では次の行へ折り返す。
class MonthlySummaryChips extends StatelessWidget {
  const MonthlySummaryChips({
    super.key,
    required this.comparison,
    required this.transactionCount,
  });

  final MonthlyComparisonView comparison;
  final int transactionCount;

  String get _changeLabel {
    if (comparison.previousTotal == 0) return '先月比 —';
    final ratio = formatRatio(
      comparison.amountChange.abs(),
      comparison.previousTotal,
    );
    // 小数1桁で0になる差額には符号を付けず、+0.0% / -0.0%を避ける。
    final sign =
        ratio == '0.0%'
            ? ''
            : comparison.amountChange > 0
            ? '+'
            : '-';
    return '先月比 $sign$ratio';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _badge(
          context,
          label: _changeLabel,
          background: colors.secondaryContainer,
          foreground: LedgerTokens.comparisonText,
          tooltip:
              comparison.previousTotal == 0
                  ? '前月の支出が0円のため、先月比は計算できません'
                  : '表示月の支出を前月の1か月分と比較しています',
        ),
        _badge(
          context,
          label: '$transactionCount件',
          background: LedgerTokens.countSurface,
          foreground: colors.onSurfaceVariant,
          tooltip: '表示月の取引件数',
        ),
      ],
    );
  }

  Widget _badge(
    BuildContext context, {
    required String label,
    required Color background,
    required Color foreground,
    required String tooltip,
  }) => Tooltip(
    message: tooltip,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(LedgerTokens.pillRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: foreground),
        ),
      ),
    ),
  );
}
