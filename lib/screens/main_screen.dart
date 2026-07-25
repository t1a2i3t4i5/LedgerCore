import 'package:flutter/material.dart';

import 'summary_screen.dart';
import 'transactions_screen.dart';
import 'categories_screen.dart';
import 'split_screen.dart';
import 'members_screen.dart';

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
    CategoriesScreen(),
    SplitScreen(),
  ];

  final _titles = const ['月次サマリー', '取引一覧', 'カテゴリ', '割り勘'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_currentIndex]),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_outline),
            tooltip: 'メンバー管理',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MembersScreen()),
              );
            },
          ),
        ],
      ),
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) =>
            setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'サマリー',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: '取引',
          ),
          NavigationDestination(
            icon: Icon(Icons.label_outline),
            selectedIcon: Icon(Icons.label),
            label: 'カテゴリ',
          ),
          NavigationDestination(
            icon: Icon(Icons.balance_outlined),
            selectedIcon: Icon(Icons.balance),
            label: '割り勘',
          ),
        ],
      ),
    );
  }
}
