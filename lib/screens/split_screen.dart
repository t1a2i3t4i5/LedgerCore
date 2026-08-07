import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/summary_provider.dart';

class SplitScreen extends StatefulWidget {
  const SplitScreen({super.key});

  @override
  State<SplitScreen> createState() => _SplitScreenState();
}

class _SplitScreenState extends State<SplitScreen> {
  final _fmt = NumberFormat('#,###', 'ja_JP');

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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => provider.changeMonth(-1),
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
                        onPressed: () => provider.changeMonth(1),
                      ),
                      IconButton(
                        icon: const Icon(Icons.today),
                        tooltip: '今月に戻る',
                        onPressed: provider.isCurrentMonth
                            ? null
                            : provider.goToCurrentMonth,
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
              else if (provider.split == null)
                const Center(child: Text('データがありません'))
              else ...[
                // 合計・均等割
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              const Text('合計', style: TextStyle(fontSize: 12)),
                              Text(
                                '¥${_fmt.format(provider.split!.total)}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const VerticalDivider(),
                        Expanded(
                          child: Column(
                            children: [
                              const Text('一人当たり',
                                  style: TextStyle(fontSize: 12)),
                              Text(
                                '¥${_fmt.format(provider.split!.fairShare)}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 精算結果
                Card(
                  color: Colors.teal.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.swap_horiz, color: Colors.teal),
                            const SizedBox(width: 8),
                            Text(
                              '精算方法',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(color: Colors.teal),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(provider.split!.settlement),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // メンバー別支払い
                Text('メンバー別支払い状況',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...provider.split!.users.map((u) {
                  final isOver = u.balance > 0;
                  final isUnder = u.balance < 0;
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Text(u.userName[0])),
                      title: Text(u.userName),
                      subtitle: Text('支払済み: ¥${_fmt.format(u.paid)}'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            isOver
                                ? '+¥${_fmt.format(u.balance)}'
                                : '¥${_fmt.format(u.balance)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isOver
                                  ? Colors.green
                                  : isUnder
                                      ? Colors.red
                                      : Colors.grey,
                            ),
                          ),
                          Text(
                            isOver ? '受け取り' : isUnder ? '支払い' : '均等',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ],
          ),
        );
      },
    );
  }
}
