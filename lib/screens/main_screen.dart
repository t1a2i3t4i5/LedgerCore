import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logging/operation_logger.dart';
import 'settings_screen.dart';
import 'split_screen.dart';
import 'summary_screen.dart';
import 'transactions_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  late final _screens = [
    SummaryScreen(onOpenSplit: () => _selectTab(2)),
    const TransactionsScreen(),
    const SplitScreen(),
    const SettingsScreen(),
  ];

  /// ログに載せるタブ名。**画面内の見出しとは別に持つ。**
  /// op が英字なので detail も英字で揃え、画面の文言を変えてもログの
  /// 集計が壊れないようにする
  static const _logNames = ['summary', 'transactions', 'split', 'settings'];

  /// ナビゲーションバーとホームの精算カードで、通知とログの扱いを揃える。
  void _selectTab(int index) {
    // 前のタブ向けの案内（取引保存後の「その月を表示」など）を残さない。
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    // 選択中のタブを押し直したときは記録しない。
    if (index != _currentIndex) {
      context.read<OperationLogger>().info(
        'tab.change',
        detail: {'from': _logNames[_currentIndex], 'to': _logNames[index]},
      );
    }
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(bottom: false, child: _screens[_currentIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'ホーム',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: '取引',
          ),
          NavigationDestination(
            icon: Icon(Icons.balance_outlined),
            selectedIcon: Icon(Icons.balance),
            label: '割り勘',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '設定',
          ),
        ],
      ),
    );
  }
}
