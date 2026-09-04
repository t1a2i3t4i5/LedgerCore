import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/category.dart';
import '../providers/category_provider.dart';
import '../theme/ledger_tokens.dart';
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
      _showFailureSnackBar('並び順を保存できませんでした');
    }
  }

  void _showFailureSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        // 画面下に固定した追加ボタンを覆わない高さまで浮かせる。
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 88),
      ),
    );
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
        _showFailureSnackBar('削除できませんでした（取引が残っている可能性があります）');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Consumer<CategoryProvider>(
          builder: (context, provider, _) {
            final movable = provider.movableCategories;
            final fixed = provider.fixedCategories;
            final rowCount = movable.length + fixed.length;

            final scrollView = CustomScrollView(
              slivers: [
                PinnedBackPageHeader(
                  title: 'カテゴリ',
                  actions: [
                    _EditModeButton(
                      editing: _editing,
                      onPressed: () => setState(() => _editing = !_editing),
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
                    // 一覧は 1 枚のカードに収める。行ごとにカードを分けると
                    // 区切り線ではなく影の帯が並び、案の見た目から離れる。
                    sliver: DecoratedSliver(
                      decoration: ledgerCardDecoration(context),
                      sliver: SliverMainAxisGroup(
                        slivers: [
                          SliverReorderableList(
                            itemCount: movable.length,
                            onReorder: _reorder,
                            proxyDecorator:
                                (child, index, animation) => Material(
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(
                                    LedgerTokens.cardRadius,
                                  ),
                                  elevation: 6,
                                  child: child,
                                ),
                            itemBuilder: (context, index) {
                              final cat = movable[index];
                              return _CategoryRow(
                                key: ValueKey(cat.id),
                                category: cat,
                                editing: _editing,
                                isFirst: index == 0,
                                isLast: index == rowCount - 1,
                                showDivider: index < rowCount - 1,
                                onTap: () => _showEditSheet(cat),
                                onDelete: () => _delete(cat.id, cat.name),
                                dragIndex: index,
                              );
                            },
                          ),
                          if (fixed.isNotEmpty)
                            SliverList.builder(
                              itemCount: fixed.length,
                              itemBuilder: (context, index) {
                                final cat = fixed[index];
                                return _CategoryRow(
                                  key: ValueKey(cat.id),
                                  category: cat,
                                  editing: _editing,
                                  isFirst: movable.isEmpty && index == 0,
                                  isLast: index == fixed.length - 1,
                                  showDivider: index < fixed.length - 1,
                                  onTap: () => _showEditSheet(cat),
                                  // 押せるかどうかの判断は _CategoryRow に一本化する。
                                  // ここで渡さないと、行側のガードを外しても
                                  // onDelete が null のままで退行に気付けない
                                  onDelete: () => _delete(cat.id, cat.name),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            );

            final list =
                !provider.loading &&
                        provider.error == null &&
                        provider.categories.isNotEmpty
                    ? RefreshIndicator(onRefresh: _fetch, child: scrollView)
                    : scrollView;

            return Column(
              children: [
                Expanded(child: list),
                _AddCategoryButton(onPressed: _showEditSheet),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 右上の「編集」/「完了」。編集中だけ塗りつぶしにして、モードを一目で分ける。
class _EditModeButton extends StatelessWidget {
  const _EditModeButton({required this.editing, required this.onPressed});

  final bool editing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: editing ? scheme.primary : scheme.primaryContainer,
        foregroundColor: editing ? scheme.onPrimary : scheme.onPrimaryContainer,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        minimumSize: const Size(0, 40),
        textStyle: Theme.of(context).textTheme.labelLarge,
      ),
      child: Text(editing ? '完了' : '編集'),
    );
  }
}

/// カテゴリ 1 行。カードの内側に置くので、角丸は先頭と末尾の行だけが持つ。
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    super.key,
    required this.category,
    required this.editing,
    required this.isFirst,
    required this.isLast,
    required this.showDivider,
    required this.onTap,
    this.onDelete,
    this.dragIndex,
  });

  final CategoryView category;
  final bool editing;
  final bool isFirst;
  final bool isLast;
  final bool showDivider;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  /// 並べ替えハンドルに渡す添字。固定カテゴリでは null。
  final int? dragIndex;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = categoryColor(category.id, colorValue: category.colorValue);
    // 編集中の固定カテゴリは操作できないので、色も文字も淡くして理由を示す。
    final muted = editing && category.isFixed;
    final radius = BorderRadius.vertical(
      top: Radius.circular(isFirst ? LedgerTokens.cardRadius : 0),
      bottom: Radius.circular(isLast ? LedgerTokens.cardRadius : 0),
    );

    final dot = CircleAvatar(
      radius: 5,
      backgroundColor: muted ? color.withValues(alpha: 0.35) : color,
    );
    final label = Text(
      category.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      // カテゴリ名は行を識別する主要情報なので、操作不能時も AA を満たす
      // onSurfaceVariant を使う。subtext は補助情報にだけ使う。
      style: muted ? TextStyle(color: scheme.onSurfaceVariant) : null,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ドラッグ中は Overlay へ持ち上がり、Scaffold の Material 祖先から
        // 外れるため、行自身に持たせる。
        Material(
          type: MaterialType.transparency,
          child: ListTile(
            shape: RoundedRectangleBorder(borderRadius: radius),
            onTap: editing ? null : onTap,
            leading:
                editing
                    ? IconButton(
                      tooltip:
                          category.isFixed
                              ? '${category.name}は削除できません'
                              : '${category.name}を削除',
                      icon: Icon(
                        Icons.remove_circle_outline,
                        color: category.isFixed ? null : scheme.error,
                      ),
                      onPressed: category.isFixed ? null : onDelete,
                    )
                    : dot,
            minLeadingWidth: editing ? 48 : 10,
            horizontalTitleGap: 12,
            title:
                editing
                    ? Row(
                      children: [
                        dot,
                        const SizedBox(width: 12),
                        Expanded(child: label),
                      ],
                    )
                    : label,
            trailing:
                editing
                    ? (dragIndex == null
                        ? Text(
                          '固定',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: LedgerTokens.subtext),
                        )
                        : Semantics(
                          label: '${category.name}を並べ替え',
                          child: ReorderableDragStartListener(
                            index: dragIndex!,
                            child: const SizedBox.square(
                              dimension: 48,
                              child: Icon(Icons.drag_handle),
                            ),
                          ),
                        ))
                    : const Icon(Icons.chevron_right),
          ),
        ),
        if (showDivider) const Divider(height: 1, indent: 16, endIndent: 16),
      ],
    );
  }
}

/// 一覧の下に据える「カテゴリを追加」。破線の枠で、一覧の行とは別の操作だと示す。
class _AddCategoryButton extends StatelessWidget {
  const _AddCategoryButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: SizedBox(
        height: 64,
        child: CustomPaint(
          painter: const _DashedBorderPainter(
            color: LedgerTokens.dashedOutline,
            radius: LedgerTokens.cardRadius,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: const Key('add-category-button'),
              onTap: onPressed,
              borderRadius: BorderRadius.circular(LedgerTokens.cardRadius),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 20, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(
                      'カテゴリを追加',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 角丸の破線枠。Flutter に破線の Border が無いので、輪郭を測って刻む。
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const _dash = 6.0;
  static const _gap = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
    final outline =
        Path()..addRRect(
          RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
        );
    for (final metric in outline.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + _dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      color != oldDelegate.color || radius != oldDelegate.radius;
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
