import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/household_member.dart';
import '../providers/member_provider.dart';
import '../theme/ledger_tokens.dart';
import '../widgets/chart_palette.dart';
import '../widgets/ledger_card.dart';
import '../widgets/page_header.dart';

const _memberNameMaxLength = 50;
const _memberNameNote = '名前は取引の記録と精算画面に表示されます';

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
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverList.separated(
                  itemCount: members.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final member = members[index];
                    return _MemberRow(
                      key: ValueKey(member.id),
                      member: member,
                      onSave: _updateMember,
                    );
                  },
                ),
              ),
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverToBoxAdapter(child: _MemberNameNote()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MemberRow extends StatefulWidget {
  const _MemberRow({super.key, required this.member, required this.onSave});

  final HouseholdMember member;
  final Future<void> Function(int id, String name) onSave;

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

  String get _avatarLabel {
    final name = _controller.text;
    return name.isEmpty ? '—' : name.characters.first;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final avatarColor = memberColor(widget.member.id);
    return LedgerCard(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: 72,
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: avatarColor,
                foregroundColor: labelColorOn(avatarColor),
                child: Text(_avatarLabel),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  key: ValueKey('member-name-slot-${widget.member.id}'),
                  child:
                      _editing
                          ? TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            autofocus: true,
                            maxLength: _memberNameMaxLength,
                            maxLines: 1,
                            textInputAction: TextInputAction.done,
                            cursorColor: colorScheme.secondary,
                            style: Theme.of(context).textTheme.bodyLarge,
                            decoration: InputDecoration(
                              isDense: true,
                              counterText: '',
                              filled: true,
                              fillColor: colorScheme.secondaryContainer,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
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
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ),
                          ),
                ),
              ),
              const SizedBox(width: 12),
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
                      style: TextStyle(
                        color: LedgerTokens.subtext,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Visibility(
                    key: ValueKey('member-counter-${widget.member.id}'),
                    visible: _editing,
                    child: Text(
                      '${_controller.text.characters.length}/$_memberNameMaxLength',
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
              const SizedBox(width: 12),
              SizedBox.square(
                dimension: 44,
                child: IconButton(
                  tooltip: '名前を編集',
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.edit_outlined,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  onPressed: _startEditing,
                ),
              ),
            ],
          ),
        ),
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
