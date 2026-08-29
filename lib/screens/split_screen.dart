import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/split.dart';
import '../providers/summary_provider.dart';
import '../theme/ledger_tokens.dart';
import '../widgets/amount_format.dart';
import '../widgets/chart_palette.dart';
import '../widgets/ledger_card.dart';
import '../widgets/month_selector.dart';
import '../widgets/ratio_bar.dart';

class SplitScreen extends StatefulWidget {
  const SplitScreen({super.key});

  @override
  State<SplitScreen> createState() => _SplitScreenState();
}

class _SplitScreenState extends State<SplitScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  Future<void> _fetch() async {
    await context.read<SummaryProvider>().fetch();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SummaryProvider>(
      builder: (context, provider, _) {
        return RefreshIndicator(
          onRefresh: _fetch,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 月選択
              MonthSelector(
                year: provider.year,
                month: provider.month,
                onPrev: () => provider.changeMonth(-1),
                onNext: () => provider.changeMonth(1),
                onToday:
                    provider.isCurrentMonth ? null : provider.goToCurrentMonth,
              ),
              const SizedBox(height: 8),

              if (provider.loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (provider.error != null)
                Center(
                  child: Text(
                    'エラー: ${provider.error}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                )
              else if (provider.split == null)
                const Center(child: Text('データがありません'))
              else ...[
                // 合計・均等割
                LedgerCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _AmountSummary(
                          label: '合計',
                          amount: provider.split!.total,
                        ),
                      ),
                      SizedBox(
                        height: 48,
                        child: VerticalDivider(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      Expanded(
                        child: _AmountSummary(
                          label: '一人当たり',
                          amount: provider.split!.fairShare,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 精算結果
                DecoratedBox(
                  key: const ValueKey('settlement-card'),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(
                      LedgerTokens.cardRadiusLarge,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.swap_horiz,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '精算方法',
                              style: Theme.of(
                                context,
                              ).textTheme.titleMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          provider.split!.settlement,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context).colorScheme.onPrimary,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // メンバー別支払い
                Text(
                  'メンバー別支払い状況',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                LedgerCard(
                  child: Column(
                    children: [
                      for (final (index, member)
                          in provider.split!.members.indexed) ...[
                        if (index > 0)
                          Divider(
                            height: 32,
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        _MemberBalanceRow(
                          key: ValueKey('member-balance-${member.memberId}'),
                          member: member,
                          total: provider.split!.total,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _AmountSummary extends StatelessWidget {
  const _AmountSummary({required this.label, required this.amount});

  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 2),
        Text(
          formatYen(amount),
          key: ValueKey('summary-amount-$label'),
          style: LedgerTokens.amountRow,
        ),
      ],
    );
  }
}

class _MemberBalanceRow extends StatelessWidget {
  const _MemberBalanceRow({
    super.key,
    required this.member,
    required this.total,
  });

  final MemberBalance member;
  final double total;

  @override
  Widget build(BuildContext context) {
    final color = memberColor(member.memberId);
    final (status, balanceColor) = switch (member.balance) {
      > 0 => ('受け取り', LedgerTokens.balancePositive),
      < 0 => ('支払い', LedgerTokens.balanceNegative),
      _ => ('均等', LedgerTokens.balanceEven),
    };
    // 黒字だけ + を前置する。負値は formatYen が
    // ¥-1,000 の形で符号を出す。
    final balance =
        member.balance > 0
            ? '+${formatYen(member.balance)}'
            : formatYen(member.balance);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(radius: 5, backgroundColor: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                member.memberName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              status,
              style: const TextStyle(fontSize: 11, color: LedgerTokens.subtext),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            balance,
            key: ValueKey('member-balance-amount-${member.memberId}'),
            style: LedgerTokens.amountRow.copyWith(color: balanceColor),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '支払済み',
          style: TextStyle(fontSize: 12, color: LedgerTokens.bodyMuted),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            formatYen(member.paid),
            key: ValueKey('member-paid-${member.memberId}'),
            style: LedgerTokens.amountSmall,
          ),
        ),
        const SizedBox(height: 8),
        RatioBar(amount: member.paid, total: total, color: color),
      ],
    );
  }
}
