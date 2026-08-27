import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/member_provider.dart';

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

  Future<void> _showEditDialog({int? id, String? currentName}) async {
    final ctrl = TextEditingController(text: currentName);
    final isEdit = id != null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text(isEdit ? 'メンバーを編集' : 'メンバーを追加'),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'メンバー名',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('キャンセル'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('保存'),
              ),
            ],
          ),
    );

    if (confirmed != true || !mounted) return;
    final name = ctrl.text.trim();
    if (name.isEmpty) return;

    final provider = context.read<MemberProvider>();
    try {
      if (isEdit) {
        await provider.updateMember(id, name);
      } else {
        await provider.addMember(name);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失敗: $e')));
      }
    }
  }

  Future<void> _delete(int id, String name, int memberCount) async {
    if (memberCount <= 1) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('最後のメンバーは削除できません')));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('メンバーを削除'),
            content: Text('「$name」を削除しますか？\nこのメンバーの取引が残っている場合は削除できません。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('キャンセル'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  '削除',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ),
    );

    if (confirmed == true && mounted) {
      try {
        await context.read<MemberProvider>().deleteMember(id);
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
      appBar: AppBar(title: const Text('メンバー管理')),
      body: Consumer<MemberProvider>(
        builder: (context, provider, _) {
          if (provider.membersLoading && provider.members.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          final members = provider.members;
          if (members.isEmpty) {
            return const Center(child: Text('メンバーがいません'));
          }
          return ListView.separated(
            itemCount: members.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final m = members[index];
              return ListTile(
                leading: CircleAvatar(child: Text(m.name.substring(0, 1))),
                title: Text(m.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed:
                          () => _showEditDialog(id: m.id, currentName: m.name),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      onPressed: () => _delete(m.id, m.name, members.length),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
