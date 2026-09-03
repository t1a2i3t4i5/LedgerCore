import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/category.dart';
import '../providers/category_provider.dart';
import '../widgets/chart_palette.dart';
import '../widgets/ledger_card.dart';
import '../widgets/page_header.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  Future<void> _fetch() async {
    await context.read<CategoryProvider>().fetch();
  }

  Future<void> _showEditSheet([CategoryView? category]) async {
    final provider = context.read<CategoryProvider>();
    final initialColor =
        category == null
            ? leastUsedCategoryColor(
              provider.categories.map(
                (item) => categoryColor(item.id, colorValue: item.colorValue),
              ),
            )
            : categoryColor(category.id, colorValue: category.colorValue);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder:
          (_) => _CategoryEditSheet(
            category: category,
            initialColor: initialColor,
            existingCategories: provider.categories,
            onSave: (name, color) async {
              if (category == null) {
                await provider.create(name, colorValue: color.toARGB32());
              } else {
                await provider.update(
                  category.id,
                  name,
                  colorValue: color.toARGB32(),
                );
              }
            },
          ),
    );
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    try {
      await context.read<CategoryProvider>().reorder(oldIndex, newIndex);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('並び順を保存できませんでした')));
      }
    }
  }

  Future<void> _delete(int categoryId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('カテゴリを削除'),
            content: Text('「$name」を削除しますか？\nこのカテゴリの取引が残っている場合は削除できません。'),
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
        await context.read<CategoryProvider>().delete(categoryId);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('削除できませんでした（取引が残っている可能性があります）')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Consumer<CategoryProvider>(
          builder: (context, provider, _) {
            final scrollView = CustomScrollView(
              slivers: [
                PinnedBackPageHeader(
                  title: 'カテゴリ',
                  actions: [
                    TextButton(
                      onPressed: () => setState(() => _editing = !_editing),
                      child: Text(_editing ? '完了' : '編集'),
                    ),
                  ],
                ),
                if (provider.loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (provider.error != null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        'エラー: ${provider.error}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  )
                else if (provider.categories.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyCategories(),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    sliver: SliverReorderableList(
                      itemCount: provider.categories.length,
                      onReorder: _reorder,
                      itemBuilder: (context, index) {
                        final cat = provider.categories[index];
                        final color = categoryColor(
                          cat.id,
                          colorValue: cat.colorValue,
                        );
                        return Padding(
                          key: ValueKey(cat.id),
                          padding: const EdgeInsets.only(bottom: 12),
                          child: LedgerCard(
                            padding: EdgeInsets.zero,
                            // ドラッグ中は Overlay へ持ち上がり、Scaffold の
                            // Material 祖先から外れるため、行自身に持たせる。
                            child: Material(
                              type: MaterialType.transparency,
                              child: ListTile(
                                onTap:
                                    _editing ? null : () => _showEditSheet(cat),
                                leading:
                                    _editing
                                        ? IconButton(
                                          tooltip: '${cat.name}を削除',
                                          icon: Icon(
                                            Icons.remove_circle_outline,
                                            color:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.error,
                                          ),
                                          onPressed:
                                              () => _delete(cat.id, cat.name),
                                        )
                                        : CircleAvatar(
                                          radius: 5,
                                          backgroundColor: color,
                                        ),
                                minLeadingWidth: _editing ? 48 : 10,
                                horizontalTitleGap: 12,
                                title:
                                    _editing
                                        ? Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 5,
                                              backgroundColor: color,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                cat.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        )
                                        : Text(
                                          cat.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                trailing:
                                    _editing
                                        ? Semantics(
                                          label: '${cat.name}を並べ替え',
                                          child: ReorderableDragStartListener(
                                            index: index,
                                            child: const SizedBox.square(
                                              dimension: 48,
                                              child: Icon(Icons.drag_handle),
                                            ),
                                          ),
                                        )
                                        : const Icon(Icons.chevron_right),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );

            if (!provider.loading &&
                provider.error == null &&
                provider.categories.isNotEmpty) {
              return RefreshIndicator(onRefresh: _fetch, child: scrollView);
            }
            return scrollView;
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showEditSheet,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _CategoryEditSheet extends StatefulWidget {
  const _CategoryEditSheet({
    required this.category,
    required this.initialColor,
    required this.existingCategories,
    required this.onSave,
  });

  final CategoryView? category;
  final Color initialColor;
  final List<CategoryView> existingCategories;
  final Future<void> Function(String name, Color color) onSave;

  @override
  State<_CategoryEditSheet> createState() => _CategoryEditSheetState();
}

class _CategoryEditSheetState extends State<_CategoryEditSheet> {
  late final TextEditingController _nameController;
  late Color _selectedColor;
  String? _nameError;
  String? _saveError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category?.name);
    _selectedColor = widget.initialColor;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String? _validateName(String name) {
    if (name.isEmpty) return 'カテゴリ名を入力してください';
    if (name.length > 50) return 'カテゴリ名は50文字以内で入力してください';
    final duplicate = widget.existingCategories.any(
      (category) => category.id != widget.category?.id && category.name == name,
    );
    if (duplicate) return '同じ名前のカテゴリがあります';
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameController.text.trim();
    final validationError = _validateName(name);
    if (validationError != null) {
      setState(() {
        _nameError = validationError;
        _saveError = null;
      });
      return;
    }

    setState(() {
      _saving = true;
      _nameError = null;
      _saveError = null;
    });
    try {
      await widget.onSave(name, _selectedColor);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = '保存できませんでした。入力内容を確認してください';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final height = math.min(520.0, media.size.height - media.viewInsets.bottom);
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_saving,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: SizedBox(
          height: height,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed:
                                _saving
                                    ? null
                                    : () => Navigator.of(context).pop(),
                            child: const Text('キャンセル'),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          widget.category == null ? 'カテゴリを追加' : 'カテゴリを編集',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const Expanded(child: SizedBox()),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _nameController,
                          enabled: !_saving,
                          maxLength: 51,
                          decoration: InputDecoration(
                            labelText: 'カテゴリ名',
                            errorText: _nameError,
                            border: const OutlineInputBorder(),
                            prefixIcon: Padding(
                              padding: const EdgeInsets.all(16),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: _selectedColor,
                                  shape: BoxShape.circle,
                                ),
                                child: const SizedBox.square(dimension: 12),
                              ),
                            ),
                          ),
                          onChanged:
                              (_) => setState(() {
                                _nameError = null;
                                _saveError = null;
                              }),
                          onSubmitted: (_) => _save(),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '色',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final (index, color)
                                in categoryPalette.indexed)
                              Semantics(
                                label: 'カテゴリ色${index + 1}',
                                button: true,
                                selected: color == _selectedColor,
                                child: Tooltip(
                                  message: 'カテゴリ色${index + 1}',
                                  child: InkResponse(
                                    key: ValueKey(
                                      'category-color-${color.toARGB32()}',
                                    ),
                                    onTap:
                                        _saving
                                            ? null
                                            : () => setState(
                                              () => _selectedColor = color,
                                            ),
                                    radius: 24,
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: color,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color:
                                              color == _selectedColor
                                                  ? scheme.onSurface
                                                  : scheme.outlineVariant,
                                          width:
                                              color == _selectedColor ? 3 : 1,
                                        ),
                                      ),
                                      child:
                                          color == _selectedColor
                                              ? Icon(
                                                Icons.check,
                                                color: labelColorOn(color),
                                              )
                                              : null,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (_saveError case final error?) ...[
                          const SizedBox(height: 16),
                          Text(error, style: TextStyle(color: scheme.error)),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child:
                          _saving
                              ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Text('保存する'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyCategories extends StatelessWidget {
  const _EmptyCategories();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.label_outline,
          size: 40,
          color: Theme.of(context).colorScheme.secondary,
        ),
        const SizedBox(height: 12),
        Text(
          'カテゴリがありません',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}
