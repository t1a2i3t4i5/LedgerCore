import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/category_provider.dart';
import '../providers/member_provider.dart';
import '../providers/transaction_provider.dart';
import 'add_transaction_screen.dart';
import 'transaction_filter_sheet.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _fmt = NumberFormat('#,###', 'ja_JP');
  final _dateFmt = DateFormat('MM/dd');

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

  void _changeMonth(int delta) {
    final provider = context.read<TransactionProvider>();
    var year = provider.year;
    var month = provider.month + delta;
    if (month > 12) {
      month = 1;
      year++;
    } else if (month < 1) {
      month = 12;
      year--;
    }
    provider.setYearMonth(year, month);
    _fetch();
  }

  void _goToCurrentMonth() {
    final now = DateTime.now();
    final provider = context.read<TransactionProvider>();
    provider.setYearMonth(now.year, now.month);
    _fetch();
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
      builder: (_) => AlertDialog(
        title: const Text('取引を削除'),
        content: const Text('この取引を削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await context.read<TransactionProvider>().delete(transactionId);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('削除失敗: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TransactionProvider>(
      builder: (context, provider, _) {
        final now = DateTime.now();
        final isCurrentMonth =
            provider.year == now.year && provider.month == now.month;
        final filtered = provider.filteredTransactions;
        final activeCount = provider.activeFilterCount;
        return Scaffold(
          body: Column(
            children: [
              // 月選択 + フィルターボタン
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _changeMonth(-1),
                    ),
                    Text(
                      '${provider.year}年${provider.month}月',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: () => _changeMonth(1),
                        ),
                        IconButton(
                          icon: const Icon(Icons.today),
                          tooltip: '今月に戻る',
                          onPressed: isCurrentMonth ? null : _goToCurrentMonth,
                        ),
                        // フィルターボタン（適用中の数をバッジ表示）
                        IconButton(
                          tooltip: 'ソート・フィルター',
                          onPressed: _openFilterSheet,
                          icon: Badge(
                            isLabelVisible: activeCount > 0,
                            label: Text('$activeCount'),
                            child: const Icon(Icons.filter_list),
                          ),
                        ),
                      ],
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
                        child: Text(
                          '合計 ¥${_fmt.format(provider.filteredTotal)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: provider.loading
                    ? const Center(child: CircularProgressIndicator())
                    : provider.error != null
                        ? Center(
                            child: Text(
                              'エラー: ${provider.error}',
                              style: const TextStyle(color: Colors.red),
                            ),
                          )
                        : filtered.isEmpty
                            ? Center(
                                child: Text(
                                  provider.transactions.isEmpty
                                      ? '取引がありません'
                                      : '該当する取引がありません',
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _fetch,
                                child: ListView.separated(
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final t = filtered[index];
                                    return ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor:
                                            Colors.teal.withValues(alpha: 0.15),
                                        child: Text(
                                          _dateFmt.format(t.spentAt),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.teal,
                                          ),
                                        ),
                                      ),
                                      title: Text(t.categoryName),
                                      subtitle: Text(
                                        '${t.userName}${t.memo != null && t.memo!.isNotEmpty ? ' · ${t.memo}' : ''}',
                                      ),
                                      trailing: Text(
                                        '¥${_fmt.format(t.amount)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                AddTransactionScreen(
                                              existing: t,
                                            ),
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
                MaterialPageRoute(
                  builder: (_) => const AddTransactionScreen(),
                ),
              );
            },
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }
}
