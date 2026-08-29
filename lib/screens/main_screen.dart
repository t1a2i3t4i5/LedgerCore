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

  final _screens = const [
    SummaryScreen(),
    TransactionsScreen(),
    SplitScreen(),
    SettingsScreen(),
  ];

  /// ログに載せるタブ名。**画面内の見出しとは別に持つ。**
  /// op が英字なので detail も英字で揃え、画面の文言を変えてもログの
  /// 集計が壊れないようにする
  static const _logNames = ['summary', 'transactions', 'split', 'settings'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(bottom: false, child: _screens[_currentIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          // 別のタブへ移ったら、前のタブ向けの案内は消す。
          // SnackBar はこの Scaffold（ルートの ScaffoldMessenger）に出るので、
          // 放っておくとタブを移っても残る。取引の保存後に出る
          // 「その月を表示」をサマリータブで押すと、画面は何も変わらないまま
          // 取引一覧の表示月だけが裏で動く
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          // 選択中のタブを押し直したときは記録しない。NavigationBar は
          // 同じ行き先でもこのコールバックを呼ぶので、素直に書くと
          // from と to が同じ行がログに溜まる
          if (index != _currentIndex) {
            context.read<OperationLogger>().info(
              'tab.change',
              detail: {
                'from': _logNames[_currentIndex],
                'to': _logNames[index],
              },
            );
          }
          setState(() => _currentIndex = index);
        },
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
