import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/summary_provider.dart';

class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  final _fmt = NumberFormat('#,###', 'ja_JP');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  Future<void> _fetch() async {
    await context.read<SummaryProvider>().fetch();
  }

  void _changeMonth(int delta) {
    final provider = context.read<SummaryProvider>();
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
    final provider = context.read<SummaryProvider>();
    provider.setYearMonth(now.year, now.month);
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SummaryProvider>(
      builder: (context, provider, _) {
        final now = DateTime.now();
        final isCurrentMonth = provider.year == now.year && provider.month == now.month;
        return RefreshIndicator(
          onRefresh: _fetch,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 月選択
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => _changeMonth(-1),
                  ),
                  Text(
                    '${provider.year}年${provider.month}月',
                    style: Theme.of(context).textTheme.titleLarge,
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
                    ],
                  ),
                ],
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
                    style: const TextStyle(color: Colors.red),
                  ),
                )
              else if (provider.summary == null)
                const Center(child: Text('データがありません'))
              else ...[
                // 合計カード
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Text('合計支出', style: TextStyle(fontSize: 14)),
                        const SizedBox(height: 8),
                        Text(
                          '¥${_fmt.format(provider.summary!.total)}',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                color: Colors.teal,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // カテゴリ別
                Text('カテゴリ別',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...provider.summary!.byCategory.map(
                  (item) => ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.label_outline, size: 20),
                    ),
                    title: Text(item.categoryName),
                    trailing: Text('¥${_fmt.format(item.total)}'),
                    dense: true,
                  ),
                ),
                const Divider(),

                // ユーザー別
                const SizedBox(height: 8),
                Text('メンバー別',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...provider.summary!.byUser.map(
                  (item) => ListTile(
                    leading: CircleAvatar(
                      child: Text(item.userName[0]),
                    ),
                    title: Text(item.userName),
                    trailing: Text('¥${_fmt.format(item.total)}'),
                    dense: true,
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
