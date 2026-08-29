import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/main.dart';
import 'package:ledger_app/models/transaction.dart';
import 'package:ledger_app/screens/settings_screen.dart';
import 'package:ledger_app/screens/split_screen.dart';
import 'package:ledger_app/screens/transactions_screen.dart';
import 'package:ledger_app/widgets/month_selector.dart';
import 'package:ledger_app/widgets/page_header.dart';

/// ルートの AppBar を画面内見出しへ移した配線を、LedgerApp 全体で確認する。
///
/// PageHeader 単体の倍率・leading・actions は page_header_test.dart が見る。
/// ここでは各タブが正しい見出しを採用し、実際のスクロール領域へ載せたことを
/// 守る。NavigationBar の同名ラベルを拾わないよう、画面の子孫へ絞って探す。
void main() {
  late AppDatabase db;

  final fixedNow = DateTime(2026, 7, 15);

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(LedgerApp(db: db, clock: () => fixedNow));
    await tester.pumpAndSettle();
  }

  Finder headerIn(Type screenType, String title) => find.descendant(
    of: find.byType(screenType),
    matching: find.descendant(
      of: find.byType(PageHeader),
      matching: find.text(title),
    ),
  );

  void expectThemeHeading(WidgetTester tester, Type screenType, String title) {
    final finder = headerIn(screenType, title);
    expect(finder, findsOneWidget);
    final text = tester.widget<Text>(finder);
    final context = tester.element(finder);
    expect(text.style, Theme.of(context).textTheme.headlineMedium);
  }

  testWidgets('文字倍率2.0でも4タブが AppBar なしで正しい大見出しを描く', (tester) async {
    await pumpApp(tester);

    // ホームだけはページ名ではなく、既存の年月見出しを使う。
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(PageHeader), findsNothing);
    expect(find.byType(MonthSelector), findsOneWidget);
    expect(find.text('2026年7月'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing);
    expectThemeHeading(tester, TransactionsScreen, '取引');
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.balance_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing);
    expectThemeHeading(tester, SplitScreen, '精算');
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing);
    expectThemeHeading(tester, SettingsScreen, '設定');
    expect(tester.takeException(), isNull);

    final navigationBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(
      navigationBar.destinations.cast<NavigationDestination>().map(
        (destination) => destination.label,
      ),
      ['ホーム', '取引', '割り勘', '設定'],
    );
  });

  testWidgets('取引の大見出しは一覧と一緒にスクロールする', (tester) async {
    final categories = await db.getCategories();
    final members = await db.getMembers();
    for (var day = 1; day <= 20; day++) {
      await db.insertTransaction(
        TransactionInput(
          memberId: members.first.id,
          categoryId: categories[day % categories.length].id,
          amount: day * 100,
          spentAt: DateTime(2026, 7, day),
        ),
      );
    }
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pumpAndSettle();

    final heading = headerIn(TransactionsScreen, '取引');
    expect(heading.hitTestable(), findsOneWidget);

    await tester.drag(
      find.descendant(
        of: find.byType(TransactionsScreen),
        matching: find.byType(CustomScrollView),
      ),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();

    // ListView の外へ固定すると、スクロール後も hitTestable のままになる。
    expect(heading.hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
