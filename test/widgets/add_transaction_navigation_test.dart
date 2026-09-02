import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/models/transaction.dart';
import 'package:ledger_app/providers/category_provider.dart';
import 'package:ledger_app/providers/member_provider.dart';
import 'package:ledger_app/providers/transaction_provider.dart';
import 'package:ledger_app/screens/add_transaction_screen.dart';
import 'package:ledger_app/theme/ledger_theme.dart';
import 'package:provider/provider.dart';

class _DelayedTransactionProvider extends TransactionProvider {
  _DelayedTransactionProvider(super.db)
    : super(clock: () => DateTime(2026, 7, 15));

  final blocker = Completer<void>();
  int createCalls = 0;

  @override
  Future<void> create(TransactionInput input) async {
    createCalls++;
    await blocker.future;
    await super.create(input);
  }
}

void main() {
  late AppDatabase db;
  late _DelayedTransactionProvider provider;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() async => db.close());

  Future<ModalRoute<void>> openInput(WidgetTester tester) async {
    // 完了待ちは testWidgets と同じ擬似時間のゾーンで作る。
    provider = _DelayedTransactionProvider(db);
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => CategoryProvider(db)),
          ChangeNotifierProvider(create: (_) => MemberProvider(db)),
          ChangeNotifierProvider<TransactionProvider>.value(value: provider),
        ],
        child: MaterialApp(
          theme: ledgerTheme,
          initialRoute: '/transactions',
          routes: {
            // 一覧まで誤って pop されても Navigator 自体は壊さず、検証を続ける。
            '/': (_) => const Scaffold(body: Text('アプリのルート')),
            '/transactions':
                (context) => Scaffold(
                  body: TextButton(
                    onPressed:
                        () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => const AddTransactionScreen(),
                          ),
                        ),
                    child: const Text('入力画面を開く'),
                  ),
                  bottomNavigationBar: NavigationBar(
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.home),
                        label: 'ホーム',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.receipt),
                        label: '取引',
                      ),
                    ],
                  ),
                ),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('入力画面を開く'));
    await tester.pumpAndSettle();
    final category = (await db.getCategories()).first;
    final chip = find.widgetWithText(ChoiceChip, category.name);
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '1200');
    return ModalRoute.of<void>(
      tester.element(find.byType(AddTransactionScreen)),
    )!;
  }

  VoidCallback save(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed!;

  VoidCallback cancel(WidgetTester tester) =>
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'キャンセル'))
          .onPressed!;

  Future<void> finishSave(WidgetTester tester) async {
    provider.blocker.complete();
    await tester.pumpAndSettle();
  }

  void expectListRemains() {
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('アプリのルート'), findsNothing);
    expect(find.byType(AddTransactionScreen), findsNothing);
  }

  testWidgets('保存直後の同一フレームのキャンセルは無効で一覧を残す', (tester) async {
    final route = await openInput(tester);
    final onSave = save(tester);
    final onCancel = cancel(tester);
    onSave();
    onCancel();
    try {
      expect(route.isCurrent, isTrue, reason: '保存中のキャンセルが通っている');
    } finally {
      await finishSave(tester);
    }
    expectListRemains();
    expect((await db.getAllTransactions()).single.amount, 1200);
  });

  testWidgets('キャンセル直後の同一フレームの保存は開始しない', (tester) async {
    await openInput(tester);
    final onSave = save(tester);
    final onCancel = cancel(tester);
    onCancel();
    onSave();
    await finishSave(tester);
    expect(provider.createCalls, 0);
    expect(await db.getAllTransactions(), isEmpty);
    expectListRemains();
  });

  testWidgets('同一フレームでキャンセルを二度呼んでも一覧を残す', (tester) async {
    await openInput(tester);
    final onCancel = cancel(tester);
    onCancel();
    onCancel();
    await tester.pumpAndSettle();
    expectListRemains();
    expect(await db.getAllTransactions(), isEmpty);
  });

  for (final finishExit in [false, true]) {
    testWidgets('保存中に端末で戻っても一覧を残す（退場完了=$finishExit）', (tester) async {
      final route = await openInput(tester);
      save(tester)();
      await tester.binding.handlePopRoute();
      expect(route.isCurrent, isFalse);
      if (finishExit) {
        await tester.pumpAndSettle();
      } else {
        expect(find.byType(AddTransactionScreen), findsOneWidget);
      }
      await finishSave(tester);
      expectListRemains();
      expect((await db.getAllTransactions()).single.amount, 1200);
    });
  }

  for (final x in [100.0, 260.0]) {
    testWidgets('ヘッダの空白x=$xを押しても保存もキャンセルもしない', (tester) async {
      final route = await openInput(tester);
      await tester.tapAt(Offset(x, 28));
      try {
        expect(route.isCurrent, isTrue);
        expect(provider.createCalls, 0);
        expect(find.text('1200'), findsOneWidget);
      } finally {
        await finishSave(tester);
      }
    });
  }
}
