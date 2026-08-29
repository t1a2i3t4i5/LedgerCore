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
import 'package:ledger_app/theme/ledger_tokens.dart';
import 'package:provider/provider.dart';

class _EmptyMemberProvider extends MemberProvider {
  _EmptyMemberProvider(super.db);

  @override
  Future<void> fetchMembers() async {}
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> pumpScreen(
    WidgetTester tester, {
    TextScaler textScaler = TextScaler.noScaling,
    MemberProvider? memberProvider,
  }) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => CategoryProvider(db)),
          ChangeNotifierProvider.value(
            value: memberProvider ?? MemberProvider(db),
          ),
          ChangeNotifierProvider(create: (_) => TransactionProvider(db)),
        ],
        child: MaterialApp(
          theme: ledgerTheme,
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                child: child!,
              ),
          home: const AddTransactionScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('金額欄は上部で中央揃えの大きな表示になる', (tester) async {
    await pumpScreen(tester);

    final amountFieldFinder = find.byType(TextFormField).first;
    final textField = tester.widget<TextField>(
      find.descendant(of: amountFieldFinder, matching: find.byType(TextField)),
    );

    expect(tester.getCenter(find.text('金額')).dx, closeTo(180, 0.1));
    expect(textField.textAlign, TextAlign.center);
    expect(textField.style, LedgerTokens.amountLarge);
    expect(textField.decoration?.border, InputBorder.none);
    expect(textField.decoration?.prefixIcon, isNull);
    final fittedBoxFinder = find.ancestor(
      of: amountFieldFinder,
      matching: find.byType(FittedBox),
    );
    expect(fittedBoxFinder, findsOneWidget);
    expect(tester.widget<FittedBox>(fittedBoxFinder).fit, BoxFit.scaleDown);
  });

  testWidgets('登録者はChoiceChipで選び、未選択ならエラーになる', (tester) async {
    await pumpScreen(tester);

    final memberId = (await db.getMembers()).first.id;
    final chip = tester.widget<ChoiceChip>(find.byType(ChoiceChip).first);
    expect(chip.selected, isTrue);

    await tester.tap(find.byType(ChoiceChip).first);
    await tester.pump();
    expect(
      tester.widget<ChoiceChip>(find.byType(ChoiceChip).first).selected,
      isFalse,
    );

    await tester.enterText(find.byType(TextFormField).first, '1200');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('登録者を選択してください'), findsOneWidget);
    expect(
      (await db.getMembers()).any((member) => member.id == memberId),
      isTrue,
    );
    expect(await db.getAllTransactions(), isEmpty);
  });

  testWidgets('メンバー読込中は本文用の補助色を使う', (tester) async {
    await pumpScreen(tester, memberProvider: _EmptyMemberProvider(db));

    final text = tester.widget<Text>(find.text('メンバー情報を読み込み中...'));
    expect(text.style?.color, ledgerTheme.colorScheme.onSurfaceVariant);
    expect(text.style?.color, isNot(LedgerTokens.subtext));
  });

  testWidgets('文字倍率2.0でも上限額を表示して例外が出ない', (tester) async {
    await pumpScreen(tester, textScaler: const TextScaler.linear(2));

    await tester.enterText(
      find.byType(TextFormField).first,
      kMaxAmount.toStringAsFixed(0),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
