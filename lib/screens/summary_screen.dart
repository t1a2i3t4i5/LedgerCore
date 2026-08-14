import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/summary_provider.dart';
import '../widgets/amount_format.dart';
import '../widgets/category_pie_chart.dart';
import '../widgets/chart_palette.dart';

class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});

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
                          formatYen(provider.summary!.total),
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
                CategoryPieChart(items: provider.summary!.byCategory),
                const SizedBox(height: 8),
                // グラフの下に金額のリストも残す（数値も確認したいため）
                ...provider.summary!.byCategory.map(
                  (item) => ListTile(
                    // 扇形と同じ色にしてグラフとリストの対応を分かりやすくする
                    leading: CircleAvatar(
                      backgroundColor: categoryColor(item.categoryId),
                      child: Icon(
                        Icons.label_outline,
                        size: 20,
                        color: labelColorOn(categoryColor(item.categoryId)),
                      ),
                    ),
                    title: Text(item.categoryName),
                    trailing: Text(formatYen(item.total)),
                    dense: true,
                  ),
                ),
                const Divider(),

                // ユーザー別
                const SizedBox(height: 8),
                Text('メンバー別',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...provider.summary!.byMember.map(
                  (item) => ListTile(
                    leading: CircleAvatar(
                      child: Text(item.memberName[0]),
                    ),
                    title: Text(item.memberName),
                    trailing: Text(formatYen(item.total)),
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
