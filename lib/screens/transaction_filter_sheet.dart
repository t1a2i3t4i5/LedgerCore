import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/category_provider.dart';
import '../providers/member_provider.dart';
import '../providers/transaction_provider.dart';

/// 取引一覧のソート・フィルター設定用 BottomSheet
class TransactionFilterSheet extends StatefulWidget {
  const TransactionFilterSheet({super.key});

  @override
  State<TransactionFilterSheet> createState() => _TransactionFilterSheetState();
}

class _TransactionFilterSheetState extends State<TransactionFilterSheet> {
  // 一時 state（「適用」されるまで Provider には反映しない）
  late TransactionSortField _sortField;
  late SortOrder _sortOrder;
  late Set<int> _categoryIds;
  late Set<int> _userIds;
  final _minAmountCtrl = TextEditingController();
  final _maxAmountCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final p = context.read<TransactionProvider>();
    _sortField = p.sortField;
    _sortOrder = p.sortOrder;
    _categoryIds = {...p.filterCategoryIds};
    _userIds = {...p.filterUserIds};
    if (p.filterMinAmount != null) {
      _minAmountCtrl.text = p.filterMinAmount!.toStringAsFixed(0);
    }
    if (p.filterMaxAmount != null) {
      _maxAmountCtrl.text = p.filterMaxAmount!.toStringAsFixed(0);
    }
    _memoCtrl.text = p.filterMemoQuery;
  }

  @override
  void dispose() {
    _minAmountCtrl.dispose();
    _maxAmountCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  void _apply() {
    // 金額範囲のバリデーション
    final min = double.tryParse(_minAmountCtrl.text.trim());
    final max = double.tryParse(_maxAmountCtrl.text.trim());
    if (_minAmountCtrl.text.trim().isNotEmpty && min == null) {
      _showError('最小金額が不正な値です');
      return;
    }
    if (_maxAmountCtrl.text.trim().isNotEmpty && max == null) {
      _showError('最大金額が不正な値です');
      return;
    }
    if (min != null && max != null && min > max) {
      _showError('最小金額は最大金額以下にしてください');
      return;
    }

    final p = context.read<TransactionProvider>();
    p.setSort(_sortField, _sortOrder);
    p.setFilters(
      categoryIds: _categoryIds,
      userIds: _userIds,
      minAmount: min,
      maxAmount: max,
      memoQuery: _memoCtrl.text.trim(),
    );
    Navigator.of(context).pop();
  }

  void _reset() {
    context.read<TransactionProvider>().resetFilters();
    Navigator.of(context).pop();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<CategoryProvider>().categories;
    final members = context.watch<MemberProvider>().members;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ヘッダー
              Row(
                children: [
                  const Text(
                    'ソート・フィルター',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(),

              // ---- ソート ----
              const _SectionLabel('並び替え'),
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<TransactionSortField>(
                      segments: const [
                        ButtonSegment(
                          value: TransactionSortField.spentAt,
                          label: Text('日付'),
                          icon: Icon(Icons.calendar_today, size: 16),
                        ),
                        ButtonSegment(
                          value: TransactionSortField.amount,
                          label: Text('金額'),
                          icon: Icon(Icons.currency_yen, size: 16),
                        ),
                      ],
                      selected: {_sortField},
                      onSelectionChanged: (s) =>
                          setState(() => _sortField = s.first),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: _sortOrder == SortOrder.desc ? '降順' : '昇順',
                    icon: Icon(
                      _sortOrder == SortOrder.desc
                          ? Icons.arrow_downward
                          : Icons.arrow_upward,
                    ),
                    onPressed: () => setState(() {
                      _sortOrder = _sortOrder == SortOrder.desc
                          ? SortOrder.asc
                          : SortOrder.desc;
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ---- カテゴリ（複数選択） ----
              const _SectionLabel('カテゴリ'),
              if (categories.isEmpty)
                const Text('カテゴリがありません',
                    style: TextStyle(color: Colors.grey))
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: categories.map((c) {
                    final selected = _categoryIds.contains(c.id);
                    return FilterChip(
                      label: Text(c.name),
                      selected: selected,
                      onSelected: (v) => setState(() {
                        if (v) {
                          _categoryIds.add(c.id);
                        } else {
                          _categoryIds.remove(c.id);
                        }
                      }),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 16),

              // ---- 登録者（複数選択） ----
              const _SectionLabel('登録者'),
              if (members.isEmpty)
                const Text('メンバー情報を読み込み中...',
                    style: TextStyle(color: Colors.grey))
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: members.map((m) {
                    final selected = _userIds.contains(m.id);
                    return FilterChip(
                      label: Text(m.name),
                      selected: selected,
                      onSelected: (v) => setState(() {
                        if (v) {
                          _userIds.add(m.id);
                        } else {
                          _userIds.remove(m.id);
                        }
                      }),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 16),

              // ---- 金額範囲 ----
              const _SectionLabel('金額範囲'),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _minAmountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '最小 (¥)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('〜'),
                  ),
                  Expanded(
                    child: TextFormField(
                      controller: _maxAmountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '最大 (¥)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ---- メモ検索 ----
              const _SectionLabel('メモ検索'),
              TextFormField(
                controller: _memoCtrl,
                decoration: const InputDecoration(
                  hintText: 'メモに含まれる文字列',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 24),

              // ---- アクション ----
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _reset,
                      child: const Text('リセット'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _apply,
                      child: const Text('適用'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
    );
  }
}
