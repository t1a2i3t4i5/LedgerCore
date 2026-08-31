import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logging/operation_logger.dart';
import '../logging/log_share.dart';
import '../widgets/ledger_card.dart';
import '../widgets/page_header.dart';
import 'categories_screen.dart';
import 'members_screen.dart';

/// 家計に関わる管理画面への入口をまとめる画面。
class SettingsScreen extends StatefulWidget {
  /// 再描画前でも、タブの選択が変わった時点で false になる。
  final bool Function() isActive;

  const SettingsScreen({super.key, required this.isActive});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _sharing = false;

  Future<void> _shareLogs(BuildContext buttonContext) async {
    if (_sharing || !mounted || !widget.isActive()) return;
    setState(() => _sharing = true);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final logger = context.read<OperationLogger>();
    try {
      final box = buttonContext.findRenderObject()! as RenderBox;
      final pending = context.read<LogShare>().share(
        origin: box.localToGlobal(Offset.zero) & box.size,
      );
      // 読み出しを先に予約し、押下記録だけで空ログ判定が変わるのを防ぐ。
      logger.info('log.share');
      final shared = await pending;
      if (!mounted || !widget.isActive()) return;
      if (!shared) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('共有できるログがありません')));
      }
    } catch (e) {
      logger.error('log.share', e);
      if (!mounted || !widget.isActive()) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ログの共有に失敗しました')));
    } finally {
      if (mounted && widget.isActive()) setState(() => _sharing = false);
    }
  }

  void _openScreen(
    BuildContext context, {
    required String logName,
    required Widget screen,
  }) {
    context.read<OperationLogger>().info(
      'screen.open',
      detail: {'name': logName},
    );
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const PageHeader(title: '設定'),
        const SizedBox(height: 24),
        Text('家計', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        LedgerCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.label_outline),
                title: const Text('カテゴリ管理'),
                trailing: const Icon(Icons.chevron_right),
                onTap:
                    () => _openScreen(
                      context,
                      logName: 'categories',
                      screen: const CategoriesScreen(),
                    ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.people_outline),
                title: const Text('メンバー管理'),
                trailing: const Icon(Icons.chevron_right),
                onTap:
                    () => _openScreen(
                      context,
                      logName: 'members',
                      screen: const MembersScreen(),
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('サポート', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        LedgerCard(
          padding: EdgeInsets.zero,
          child: Builder(
            builder:
                (buttonContext) => ListTile(
                  leading: const Icon(Icons.share_outlined),
                  title: const Text('ログを共有'),
                  subtitle: const Text('ログにはカテゴリ名・メンバー名・金額が含まれます。共有先にご注意ください。'),
                  enabled: !_sharing,
                  onTap: () => _shareLogs(buttonContext),
                ),
          ),
        ),
      ],
    );
  }
}
