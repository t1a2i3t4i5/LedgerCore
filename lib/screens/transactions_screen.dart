import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/category_provider.dart';
import '../providers/member_provider.dart';
import '../providers/transaction_provider.dart';
import '../theme/ledger_tokens.dart';
import '../widgets/amount_format.dart';
import '../widgets/chart_palette.dart';
import '../widgets/month_selector.dart';
import 'add_transaction_screen.dart';
import 'transaction_filter_sheet.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _dateFmt = DateFormat('M/d');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialLoad());
  }

  Future<void> _initialLoad() async {
    // 取引一覧に加え、フィルター BottomSheet で使うカテゴリ・メンバーも事前ロード
    await context.read<TransactionProvider>().fetch();
    if (!mounted) return;
    context.read<CategoryProvider>().fetch();
    context.read<MemberProvider>().fetchMembers();
  }

  Future<void> _fetch() async {
    await context.read<TransactionProvider>().fetch();
  }

  Future<void> _openFilterSheet() async {
    // BottomSheet を開く前に、カテゴリ・メンバーが未読込なら読む
    final catProvider = context.read<CategoryProvider>();
    final memberProvider = context.read<MemberProvider>();
    if (catProvider.categories.isEmpty) {
      // ignore: unawaited_futures
      catProvider.fetch();
    }
    if (memberProvider.members.isEmpty) {
      // ignore: unawaited_futures
      memberProvider.fetchMembers();
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const TransactionFilterSheet(),
    );
  }

  Future<void> _delete(int transactionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('取引を削除'),
            content: const Text('この取引を削除しますか？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('キャンセル'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('削除'),
              ),
            ],
          ),
    );
    if (confirmed == true && mounted) {
      try {
        await context.read<TransactionProvider>().delete(transactionId);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('削除失敗: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TransactionProvider>(
      builder: (context, provider, _) {
        final filtered = provider.filteredTransactions;
        final activeCount = provider.activeFilterCount;
        return Scaffold(
          body: Column(
            children: [
              // 月選択 + フィルターボタン
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: MonthSelector(
                  year: provider.year,
                  month: provider.month,
                  onPrev: () => provider.changeMonth(-1),
                  onNext: () => provider.changeMonth(1),
                  onToday:
                      provider.isCurrentMonth
                          ? null
                          : provider.goToCurrentMonth,
                  actions: [
                    // フィルターボタン（適用中の数をバッジ表示）
                    IconButton(
                      tooltip: 'ソート・フィルター',
                      onPressed: _openFilterSheet,
                      icon: Badge(
                        isLabelVisible: activeCount > 0,
                        label: Text('$activeCount'),
                        backgroundColor:
                            Theme.of(context).colorScheme.secondary,
                        textColor: Theme.of(context).colorScheme.onSurface,
                        child: const Icon(Icons.filter_list),
                      ),
                    ),
                  ],
                ),
              ),
              // 合計パネル
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Row(
                  children: [
                    Text(
                      '${filtered.length}件',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    // 合計は件数ぶん膨らむ（上限額 × 件数）。金額を省略すると
                    // 桁を読み違えるので、縮小して収める
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('合計'),
                            const SizedBox(width: 8),
                            Text(
                              formatYen(provider.filteredTotal),
                              style: LedgerTokens.amountRow,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child:
                    provider.loading
                        ? const Center(child: CircularProgressIndicator())
                        : provider.error != null
                        ? Center(
                          child: Text(
                            'エラー: ${provider.error}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        )
                        : filtered.isEmpty
                        ? _EmptyTransactions(
                          message:
                              provider.transactions.isEmpty
                                  ? '取引がありません'
                                  : '該当する取引がありません',
                        )
                        : RefreshIndicator(
                          onRefresh: _fetch,
                          child: ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder:
                                (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final t = filtered[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  radius: 5,
                                  backgroundColor: categoryColor(t.categoryId),
                                ),
                                minLeadingWidth: 10,
                                horizontalTitleGap: 12,
                                title: Text(
                                  t.categoryName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: _dateFmt.format(t.spentAt),
                                        style: const TextStyle(
                                          color: LedgerTokens.subtext,
                                        ),
                                      ),
                                      TextSpan(
                                        text:
                                            ' · ${t.memberName}${t.memo != null && t.memo!.isNotEmpty ? ' · ${t.memo}' : ''}',
                                      ),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.bodyMedium?.copyWith(
                                    color:
                                        Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                trailing: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 140,
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      formatYen(t.amount),
                                      style: LedgerTokens.amountRow,
                                    ),
                                  ),
                                ),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder:
                                          (_) =>
                                              AddTransactionScreen(existing: t),
                                    ),
                                  );
                                },
                                onLongPress: () => _delete(t.id),
                              );
                            },
                          ),
                        ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AddTransactionScreen()),
              );
            },
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }
}

class _EmptyTransactions extends StatelessWidget {
  const _EmptyTransactions({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.receipt_long_outlined,
          size: 40,
          color: Theme.of(context).colorScheme.secondary,
        ),
        const SizedBox(height: 12),
        Text(
          message,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}
