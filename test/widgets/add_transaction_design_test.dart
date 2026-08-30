import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/models/transaction.dart';
import 'package:ledger_app/providers/category_provider.dart';
import 'package:ledger_app/providers/member_provider.dart';
import 'package:ledger_app/providers/transaction_provider.dart';
import 'package:ledger_app/screens/add_transaction_screen.dart';
import 'package:ledger_app/theme/ledger_theme.dart';
import 'package:ledger_app/theme/ledger_tokens.dart';
import 'package:ledger_app/widgets/ledger_card.dart';
import 'package:provider/provider.dart';

class _EmptyMemberProvider extends MemberProvider {
  _EmptyMemberProvider(super.db);

  @override
  Future<void> fetchMembers() async {}
}

class _BlockingTransactionProvider extends TransactionProvider {
  _BlockingTransactionProvider(super.db);

  final blocker = Completer<void>();
  int createCalls = 0;

  @override
  Future<void> create(TransactionInput input) async {
    createCalls++;
    await blocker.future;
  }
}

RenderEditable _findRenderEditable(RenderObject root) {
  RenderEditable? result;
  void visit(RenderObject child) {
    if (child is RenderEditable) {
      result = child;
      return;
    }
    child.visitChildren(visit);
  }

  visit(root);
  return result!;
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> pumpScreen(
    WidgetTester tester, {
    TextScaler textScaler = TextScaler.noScaling,
    MemberProvider? memberProvider,
    TransactionProvider? transactionProvider,
    Size size = const Size(360, 690),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => CategoryProvider(db)),
          ChangeNotifierProvider.value(
            value: memberProvider ?? MemberProvider(db),
          ),
          ChangeNotifierProvider.value(
            value: transactionProvider ?? TransactionProvider(db),
          ),
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

  Future<void> selectFirstCategory(WidgetTester tester) async {
    final firstCategory = (await db.getCategories()).first.name;
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(firstCategory).last);
    await tester.pumpAndSettle();
  }

  testWidgets('金額欄は上部で中央揃えの大きな表示になる', (tester) async {
    await pumpScreen(tester);

    final amountFieldFinder = find.byType(TextFormField).first;
    final textField = tester.widget<TextField>(
      find.descendant(of: amountFieldFinder, matching: find.byType(TextField)),
    );

    expect(tester.widget<Text>(find.text('金額')).textAlign, TextAlign.center);
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

  testWidgets('3分割ヘッダと下部保存ボタン、内容と日付のカードを表示する', (tester) async {
    await pumpScreen(tester);

    expect(find.byType(AppBar), findsNothing);
    expect(find.text('キャンセル'), findsOneWidget);
    expect(find.text('支出を追加'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '保存する'), findsOneWidget);

    final card = find.byType(LedgerCard);
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('内容')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('日付')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('メモ（任意）')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.byIcon(Icons.calendar_today)),
      findsOneWidget,
    );
  });

  testWidgets('320px幅かつ文字倍率2.0でも3分割ヘッダが溢れない', (tester) async {
    await pumpScreen(
      tester,
      textScaler: const TextScaler.linear(2),
      size: const Size(320, 690),
    );

    expect(tester.takeException(), isNull);
    final cancelRect = tester.getRect(find.text('キャンセル'));
    final titleRect = tester.getRect(find.text('支出を追加'));
    final saveRect = tester.getRect(find.text('保存'));
    final cancelButtonRect = tester.getRect(
      find.widgetWithText(TextButton, 'キャンセル'),
    );
    final saveButtonRect = tester.getRect(
      find.widgetWithText(TextButton, '保存'),
    );
    expect(cancelRect.right, lessThanOrEqualTo(titleRect.left));
    expect(titleRect.right, lessThanOrEqualTo(saveRect.left));
    expect(titleRect.center.dx, closeTo(160, 2));
    expect(cancelButtonRect.width, closeTo((320 - 16) / 3, 1));
    expect(saveButtonRect.width, closeTo(cancelButtonRect.width, 1));
  });

  testWidgets('320px幅かつ文字倍率2.0でも別月警告の末尾を省略しない', (tester) async {
    final provider = TransactionProvider(
      db,
      clock: () => DateTime(2000, 1, 15),
    );
    await pumpScreen(
      tester,
      textScaler: const TextScaler.linear(2),
      transactionProvider: provider,
      size: const Size(320, 690),
    );

    const warning = '表示中の2000年1月とは別の月です';
    final paragraph = tester.renderObject<RenderParagraph>(find.text(warning));
    expect(paragraph.didExceedMaxLines, isFalse);
  });

  testWidgets('日付行の波紋をカード背景より手前に描くMaterialを持つ', (tester) async {
    await pumpScreen(tester);

    final card = find.byType(LedgerCard);
    final material = find.descendant(of: card, matching: find.byType(Material));
    expect(material, findsOneWidget);
    expect(tester.widget<Material>(material).type, MaterialType.transparency);
  });

  testWidgets('キーボード表示中も下部の保存ボタン全体が上端より上に残る', (tester) async {
    await pumpScreen(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    final saveRect = tester.getRect(find.widgetWithText(FilledButton, '保存する'));
    const keyboardTop = 690 - 300;
    expect(
      saveRect.bottom,
      lessThanOrEqualTo(keyboardTop),
      reason: '保存ボタンがキーボードに隠れている',
    );
  });

  testWidgets('下部の保存ボタンからも同じ保存処理を実行できる', (tester) async {
    await pumpScreen(tester);
    await selectFirstCategory(tester);
    await tester.enterText(find.byType(TextFormField).first, '1200');

    await tester.tap(find.text('保存する'));
    await tester.pumpAndSettle();

    expect((await db.getAllTransactions()).single.amount, 1200);
  });

  testWidgets('保存中は上下の保存導線を無効化し下部ボタンに進捗を出す', (tester) async {
    final provider = _BlockingTransactionProvider(db);
    await pumpScreen(tester, transactionProvider: provider);
    await selectFirstCategory(tester);
    await tester.enterText(find.byType(TextFormField).first, '1200');

    await tester.tap(find.text('保存する'));
    await tester.pump();

    expect(provider.createCalls, 1);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '保存'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'キャンセル'))
          .onPressed,
      isNull,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    provider.blocker.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('選択済みの登録者チップを押しても解除されず保存できる', (tester) async {
    await pumpScreen(tester);

    final memberId = (await db.getMembers()).first.id;
    final chip = tester.widget<ChoiceChip>(find.byType(ChoiceChip).first);
    expect(chip.selected, isTrue);

    await tester.tap(find.byType(ChoiceChip).first);
    await tester.pump();
    expect(
      tester.widget<ChoiceChip>(find.byType(ChoiceChip).first).selected,
      isTrue,
    );

    await selectFirstCategory(tester);
    await tester.enterText(find.byType(TextFormField).first, '1200');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final saved = (await db.getAllTransactions()).single;
    expect(saved.memberId, memberId);
    expect(find.text('登録者を選択してください'), findsNothing);
  });

  testWidgets('別の登録者チップを選ぶと選択表示と保存先が切り替わる', (tester) async {
    await db.insertMember('家族');
    final members = await db.getMembers();
    final firstMember = members.first;
    final secondMember = members.singleWhere((member) => member.name == '家族');

    await pumpScreen(tester);

    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, firstMember.name))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ChoiceChip>(
            find.widgetWithText(ChoiceChip, secondMember.name),
          )
          .selected,
      isFalse,
    );

    await tester.tap(find.widgetWithText(ChoiceChip, secondMember.name));
    await tester.pump();

    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, firstMember.name))
          .selected,
      isFalse,
    );
    expect(
      tester
          .widget<ChoiceChip>(
            find.widgetWithText(ChoiceChip, secondMember.name),
          )
          .selected,
      isTrue,
    );

    await selectFirstCategory(tester);
    await tester.enterText(find.byType(TextFormField).first, '1200');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect((await db.getAllTransactions()).single.memberId, secondMember.id);
  });

  testWidgets('登録者が未選択なら他の入力が正しくても保存しない', (tester) async {
    await pumpScreen(tester, memberProvider: _EmptyMemberProvider(db));

    await selectFirstCategory(tester);
    await tester.enterText(find.byType(TextFormField).first, '1200');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('登録者を選択してください'), findsOneWidget);
    expect(await db.getAllTransactions(), isEmpty);
  });

  testWidgets('メンバー読込中は本文用の補助色を使う', (tester) async {
    await pumpScreen(tester, memberProvider: _EmptyMemberProvider(db));

    final text = tester.widget<Text>(find.text('メンバー情報を読み込み中...'));
    expect(text.style?.color, ledgerTheme.colorScheme.onSurfaceVariant);
    expect(text.style?.color, isNot(LedgerTokens.subtext));
  });

  testWidgets('320px幅かつ文字倍率2.0でも上限額の全桁が見える', (tester) async {
    await pumpScreen(
      tester,
      textScaler: const TextScaler.linear(2),
      size: const Size(320, 690),
    );

    final amountField = find.byType(TextFormField).first;
    await tester.enterText(amountField, kMaxAmount.toStringAsFixed(0));
    await tester.pump();

    expect(tester.takeException(), isNull);
    final editable = _findRenderEditable(
      tester.renderObject<RenderObject>(amountField),
    );
    expect(editable.maxScrollExtent, 0, reason: '先頭の桁が横スクロール領域へ隠れている');
  });
}
