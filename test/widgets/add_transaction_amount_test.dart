import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/models/transaction.dart';
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

  /// [existing] を渡すと編集モードで開く
  Future<void> pumpScreen(
    WidgetTester tester, {
    TransactionResponse? existing,
  }) async {
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
        child: MaterialApp(home: AddTransactionScreen(existing: existing)),
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

  testWidgets('全角数字は半角に直して受け付ける', (tester) async {
    await pumpScreen(tester);

    // 日本語 IME で全角のまま打つケース。落とすだけだと欄が空になってしまう
    await tester.enterText(amountField(), '１２３４．５');
    await tester.pump();

    expect(find.text('1234.5'), findsOneWidget);
  });

  testWidgets('小数を含む取引を編集して保存しても値が丸まらない', (tester) async {
    final cats = await db.getCategories();
    final memberId = (await db.getMembers()).first.id;
    await db.insertTransaction(TransactionRequest(
      userId: memberId,
      categoryId: cats.first.id,
      amount: 1234.5,
      spentAt: DateTime(2026, 7, 10),
    ));
    final existing = (await db.getAllTransactions()).single;

    await pumpScreen(tester, existing: existing);
    // 編集画面には小数がそのまま出る（toStringAsFixed(0) だと 1235 になっていた）
    expect(find.text('1234.5'), findsOneWidget);

    // 金額に触らず保存し直しても値は変わらない。
    // ただし「保存後も 1234.5」だけを見ると、保存が一度も実行されなくても
    // 通ってしまう。メモを書き換えて、更新が実際に走ったことを併せて確かめる
    await tester.enterText(find.byType(TextFormField).last, '保存し直した');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final saved = (await db.getAllTransactions()).single;
    expect(saved.memo, '保存し直した', reason: '更新が実行されていない');
    expect(saved.amount, 1234.5);
  });

  testWidgets('整数の取引は編集画面で小数部を出さない', (tester) async {
    final cats = await db.getCategories();
    final memberId = (await db.getMembers()).first.id;
    await db.insertTransaction(TransactionRequest(
      userId: memberId,
      categoryId: cats.first.id,
      amount: 1000,
      spentAt: DateTime(2026, 7, 10),
    ));
    final existing = (await db.getAllTransactions()).single;

    await pumpScreen(tester, existing: existing);

    expect(find.text('1000'), findsOneWidget);
    expect(find.text('1000.0'), findsNothing);
  });

  testWidgets('桁を打ち続けても Infinity が保存されない', (tester) async {
    await pumpScreen(tester);
    await selectFirstCategory(tester);

    // 上限が無いと double が Infinity に飽和する。Infinity は `> 0` を満たすので
    // validator も DB の CHECK もすり抜け、円グラフの構成比が Inf/Inf = NaN になり
    // その行を手で消すまで合計が復旧しない
    await tester.enterText(amountField(), '9' * 400);
    await tester.pump();

    // 桁数制限で打ち切られる（マイナス記号と同じく入力の時点で分かる）
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, '9' * 12);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    // 保存されるのは有限の値だけ。Infinity は DB に届かない
    final saved = (await db.getAllTransactions()).single.amount;
    expect(saved.isFinite, isTrue, reason: 'Infinity が保存されている');
    expect(saved, 999999999999);
  });

  testWidgets('上限を超える金額はエラーになる', (tester) async {
    await pumpScreen(tester);
    await selectFirstCategory(tester);

    // フォーマッタを通らない経路（コントローラへの直接代入）の保険を確かめる
    final state = tester.state<FormFieldState<String>>(
      find.byType(TextFormField).first,
    );
    state.didChange('1000000000000'); // 1 兆（上限 999,999,999,999 の 1 つ上）
    await tester.pump();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('金額が大きすぎます'), findsOneWidget);
    expect(await db.getAllTransactions(), isEmpty);
  });

  testWidgets('IME の変換確定前は入力を書き換えない', (tester) async {
    await pumpScreen(tester);
    await tester.tap(amountField());
    await tester.pump();

    // enterText は composing を空で送るので、この経路は通らない。
    // 実機の IME を再現するには composing 範囲を明示して送る必要がある
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: '１２３',
      selection: TextSelection.collapsed(offset: 3),
      composing: TextRange(start: 0, end: 3),
    ));
    await tester.pump();

    // 確定前に本文だけ書き換えると IME 側のバッファと食い違う
    final composing = tester.widget<TextField>(find.byType(TextField).first);
    expect(composing.controller!.text, '１２３');

    // 確定（composing が空）になった時点で正規化される
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: '１２３',
      selection: TextSelection.collapsed(offset: 3),
    ));
    await tester.pump();

    final committed = tester.widget<TextField>(find.byType(TextField).first);
    expect(committed.controller!.text, '123');
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
