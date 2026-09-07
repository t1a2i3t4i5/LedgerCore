import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/summary.dart';
import '../providers/summary_provider.dart';
import '../theme/ledger_tokens.dart';
import '../widgets/amount_format.dart';
import '../widgets/category_breakdown_row.dart';
import '../widgets/chart_palette.dart';
import '../widgets/ledger_card.dart';
import '../widgets/month_selector.dart';
import '../widgets/monthly_summary_chips.dart';
import '../widgets/period_format.dart';
import '../widgets/settlement_summary_card.dart';

/// デスクトップ幅でも名前と金額を 1 行として追える本文幅。
const double _maxContentWidth = 480;

class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key, this.onOpenSplit});

  final VoidCallback? onOpenSplit;

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
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
          // ListView 自体は画面幅いっぱいに保ち、padding だけを広げる。
          // スクロール領域を細くしないので、デスクトップの余白上でも
          // ホイール操作と RefreshIndicator が効く。
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontal = math.max(
                16.0,
                (constraints.maxWidth - _maxContentWidth) / 2,
              );
              return ListView(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontal,
                  vertical: 16,
                ),
                // 取引ゼロの月は中身が短い。既定の physics だと
                // スクロールできる長さが無いときに引っ張っても反応しない
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  MonthSelector(
                    year: provider.year,
                    month: provider.month,
                    onPrev: () => provider.changeMonth(-1),
                    onNext: () => provider.changeMonth(1),
                    onToday:
                        provider.isCurrentMonth
                            ? null
                            : provider.goToCurrentMonth,
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
                  else
                    ..._monthBody(context, provider),
                ],
              );
            },
          ),
        );
      },
    );
  }

  /// 単月。合計・カテゴリ別・メンバー別。
  List<Widget> _monthBody(BuildContext context, SummaryProvider provider) {
    final summary = provider.summary;
    if (summary == null) return const [_EmptySection()];

    return [
      _totalCard(
        context,
        summary.total,
        label:
            provider.isCurrentMonth
                ? '今月の支出'
                : '${formatPeriod(provider.year, provider.month)}の支出',
        footer:
            provider.comparison == null
                ? null
                : MonthlySummaryChips(
                  comparison: provider.comparison!,
                  transactionCount: summary.transactionCount,
                ),
      ),
      const SizedBox(height: 16),
      if (provider.split case final split?) ...[
        SettlementSummaryCard(split: split, onTap: widget.onOpenSplit),
        const SizedBox(height: 16),
      ],
      ..._categorySection(context, summary.byCategory, summary.total),
      const Divider(),
      const SizedBox(height: 8),
      ..._memberSection(context, summary.byMember),
    ];
  }

  Widget _totalCard(
    BuildContext context,
    double total, {
    required String label,
    Widget? footer,
  }) {
    return LedgerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                formatYen(total),
                style: LedgerTokens.amountLarge.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
          if (footer != null) ...[const SizedBox(height: 16), footer],
        ],
      ),
    );
  }

  /// カテゴリ別リスト。構成比の分母を [total] で受ける。
  List<Widget> _categorySection(
    BuildContext context,
    List<CategorySummaryItem> items,
    double total,
  ) {
    return [
      Text('カテゴリ別', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      // 取引ゼロの期間でも summary 自体は非 null で返る（byCategory が空、
      // total が 0）ので、上位の null 判定では受からない。
      // この分岐が無いと見出しの下が無言で空白になる
      if (items.isEmpty)
        const _EmptySection()
      else
        ...items.map(
          (item) => CategoryBreakdownRow(
            categoryName: item.categoryName,
            amount: item.total,
            total: total,
            // カテゴリごとに決まる色を画面側で解決して渡す。
            color: categoryColor(
              item.categoryId,
              colorValue: item.categoryColorValue,
            ),
          ),
        ),
    ];
  }

  /// メンバー別リスト。
  List<Widget> _memberSection(
    BuildContext context,
    List<MemberSummaryItem> items,
  ) {
    return [
      Text('メンバー別', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      // カテゴリ別と同じ理由の空分岐。取引ゼロの月では byMember も空になる
      if (items.isEmpty)
        const _EmptySection()
      else
        ...items.map(
          (item) => ListTile(
            leading: CircleAvatar(child: Text(item.memberName[0])),
            title: Text(item.memberName),
            trailing: Text(formatYen(item.total)),
            dense: true,
          ),
        ),
    ];
  }
}

/// 見出しの下が無言で空白になるのを防ぐ共通の受け皿。
///
/// 空状態の表示を分岐ごとに手で書き写すと、片方だけ文言や余白がずれる。
/// カテゴリ別・メンバー別で同じ表示を使うので 1 か所に寄せてある。
class _EmptySection extends StatelessWidget {
  const _EmptySection();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 24),
    child: Center(child: Text('データがありません')),
  );
}
