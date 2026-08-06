import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/models/transaction.dart';
import 'package:ledger_app/providers/category_provider.dart';
import 'package:ledger_app/providers/member_provider.dart';
import 'package:ledger_app/providers/transaction_provider.dart';
import 'package:ledger_app/screens/transaction_filter_sheet.dart';
import 'package:ledger_app/widgets/amount_input_formatter.dart';
import 'package:provider/provider.dart';

/// フィルターシートの金額欄が取引追加画面と同じ挙動になっていることを確認する。
///
/// フィルタの入力値は DB に保存されないので CHECK 制約では守られない。
/// 同じアプリ内で入力の受け付け方が割れていると、「追加画面では全角がそのまま
/// 通るのに、フィルターでは理由の分からないエラーになる」という食い違いが出る。
void main() {
  late AppDatabase db;
  late TransactionProvider provider;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    provider = TransactionProvider(db);
  });
  tearDown(() async => db.close());

  /// 実画面と同じく `showModalBottomSheet` で開く。
  ///
  /// シートを直接 `home` に置くと、`_apply` の `Navigator.pop()` が唯一のルートを
  /// 外してツリーが空になる。その状態では `find.text(...)` が何に対しても
  /// `findsNothing` になり、「エラーが出ていないこと」を見るアサーションが
  /// 無条件に通ってしまう（実際、成功パスに `_showError` を差し込んでも通った）。
  /// シートの下に画面を残しておけば、pop 後も SnackBar を検出できる。
  Future<void> pumpSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => CategoryProvider(db)),
          ChangeNotifierProvider(create: (_) => MemberProvider(db)),
          ChangeNotifierProvider.value(value: provider),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const TransactionFilterSheet(),
                ),
                child: const Text('シートを開く'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('シートを開く'));
    await tester.pumpAndSettle();
  }

  Finder minField() => find.widgetWithText(TextFormField, '最小 (¥)');
  Finder maxField() => find.widgetWithText(TextFormField, '最大 (¥)');

  testWidgets('全角数字は半角に直して受け付ける', (tester) async {
    await pumpSheet(tester);

    // 従来は正規化が無く、double.tryParse が null を返して
    // 「最小金額が不正な値です」とだけ出ていた
    await tester.enterText(minField(), '１０００');
    await tester.pump();

    await tester.tap(find.text('適用'));
    await tester.pumpAndSettle();

    expect(find.text('最小金額が不正な値です'), findsNothing);
    expect(provider.filterMinAmount, 1000);
  });

  testWidgets('小数点とマイナス記号は入力自体を受け付けない', (tester) async {
    await pumpSheet(tester);

    await tester.enterText(minField(), '-1234.5');
    await tester.pump();

    expect(find.text('-1234.5'), findsNothing);
    expect(find.text('12345'), findsOneWidget);
  });

  testWidgets('桁を打ち続けても上限の桁数で打ち切られる', (tester) async {
    await pumpSheet(tester);

    await tester.enterText(maxField(), '9' * 400);
    await tester.pump();

    // 期待値はリテラルで持たない。上限を変えたときに追随させる
    final field = tester.widget<TextField>(
      find.descendant(of: maxField(), matching: find.byType(TextField)),
    );
    expect(field.controller!.text, '9' * maxAmountInputLength);
  });

  testWidgets('設定済みの条件が復元され、打ち替えた分だけ適用される', (tester) async {
    provider.setFilters(
      categoryIds: const {},
      userIds: const {},
      minAmount: 1234,
      maxAmount: 5678,
      memoQuery: '',
    );

    await pumpSheet(tester);
    // 開いた時点の表示（復元経路）
    expect(find.text('1234'), findsOneWidget);
    expect(find.text('5678'), findsOneWidget);

    // 事前値と違う値に打ち替えてから適用する。
    // 事前値のまま「触らずに適用」を検証すると、_apply が Provider に一切
    // 書き戻さなくても事前値が残って通ってしまい、往復を検証できない
    await tester.enterText(minField(), '2345');
    await tester.tap(find.text('適用'));
    await tester.pumpAndSettle();

    expect(provider.filterMinAmount, 2345);
    // 触っていない側は復元された値がそのまま往復する
    expect(provider.filterMaxAmount, 5678);
  });

  // フォーマッタは composing 中（IME の変換確定前）を素通しする。これは IME を
  // 壊さないための仕様なので、桁数制限を抜けた値がコントローラに入りうる。
  // 400 桁は double.tryParse が Infinity として解釈するため、null チェックだけの
  // バリデーションでは止まらない。Infinity が入ると全件が除外され、開き直すと
  // 欄に 'Infinity' が表示され、再適用しても同じ状態のまま固定される。
  testWidgets('composing 中に送られた桁あふれは適用されない', (tester) async {
    await pumpSheet(tester);
    await tester.tap(minField());
    await tester.pump();

    tester.testTextInput.updateEditingValue(TextEditingValue(
      text: '9' * 400,
      selection: const TextSelection.collapsed(offset: 400),
      composing: const TextRange(start: 0, end: 400),
    ));
    await tester.pump();

    await tester.tap(find.text('適用'));
    await tester.pumpAndSettle();

    expect(find.text('最小金額が不正な値です'), findsOneWidget);
    expect(provider.filterMinAmount, isNull);
  });

  testWidgets('上限を超える値は適用されない', (tester) async {
    await pumpSheet(tester);
    await tester.tap(minField());
    await tester.pump();

    // 桁数制限を抜ける経路（composing）で上限超過の有限値を送る
    final over = (kMaxAmount + 1).toStringAsFixed(0);
    tester.testTextInput.updateEditingValue(TextEditingValue(
      text: over,
      selection: TextSelection.collapsed(offset: over.length),
      composing: TextRange(start: 0, end: over.length),
    ));
    await tester.pump();

    await tester.tap(find.text('適用'));
    await tester.pumpAndSettle();

    expect(find.text('最小金額が不正な値です'), findsOneWidget);
    expect(provider.filterMinAmount, isNull);
  });

  testWidgets('最小が最大より大きいと適用されない', (tester) async {
    await pumpSheet(tester);

    await tester.enterText(minField(), '5000');
    await tester.enterText(maxField(), '1000');
    await tester.tap(find.text('適用'));
    await tester.pumpAndSettle();

    expect(find.text('最小金額は最大金額以下にしてください'), findsOneWidget);
    expect(provider.filterMinAmount, isNull);
  });
}
