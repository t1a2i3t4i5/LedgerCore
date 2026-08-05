import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/providers/category_provider.dart';
import 'package:ledger_app/providers/member_provider.dart';
import 'package:ledger_app/providers/transaction_provider.dart';
import 'package:ledger_app/screens/transaction_filter_sheet.dart';
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
        child: const MaterialApp(
          home: Scaffold(body: TransactionFilterSheet()),
        ),
      ),
    );
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

  testWidgets('桁を打ち続けても 12 桁で打ち切られる', (tester) async {
    await pumpSheet(tester);

    await tester.enterText(maxField(), '9' * 400);
    await tester.pump();

    final field = tester.widget<TextField>(
      find.descendant(of: maxField(), matching: find.byType(TextField)),
    );
    expect(field.controller!.text, '9' * 12);
  });

  testWidgets('設定済みの条件は開き直しても変わらない', (tester) async {
    provider.setFilters(
      categoryIds: const {},
      userIds: const {},
      minAmount: 1234,
      maxAmount: 5678,
      memoQuery: '',
    );

    await pumpSheet(tester);
    // 開いた時点の表示
    expect(find.text('1234'), findsOneWidget);
    expect(find.text('5678'), findsOneWidget);

    // 触らずに適用しても条件が変わらない
    await tester.tap(find.text('適用'));
    await tester.pumpAndSettle();

    expect(provider.filterMinAmount, 1234);
    expect(provider.filterMaxAmount, 5678);
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
