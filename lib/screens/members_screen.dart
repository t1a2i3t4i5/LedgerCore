import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/household_member.dart';
import '../providers/member_provider.dart';
import '../theme/ledger_tokens.dart';
import '../widgets/chart_palette.dart';
import '../widgets/page_header.dart';

const _memberNameMaxLength = 50;
const _memberNameNote = '名前は取引の記録と精算画面に表示されます';

final _memberNameLengthFormatter = TextInputFormatter.withFunction((
  oldValue,
  newValue,
) {
  if (newValue.text.length <= _memberNameMaxLength) return newValue;
  return oldValue;
});

/// 2 人の円が重なる図の寸法。
///
/// 半径は高さの半分、円の中心は左右の端から半径ぶん内側なので、
/// 重なりの幅は `2r - (幅 - 2r)` = 80 になる。
const _vennSize = Size(300, 190);

/// 割り勘の対象となるメンバーを管理する画面。
class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<MemberProvider>().fetchMembers(),
    );
  }

  Future<void> _updateMember(int id, String name) async {
    try {
      await context.read<MemberProvider>().updateMember(id, name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失敗: $e')));
      }
      rethrow;
    }
  }

  Future<void> _updateMemberColor(int id, Color color) async {
    try {
      await context.read<MemberProvider>().updateMemberColor(
        id,
        color.toARGB32(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失敗: $e')));
      }
      rethrow;
    }
  }

  Future<void> _showColorPicker(
    HouseholdMember member,
    List<HouseholdMember> members,
  ) async {
    final unavailableColors = {
      for (final other in members)
        if (other.id != member.id)
          memberColor(other.id, colorValue: other.colorValue),
    };
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder:
          (_) => _MemberColorPickerSheet(
            member: member,
            unavailableColors: unavailableColors,
            onSelected: (color) => _updateMemberColor(member.id, color),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MemberProvider>();
    final members = provider.members;
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            const PinnedBackPageHeader(title: 'メンバー'),
            if (provider.membersLoading && members.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (members.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyMembers(),
              )
            else ...[
              // 重なりは「2 人で分け合う家計」の図なので、精算と同じく
              // ちょうど 2 人のときだけ描く。
              if (members.length == 2)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                    child: _MemberVenn(members: members),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 8, 16),
                sliver: SliverList.separated(
                  itemCount: members.length,
                  separatorBuilder:
                      (_, __) => const Divider(
                        height: 1,
                        thickness: 1,
                        color: LedgerTokens.barTrack,
                      ),
                  itemBuilder: (context, index) {
                    final member = members[index];
                    return _MemberRow(
                      key: ValueKey(member.id),
                      member: member,
                      onSave: _updateMember,
                      onColorTap: () => _showColorPicker(member, members),
                    );
                  },
                ),
              ),
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 24),
                sliver: SliverToBoxAdapter(child: _MemberNameNote()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 2 人の識別色の円が重なる図。
///
/// 重なりの色は [multiplyColors] で 2 色から導く。名前は載せない
/// （長い名前が入らないうえ、行側に同じ色の丸があれば対応が付く）。
class _MemberVenn extends StatelessWidget {
  const _MemberVenn({required this.members});

  final List<HouseholdMember> members;

  @override
  Widget build(BuildContext context) => Center(
    child: ExcludeSemantics(
      child: SizedBox.fromSize(
        key: const ValueKey('member-venn'),
        size: _vennSize,
        child: CustomPaint(
          painter: _MemberVennPainter(
            left: memberColor(members[0].id, colorValue: members[0].colorValue),
            right: memberColor(
              members[1].id,
              colorValue: members[1].colorValue,
            ),
          ),
        ),
      ),
    ),
  );
}

class _MemberVennPainter extends CustomPainter {
  const _MemberVennPainter({required this.left, required this.right});

  final Color left;
  final Color right;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.height / 2;
    final leftCircle =
        Path()..addOval(
          Rect.fromCircle(center: Offset(radius, radius), radius: radius),
        );
    final rightCircle =
        Path()..addOval(
          Rect.fromCircle(
            center: Offset(size.width - radius, radius),
            radius: radius,
          ),
        );

    canvas.drawPath(leftCircle, Paint()..color = left);
    canvas.drawPath(rightCircle, Paint()..color = right);
    canvas.drawPath(
      Path.combine(PathOperation.intersect, leftCircle, rightCircle),
      Paint()..color = multiplyColors(left, right),
    );
  }

  @override
  bool shouldRepaint(_MemberVennPainter oldDelegate) =>
      oldDelegate.left != left || oldDelegate.right != right;
}

class _MemberRow extends StatefulWidget {
  const _MemberRow({
    super.key,
    required this.member,
    required this.onSave,
    required this.onColorTap,
  });

  final HouseholdMember member;
  final Future<void> Function(int id, String name) onSave;
  final VoidCallback onColorTap;

  @override
  State<_MemberRow> createState() => _MemberRowState();
}

class _MemberRowState extends State<_MemberRow> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  var _editing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.member.name);
    _focusNode = FocusNode()..addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _MemberRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.member.name != widget.member.name) {
      _controller.text = widget.member.name;
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus && _editing) {
      unawaited(_finishEditing());
    }
  }

  void _startEditing() {
    if (_editing) return;
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  Future<void> _finishEditing() async {
    final originalName = widget.member.name;
    final newName = _controller.text.trim();
    setState(() => _editing = false);

    if (newName.isEmpty || newName == originalName) {
      _controller.text = originalName;
      return;
    }

    try {
      await widget.onSave(widget.member.id, newName);
    } catch (_) {
      if (mounted) setState(() => _controller.text = originalName);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final nameStyle = Theme.of(
      context,
    ).textTheme.bodyLarge?.copyWith(fontSize: 22);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 72),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: '${widget.member.name}の色を変更',
            child: Tooltip(
              message: '色を変更',
              child: InkResponse(
                key: ValueKey('member-color-button-${widget.member.id}'),
                onTap: widget.onColorTap,
                radius: 22,
                child: SizedBox.square(
                  dimension: 44,
                  child: Center(
                    child: Container(
                      key: ValueKey('member-dot-${widget.member.id}'),
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: memberColor(
                          widget.member.id,
                          colorValue: widget.member.colorValue,
                        ),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: SizedBox(
              key: ValueKey('member-name-slot-${widget.member.id}'),
              child:
                  _editing
                      ? TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        autofocus: true,
                        inputFormatters: [_memberNameLengthFormatter],
                        maxLines: 1,
                        textInputAction: TextInputAction.done,
                        cursorColor: colorScheme.secondary,
                        style: nameStyle,
                        decoration: InputDecoration(
                          isDense: true,
                          counterText: '',
                          filled: true,
                          fillColor: colorScheme.secondaryContainer,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: colorScheme.secondary,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: colorScheme.secondary,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: colorScheme.secondary,
                            ),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                        onTapOutside: (_) => _focusNode.unfocus(),
                        onSubmitted: (_) => _focusNode.unfocus(),
                      )
                      : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _startEditing,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            widget.member.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: nameStyle,
                          ),
                        ),
                      ),
            ),
          ),
          const SizedBox(width: 12),
          // カウンタは編集中だけ出すが、隠している間も同じ幅を予約して
          // 行の高さと名前の幅を動かさない。予約幅は文字倍率を適用した
          // `50/50` の内容幅から採り、固定幅で末尾を切らない。
          Stack(
            alignment: Alignment.centerRight,
            children: [
              const Visibility(
                visible: false,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: Text(
                  '50/50',
                  maxLines: 1,
                  style: TextStyle(color: LedgerTokens.subtext, fontSize: 11),
                ),
              ),
              Visibility(
                key: ValueKey('member-counter-${widget.member.id}'),
                visible: _editing,
                child: Text(
                  '${_controller.text.length}/$_memberNameMaxLength',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  style: const TextStyle(
                    color: LedgerTokens.subtext,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
          SizedBox.square(
            dimension: 44,
            child: IconButton(
              tooltip: '名前を編集',
              padding: EdgeInsets.zero,
              icon: const Icon(
                Icons.edit_outlined,
                size: 20,
                color: LedgerTokens.subtext,
              ),
              onPressed: _startEditing,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberColorPickerSheet extends StatefulWidget {
  const _MemberColorPickerSheet({
    required this.member,
    required this.unavailableColors,
    required this.onSelected,
  });

  final HouseholdMember member;
  final Set<Color> unavailableColors;
  final Future<void> Function(Color color) onSelected;

  @override
  State<_MemberColorPickerSheet> createState() =>
      _MemberColorPickerSheetState();
}

class _MemberColorPickerSheetState extends State<_MemberColorPickerSheet> {
  var _saving = false;
  String? _error;

  Future<void> _select(Color color) async {
    if (_saving) return;
    final current = memberColor(
      widget.member.id,
      colorValue: widget.member.colorValue,
    );
    if (color == current) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSelected(color);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '色を保存できませんでした';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = memberColor(
      widget.member.id,
      colorValue: widget.member.colorValue,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              '${widget.member.name}の色',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final (index, color) in memberPalette.indexed)
                Builder(
                  builder: (context) {
                    final unavailable =
                        widget.unavailableColors.contains(color) &&
                        color != current;
                    return Semantics(
                      label:
                          unavailable
                              ? 'メンバー色${index + 1}、使用中'
                              : 'メンバー色${index + 1}',
                      button: true,
                      selected: color == current,
                      enabled: !unavailable && !_saving,
                      child: Tooltip(
                        message: unavailable ? 'ほかのメンバーが使用中' : '色を選択',
                        child: InkResponse(
                          key: ValueKey('member-color-${color.toARGB32()}'),
                          onTap:
                              unavailable || _saving
                                  ? null
                                  : () => _select(color),
                          radius: 24,
                          child: Opacity(
                            opacity: unavailable ? 0.35 : 1,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color:
                                      color == current
                                          ? scheme.onSurface
                                          : scheme.outlineVariant,
                                  width: color == current ? 3 : 1,
                                ),
                              ),
                              child:
                                  color == current
                                      ? Icon(
                                        Icons.check,
                                        color: labelColorOn(color),
                                      )
                                      : unavailable
                                      ? Icon(
                                        Icons.block,
                                        color: labelColorOn(color),
                                      )
                                      : null,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
          if (_saving) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_error case final error?) ...[
            const SizedBox(height: 16),
            Text(error, style: TextStyle(color: scheme.error)),
          ],
        ],
      ),
    );
  }
}

class _MemberNameNote extends StatelessWidget {
  const _MemberNameNote();

  @override
  Widget build(BuildContext context) => Text(
    _memberNameNote,
    style: Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: LedgerTokens.subtext),
  );
}

class _EmptyMembers extends StatelessWidget {
  const _EmptyMembers();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.people_outline,
          size: 40,
          color: Theme.of(context).colorScheme.secondary,
        ),
        const SizedBox(height: 12),
        Text(
          'メンバーがいません',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}
