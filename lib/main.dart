import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'db/database.dart';
import 'providers/category_provider.dart';
import 'providers/member_provider.dart';
import 'providers/month_scoped_provider.dart';
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

  /// 表示月の基準となる「今」。既定（null）は [DateTime.now]。
  /// テストから固定時刻を注入して、画面を実時刻から切り離すために使う
  final Clock? clock;

  const LedgerApp({super.key, required this.db, this.clock});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MemberProvider(db)),
        ChangeNotifierProvider(create: (_) => TransactionProvider(db, clock: clock)),
        ChangeNotifierProvider(create: (_) => CategoryProvider(db)),
        ChangeNotifierProvider(create: (_) => SummaryProvider(db, clock: clock)),
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
