import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/summary.dart';
import '../providers/summary_provider.dart';
import '../widgets/amount_format.dart';
import '../widgets/chart_palette.dart';
import '../widgets/month_selector.dart';
import '../widgets/period_bar_chart.dart';

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
            // 全期間モードや取引ゼロの月は中身が短い。既定の physics だと
            // スクロールできる長さが無いときに引っ張っても反応しない
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              // 期間の切り替え。MonthSelector より上に固定する。
              // 下に置くと、全期間モードで MonthSelector が消えたときに
              // 切り替え UI 自体が上へ飛び、押した指の位置とずれる
              SegmentedButton<SummaryPeriod>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: SummaryPeriod.month, label: Text('月')),
                  ButtonSegment(value: SummaryPeriod.year, label: Text('年')),
                  ButtonSegment(value: SummaryPeriod.all, label: Text('全期間')),
                ],
                selected: {provider.period},
                onSelectionChanged:
                    (selected) => provider.setPeriod(selected.first),
              ),
              const SizedBox(height: 8),

              // 期間の送り。全期間モードには送る先が無いので出さない
              if (provider.period == SummaryPeriod.month) ...[
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
              ] else if (provider.period == SummaryPeriod.year) ...[
                MonthSelector(
                  // 表示月（provider.year）ではなく年専用の軸。ここを
                  // provider.year にすると、年を送った瞬間に割り勘タブの
                  // 表示期間まで 1 年ぶん動く
                  year: provider.yearAxis,
                  month: null,
                  todayTooltip: '今年に戻る',
                  onPrev: () => provider.changeYear(-1),
                  onNext: () => provider.changeYear(1),
                  onToday:
                      provider.isCurrentYear ? null : provider.goToCurrentYear,
                ),
                const SizedBox(height: 8),
              ],

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
              else
                ...switch (provider.period) {
                  SummaryPeriod.month => _monthBody(context, provider),
                  SummaryPeriod.year => _yearBody(context, provider),
                  SummaryPeriod.all => _allBody(context, provider),
                },
            ],
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
      _totalCard(context, summary.total),
      const SizedBox(height: 16),
      ..._categorySection(context, summary.byCategory, summary.total),
      const Divider(),
      const SizedBox(height: 8),
      ..._memberSection(context, summary.byMember),
    ];
  }

  /// 選択年。月別の推移グラフと、その年の合計・カテゴリ別。
  ///
  /// メンバー別は出さない。`YearlySummary` に `byMember` が無く、足すと
  /// データ層とそのテストまで波及する（design-notes.md 参照）。
  List<Widget> _yearBody(BuildContext context, SummaryProvider provider) {
    final yearly = provider.yearly;
    if (yearly == null) return const [_EmptySection()];

    return [
      Text('月別の推移', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      // 取引の無い月も 0 として 12 本並ぶ（buildYearlySummary が 0 で埋める）
      PeriodBarChart(items: yearly.byMonth),
      const SizedBox(height: 16),
      _totalCard(context, yearly.total),
      const SizedBox(height: 16),
      ..._categorySection(context, yearly.byCategory, yearly.total),
    ];
  }

  /// 全期間。年別の推移グラフだけ。
  ///
  /// 合計を出すには年別合計を画面側で fold することになり、「集計ロジックは
  /// 純関数に置く」約束に触れる。カテゴリ別も全期間ぶんを返す API が無い。
  List<Widget> _allBody(BuildContext context, SummaryProvider provider) {
    return [
      Text('年別の推移', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      // 取引のある年だけが昇順に並ぶ。1 年も無ければグラフ側が空表示を出す
      PeriodBarChart(items: provider.allYears),
    ];
  }

  Widget _totalCard(BuildContext context, double total) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text('合計支出', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            Text(
              formatYen(total),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Colors.teal,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// カテゴリ別リスト。月モードと年モードが同じ形を共有する。
  /// 構成比の分母だけがモードで変わるので [total] を引数で受ける。
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
          (item) => ListTile(
            // カテゴリごとに決まる色。取引一覧など他の画面でも同じ色になる
            leading: CircleAvatar(
              backgroundColor: categoryColor(item.categoryId),
              child: Icon(
                Icons.label_outline,
                size: 20,
                color: labelColorOn(categoryColor(item.categoryId)),
              ),
            ),
            // カテゴリ名は DB 上 50 文字まで入る。trailing が長くなった分
            // title の取り分が減るので ellipsis で畳む
            title: Text(item.categoryName, overflow: TextOverflow.ellipsis),
            // 金額と % を 1 行に並べない。ListTile は trailing を先に
            // 測って残りを title に配分するので、'¥50,000 (14.3%)' の
            // 1 行では 360px 幅で title に 43.5px しか残らず、全角 4 文字の
            // カテゴリ名が既に ellipsis で畳まれていた（実測）。
            // 縦に積むと trailing の幅は金額だけで決まる
            trailing: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatYen(item.total)),
                Text(
                  formatRatio(item.total, total),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            dense: true,
          ),
        ),
    ];
  }

  /// メンバー別リスト。月モードだけが使う。
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
/// 期間モードが 3 つに増えて分岐が増えたので 1 か所に寄せてある。
class _EmptySection extends StatelessWidget {
  const _EmptySection();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 24),
    child: Center(child: Text('データがありません')),
  );
}
