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

/// 取引追加画面の金額欄が 0 以下・小数・上限超過を弾くことを確認する。
/// DB 側の CHECK 制約は database_test.dart 側で担保しており、
/// ここでは「入り口で止まって保存に到達しない」ことを見る。
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  /// [existing] を渡すと編集モードで開く
  Future<void> pumpScreen(
    WidgetTester tester, {
    TransactionView? existing,
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

  /// フォーマッタを経由しない経路（コントローラへの直接代入）で金額を入れる。
  /// 入力欄からは打てない値に対して validator が保険になっているかを見るのに使う。
  void setAmountDirectly(WidgetTester tester, String text) {
    tester
        .state<FormFieldState<String>>(find.byType(TextFormField).first)
        .didChange(text);
  }

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

  testWidgets('小数点は入力自体を受け付けない', (tester) async {
    await pumpScreen(tester);

    // 小数は全画面 NumberFormat('#,###') で表示されないため、
    // 保存できても読めない値にしかならない。入り口で落とす
    await tester.enterText(amountField(), '1234.5');
    await tester.pump();

    // 小数点は「除去」なので桁が詰まり、1234.5 は 12345 になる（10 倍）。
    // マイナス記号の除去と違って値が増える方向なので、意図した挙動として
    // ここで固定しておく
    expect(find.text('1234.5'), findsNothing);
    expect(find.text('12345'), findsOneWidget);
  });

  testWidgets('全角数字は半角に直して受け付ける', (tester) async {
    await pumpScreen(tester);

    // 日本語 IME で全角のまま打つケース。落とすだけだと欄が空になってしまう
    await tester.enterText(amountField(), '１２３４');
    await tester.pump();

    expect(find.text('1234'), findsOneWidget);
  });

  testWidgets('全角ピリオドは金額に残らない', (tester) async {
    await pumpScreen(tester);

    await tester.enterText(amountField(), '１２３４．５');
    await tester.pump();

    // 半角の小数点と同じく除去され、桁が詰まる。
    //
    // 注意: このテストは「正規化 regex が `．` を含むか」を区別できない。
    // 含む場合は一度 `1234.5` になってから後段の allow(RegExp(r'[0-9]')) が
    // `.` を落とすため、どちらでも結果は `12345` に収束する。
    // ここで固定しているのは経路ではなく「全角ピリオドは金額に残らない」
    // という外から見える事実だけ
    expect(find.text('12345'), findsOneWidget);
  });

  testWidgets('取引を編集して保存し直しても金額が変わらない', (tester) async {
    final cats = await db.getCategories();
    final memberId = (await db.getMembers()).first.id;
    await db.insertTransaction(TransactionInput(
      memberId: memberId,
      categoryId: cats.first.id,
      amount: 1234,
      spentAt: DateTime(2026, 7, 10),
    ));
    final existing = (await db.getAllTransactions()).single;

    await pumpScreen(tester, existing: existing);
    expect(find.text('1234'), findsOneWidget);

    // 金額に触らず保存し直しても値は変わらない。
    // ただし「保存後も 1234」だけを見ると、保存が一度も実行されなくても
    // 通ってしまう。メモを書き換えて、更新が実際に走ったことを併せて確かめる
    await tester.enterText(find.byType(TextFormField).last, '保存し直した');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final saved = (await db.getAllTransactions()).single;
    expect(saved.memo, '保存し直した', reason: '更新が実行されていない');
    expect(saved.amount, 1234);
  });

  testWidgets('整数の取引は編集画面で小数部を出さない', (tester) async {
    final cats = await db.getCategories();
    final memberId = (await db.getMembers()).first.id;
    await db.insertTransaction(TransactionInput(
      memberId: memberId,
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

    // 桁数制限で打ち切られる（マイナス記号と同じく入力の時点で分かる）。
    // 期待値はリテラルで持たず kMaxAmount から導出する。入力欄の桁数制限も
    // 同じ源から採っているので、上限を変えると実装とテストが揃って追随する
    final maxDigits = kMaxAmount.toStringAsFixed(0).length;
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, '9' * maxDigits);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    // 保存されるのは有限の値だけ。Infinity は DB に届かない
    final saved = (await db.getAllTransactions()).single.amount;
    expect(saved.isFinite, isTrue, reason: 'Infinity が保存されている');
    // 桁数いっぱいに 9 を並べた値が、そのまま上限額と一致する
    // （桁数制限と kMaxAmount が食い違うとここで落ちる）
    expect(saved, kMaxAmount);
  });

  testWidgets('上限を超える金額はエラーになる', (tester) async {
    await pumpScreen(tester);
    await selectFirstCategory(tester);

    // フォーマッタを通らない経路（コントローラへの直接代入）の保険を確かめる
    // 期待値はリテラルで持たない（上限を変えたら追随させる）
    setAmountDirectly(tester, (kMaxAmount + 1).toStringAsFixed(0));
    await tester.pump();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('金額が大きすぎます'), findsOneWidget);
    expect(await db.getAllTransactions(), isEmpty);
  });

  // validator の `!amount.isFinite` を守るテスト。
  // NaN は `> kMaxAmount` も `<= 0` も false になるため、このガードを外すと
  // 「金額は整数で入力してください」という的外れなメッセージに変わる
  // （NaN != NaN が true なので整数チェックに落ちる）。
  // Infinity のほうは上限比較でも止まるので、ガードの有無を区別できない
  testWidgets('NaN は「大きすぎます」で止まる', (tester) async {
    await pumpScreen(tester);
    await selectFirstCategory(tester);

    setAmountDirectly(tester, 'NaN');
    await tester.pump();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('金額が大きすぎます'), findsOneWidget);
    expect(find.text('金額は整数で入力してください'), findsNothing);
    expect(await db.getAllTransactions(), isEmpty);
  });

  testWidgets('指数表記で飽和させた値も保存されない', (tester) async {
    await pumpScreen(tester);
    await selectFirstCategory(tester);

    // double.tryParse('1e400') は Infinity になる
    setAmountDirectly(tester, '1e400');
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

  testWidgets('小数はコントローラへ直接代入してもエラーになる', (tester) async {
    await pumpScreen(tester);
    await selectFirstCategory(tester);

    // フォーマッタが小数点を通さないので画面からは到達しないが、
    // DB の CHECK と揃える二重の守りとして validator も見ている
    setAmountDirectly(tester, '1234.5');
    await tester.pump();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('金額は整数で入力してください'), findsOneWidget);
    expect(await db.getAllTransactions(), isEmpty);
  });

  testWidgets('空欄・非数値のエラーメッセージは従来どおり', (tester) async {
    await pumpScreen(tester);
    await selectFirstCategory(tester);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('金額を入力してください'), findsOneWidget);

    // 数字しか通らなくなったので、非数値はフォーマッタを経由しない
    // 直接代入で作る
    setAmountDirectly(tester, 'abc');
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
