import 'package:flutter/material.dart';

import '../models/split.dart';
import '../theme/ledger_tokens.dart';
import 'amount_format.dart';

/// 月の割り勘結果をホームに表示する。計算とデータ取得は行わない。
class SettlementSummaryCard extends StatelessWidget {
  const SettlementSummaryCard({super.key, required this.split, this.onTap});

  final SplitResult split;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final creditors = split.members.where((member) => member.balance > 0);
    final debtors = split.members.where((member) => member.balance < 0);
    final needsSettlement = creditors.isNotEmpty && debtors.isNotEmpty;
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: LedgerTokens.balancePositiveSurface,
      borderRadius: BorderRadius.circular(LedgerTokens.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (split.members.length < 2)
                Text(
                  split.members.isEmpty
                      ? 'メンバーを登録すると精算できます'
                      : '精算には2人以上のメンバーが必要です',
                )
              else if (!needsSettlement)
                const Text('精算不要')
              else if (split.members.length == 2)
                _payment(
                  context,
                  '${debtors.single.memberName} → ${creditors.single.memberName} に ',
                  debtors.single.balance.abs(),
                )
              else ...[
                const Text('メンバーごとの支払い額'),
                // 3人以上の送金先は既存の計算結果に無い。新たに割り当てず、
                // 各メンバーの不足額を省略せずに並べる。
                for (final debtor in debtors) ...[
                  const SizedBox(height: 8),
                  _payment(
                    context,
                    '${debtor.memberName} は ',
                    debtor.balance.abs(),
                  ),
                ],
              ],
              if (onTap != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        needsSettlement ? '精算する' : '割り勘を見る',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: colorScheme.primary),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _payment(BuildContext context, String label, double amount) {
    // 文と金額を一続きで折り返し、文字倍率を上げても固定高で切らない。
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: label),
          TextSpan(text: formatYen(amount), style: LedgerTokens.amountSmall),
        ],
      ),
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }
}
