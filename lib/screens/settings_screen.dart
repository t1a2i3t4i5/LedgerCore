import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logging/operation_logger.dart';
import '../widgets/ledger_card.dart';
import 'categories_screen.dart';
import 'members_screen.dart';

/// 家計に関わる管理画面への入口をまとめる画面。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
      ],
    );
  }
}
