import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'db/database.dart';
import 'providers/category_provider.dart';
import 'providers/member_provider.dart';
import 'providers/summary_provider.dart';
import 'providers/transaction_provider.dart';
import 'screens/main_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase();
  runApp(LedgerApp(db: db));
}

class LedgerApp extends StatelessWidget {
  final AppDatabase db;

  const LedgerApp({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MemberProvider(db)),
        ChangeNotifierProvider(create: (_) => TransactionProvider(db)),
        ChangeNotifierProvider(create: (_) => CategoryProvider(db)),
        ChangeNotifierProvider(create: (_) => SummaryProvider(db)),
      ],
      child: MaterialApp(
        title: '家計簿',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: Colors.teal,
          useMaterial3: true,
        ),
        // 認証は撤廃。起動後すぐにメイン画面へ。
        home: const MainScreen(),
      ),
    );
  }
}
