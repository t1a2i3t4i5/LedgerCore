import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/providers/category_provider.dart';
import 'package:ledger_app/providers/member_provider.dart';
import 'package:ledger_app/providers/transaction_provider.dart';
import 'package:ledger_app/screens/add_transaction_screen.dart';
import 'package:provider/provider.dart';

/// 取引追加画面の金額欄が 0 以下を弾くことを確認する。
/// DB 側の CHECK 制約は database_test.dart 側で担保しており、
/// ここでは「入り口で止まって保存に到達しない」ことを見る。
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => CategoryProvider(db)),
          ChangeNotifierProvider(create: (_) => MemberProvider(db)),
          ChangeNotifierProvider(create: (_) => TransactionProvider(db)),
        ],
        child: const MaterialApp(home: AddTransactionScreen()),
      ),
    );
    // initState の postFrameCallback でカテゴリ・メンバーを読むので落ち着かせる
    await tester.pumpAndSettle();
  }

  /// カテゴリ未選択で保存が止まらないよう、先頭カテゴリを選んでおく
  Future<void> selectFirstCategory(WidgetTester tester) async {
    final firstCategory = (await db.getCategories()).first.name;
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(firstCategory).last);
    await tester.pumpAndSettle();
  }

  Finder amountField() => find.byType(TextFormField).first;

  testWidgets('0 を入れて保存するとエラーが出て保存されない', (tester) async {
    await pumpScreen(tester);
    await selectFirstCategory(tester);

    await tester.enterText(amountField(), '0');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('金額は 0 より大きい値を入力してください'), findsOneWidget);
    expect(await db.getAllTransactions(), isEmpty);
  });

  testWidgets('マイナス記号は入力自体を受け付けない', (tester) async {
    await pumpScreen(tester);

    await tester.enterText(amountField(), '-500');
    await tester.pump();

    // inputFormatters がマイナス記号を落とすので 500 になる
    expect(find.text('-500'), findsNothing);
    expect(find.text('500'), findsOneWidget);
  });

  testWidgets('小数点は入力できる', (tester) async {
    await pumpScreen(tester);

    await tester.enterText(amountField(), '1234.5');
    await tester.pump();

    expect(find.text('1234.5'), findsOneWidget);
  });

  testWidgets('空欄・非数値のエラーメッセージは従来どおり', (tester) async {
    await pumpScreen(tester);
    await selectFirstCategory(tester);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('金額を入力してください'), findsOneWidget);

    // 数字と小数点しか通らないので、非数値は「.」の連続で作る
    await tester.enterText(amountField(), '..');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('有効な数値を入力してください'), findsOneWidget);
  });

  testWidgets('正の金額なら保存できる', (tester) async {
    await pumpScreen(tester);
    await selectFirstCategory(tester);

    await tester.enterText(amountField(), '1200');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final txns = await db.getAllTransactions();
    expect(txns.single.amount, 1200);
  });
}
