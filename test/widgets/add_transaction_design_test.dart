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
import 'package:ledger_app/widgets/chart_palette.dart';
import 'package:ledger_app/widgets/ledger_card.dart';
import 'package:provider/provider.dart';

class _EmptyMemberProvider extends MemberProvider {
  _EmptyMemberProvider(super.db);

  @override
  Future<void> fetchMembers() async {}
}

class _BlockingTransactionProvider extends TransactionProvider {
  _BlockingTransactionProvider(super.db)
    : super(clock: () => DateTime(2026, 7, 15));

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

Finder _choiceChip(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(ChoiceChip));

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> pumpScreen(
    WidgetTester tester, {
    TextScaler textScaler = TextScaler.noScaling,
    MemberProvider? memberProvider,
    TransactionProvider? transactionProvider,
    TransactionView? existing,
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
            value:
                transactionProvider ??
                TransactionProvider(db, clock: () => DateTime(2026, 7, 15)),
          ),
        ],
        child: MaterialApp(
          theme: ledgerTheme,
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                child: child!,
              ),
          home: AddTransactionScreen(existing: existing),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> selectFirstCategory(WidgetTester tester) async {
    final firstCategory = (await db.getCategories()).first.name;
    final chip = _choiceChip(firstCategory);
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '保存する'));
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
    expect(textField.decoration?.prefixText, isNull);
    expect(textField.decoration?.prefixIcon, isNull);
    final fittedBoxFinder = find.ancestor(
      of: amountFieldFinder,
      matching: find.byType(FittedBox),
    );
    expect(fittedBoxFinder, findsOneWidget);
    expect(tester.widget<FittedBox>(fittedBoxFinder).fit, BoxFit.scaleDown);

    await tester.enterText(amountFieldFinder, '3240');
    await tester.pump();
    final editable = _findRenderEditable(
      tester.renderObject<RenderObject>(amountFieldFinder),
    );
    final firstDigitX =
        editable
            .localToGlobal(
              Offset(
                editable
                    .getLocalRectForCaret(const TextPosition(offset: 0))
                    .left,
                0,
              ),
            )
            .dx;
    final currencyRight = tester.getRect(find.text('¥')).right;
    expect(firstDigitX - currencyRight, inInclusiveRange(0, 8));
  });

  testWidgets('3分割ヘッダと下部保存ボタン、内容と日付のカードを表示する', (tester) async {
    await pumpScreen(tester);

    expect(find.byType(AppBar), findsNothing);
    expect(find.text('キャンセル'), findsOneWidget);
    expect(find.text('支出を追加'), findsOneWidget);
    expect(find.text('保存'), findsNothing);
    expect(find.widgetWithText(FilledButton, '保存する'), findsOneWidget);
    expect(find.text('カテゴリ'), findsOneWidget);
    expect(find.text('支払った人'), findsOneWidget);
    expect(find.byIcon(Icons.label_outline), findsNothing);
    expect(find.byIcon(Icons.person_outline), findsNothing);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.style?.shape, isNull, reason: 'ボタン形状は画面ではなくテーマで決める');
    expect(
      Theme.of(
        tester.element(find.byType(FilledButton)),
      ).filledButtonTheme.style?.shape?.resolve({}),
      isA<StadiumBorder>(),
    );

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
      find.descendant(of: card, matching: find.byIcon(Icons.chevron_right)),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.calendar_today), findsNothing);
  });

  testWidgets('カテゴリと支払った人の選択表示を共通ChipThemeへ委譲する', (tester) async {
    await pumpScreen(tester);

    final category = (await db.getCategories()).first;
    final member = (await db.getMembers()).first;
    final categoryChip = tester.widget<ChoiceChip>(_choiceChip(category.name));
    final memberChip = tester.widget<ChoiceChip>(_choiceChip(member.name));

    for (final chip in [categoryChip, memberChip]) {
      expect(chip.side, isNull);
      expect(chip.selectedColor, isNull);
      expect(
        chip.backgroundColor,
        ledgerTheme.colorScheme.surfaceContainerLowest,
      );
    }
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
    final cancelButtonRect = tester.getRect(
      find.widgetWithText(TextButton, 'キャンセル'),
    );
    expect(cancelRect.right, lessThanOrEqualTo(titleRect.left));
    expect(titleRect.center.dx, closeTo(160, 2));
    final header = find.ancestor(
      of: find.text('支出を追加'),
      matching: find.byType(Row),
    );
    final slots = find.descendant(of: header, matching: find.byType(Expanded));
    expect(slots, findsNWidgets(3));
    for (var i = 0; i < 3; i++) {
      expect(tester.getRect(slots.at(i)).width, closeTo((320 - 16) / 3, 1));
    }
    expect(cancelButtonRect.width, greaterThanOrEqualTo(48));
    expect(cancelButtonRect.height, greaterThanOrEqualTo(48));
    expect(cancelButtonRect.width, lessThanOrEqualTo((320 - 16) / 3));
    final title = tester.widget<Text>(find.text('支出を追加'));
    expect(title.maxLines, isNull);
    expect(title.overflow, isNull);
    expect(
      tester
          .renderObject<RenderParagraph>(find.text('支出を追加'))
          .didExceedMaxLines,
      isFalse,
    );
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

  testWidgets('文字倍率2.0でも内容と日付のラベルを1行で読める', (tester) async {
    await pumpScreen(
      tester,
      textScaler: const TextScaler.linear(2),
      size: const Size(320, 690),
    );
    for (final label in ['内容', '日付']) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      expect(
        paragraph.size.width,
        greaterThanOrEqualTo(paragraph.getMaxIntrinsicWidth(double.infinity)),
        reason: '$label の2文字が折り返されている',
      );
    }
  });

  testWidgets('日付行の波紋をカード背景より手前に描くMaterialを持つ', (tester) async {
    await pumpScreen(tester);

    final card = find.byType(LedgerCard);
    final dateInkWell = find.ancestor(
      of: find.byIcon(Icons.chevron_right),
      matching: find.byType(InkWell),
    );
    expect(find.descendant(of: card, matching: dateInkWell), findsOneWidget);
    final transparentAncestors = find
        .ancestor(of: dateInkWell, matching: find.byType(Material))
        .evaluate()
        .map((element) => element.widget)
        .whereType<Material>()
        .where((material) => material.type == MaterialType.transparency);
    expect(transparentAncestors, hasLength(1));
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

  testWidgets('低い画面でキーボードを表示しても溢れず保存ボタンを押せる', (tester) async {
    await pumpScreen(tester, size: const Size(360, 400));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final saveButton = find.widgetWithText(FilledButton, '保存する');
    expect(saveButton.hitTestable(), findsOneWidget);
    expect(tester.getRect(saveButton).bottom, lessThanOrEqualTo(100));
    await tester.tap(saveButton);
    await tester.pump();
    expect(find.text('金額を入力してください'), findsOneWidget);
  });

  testWidgets('下部の保存を同一フレームで二度操作しても1回だけ作成する', (tester) async {
    final provider = _BlockingTransactionProvider(db);
    await pumpScreen(tester, transactionProvider: provider);
    await selectFirstCategory(tester);
    await tester.enterText(find.byType(TextFormField).first, '1200');

    final onSave =
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed!;
    onSave();
    onSave();
    await tester.pump();

    try {
      expect(provider.createCalls, 1);
    } finally {
      provider.blocker.complete();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('下部の保存ボタンから保存処理を実行できる', (tester) async {
    await pumpScreen(tester);
    await selectFirstCategory(tester);
    await tester.enterText(find.byType(TextFormField).first, '1200');

    await tester.tap(find.text('保存する'));
    await tester.pumpAndSettle();

    expect((await db.getAllTransactions()).single.amount, 1200);
  });

  testWidgets('編集画面の見出しを表示し下部ボタンから更新できる', (tester) async {
    final category = (await db.getCategories()).first;
    final member = (await db.getMembers()).first;
    await db.insertTransaction(
      TransactionInput(
        memberId: member.id,
        categoryId: category.id,
        amount: 1200,
        spentAt: DateTime(2026, 8, 30),
      ),
    );
    final existing = (await db.getAllTransactions()).single;
    await pumpScreen(tester, existing: existing);

    expect(find.text('支出を編集'), findsOneWidget);
    expect(find.text('支出を追加'), findsNothing);
    expect(find.text('2026年8月30日（日）'), findsOneWidget);
    final memoField = find.byType(TextFormField).last;
    await tester.ensureVisible(memoField);
    await tester.pumpAndSettle();
    await tester.enterText(memoField, '更新済み');
    await tester.tap(find.text('保存する'));
    await tester.pumpAndSettle();

    final saved = (await db.getAllTransactions()).single;
    expect(saved.id, existing.id);
    expect(saved.memo, '更新済み');
  });

  testWidgets('保存中はキャンセルと下部保存を無効化し進捗を出す', (tester) async {
    final provider = _BlockingTransactionProvider(db);
    await pumpScreen(tester, transactionProvider: provider);
    await selectFirstCategory(tester);
    await tester.enterText(find.byType(TextFormField).first, '1200');

    await tester.tap(find.text('保存する'));
    await tester.pump();

    expect(provider.createCalls, 1);
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

    final member = (await db.getMembers()).first;
    final memberChip = _choiceChip(member.name);
    final chip = tester.widget<ChoiceChip>(memberChip);
    expect(chip.selected, isTrue);
    final avatar = tester.widget<CircleAvatar>(
      find.descendant(of: memberChip, matching: find.byType(CircleAvatar)),
    );
    expect(avatar.backgroundColor, memberColor(member.id));
    expect(
      find.descendant(of: memberChip, matching: find.text('自')),
      findsOneWidget,
    );

    await tester.ensureVisible(memberChip);
    await tester.pumpAndSettle();
    await tester.tap(memberChip);
    await tester.pump();
    expect(tester.widget<ChoiceChip>(memberChip).selected, isTrue);

    await selectFirstCategory(tester);
    await tester.enterText(find.byType(TextFormField).first, '1200');
    await tester.tap(find.text('保存する'));
    await tester.pumpAndSettle();

    final saved = (await db.getAllTransactions()).single;
    expect(saved.memberId, member.id);
    expect(find.text('支払った人を選択してください'), findsNothing);
  });

  testWidgets('別の登録者チップを選ぶと選択表示と保存先が切り替わる', (tester) async {
    await db.insertMember('家族');
    final members = await db.getMembers();
    final firstMember = members.first;
    final secondMember = members.singleWhere((member) => member.name == '家族');

    await pumpScreen(tester);

    expect(
      tester.widget<ChoiceChip>(_choiceChip(firstMember.name)).selected,
      isTrue,
    );
    expect(
      tester.widget<ChoiceChip>(_choiceChip(secondMember.name)).selected,
      isFalse,
    );

    final secondMemberChip = _choiceChip(secondMember.name);
    await tester.ensureVisible(secondMemberChip);
    await tester.pumpAndSettle();
    await tester.tap(secondMemberChip);
    await tester.pump();

    expect(
      tester.widget<ChoiceChip>(_choiceChip(firstMember.name)).selected,
      isFalse,
    );
    expect(
      tester.widget<ChoiceChip>(_choiceChip(secondMember.name)).selected,
      isTrue,
    );

    await selectFirstCategory(tester);
    await tester.enterText(find.byType(TextFormField).first, '1200');
    await tester.tap(find.text('保存する'));
    await tester.pumpAndSettle();

    expect((await db.getAllTransactions()).single.memberId, secondMember.id);
  });

  testWidgets('登録者が未選択なら他の入力が正しくても保存しない', (tester) async {
    await pumpScreen(tester, memberProvider: _EmptyMemberProvider(db));

    await selectFirstCategory(tester);
    await tester.enterText(find.byType(TextFormField).first, '1200');
    await tester.tap(find.text('保存する'));
    await tester.pumpAndSettle();

    expect(find.text('支払った人を選択してください'), findsOneWidget);
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
    final amountArea = tester.getRect(
      find.ancestor(of: amountField, matching: find.byType(FittedBox)),
    );
    expect(
      tester.getRect(find.text('¥')).left,
      greaterThanOrEqualTo(amountArea.left),
      reason: '上限額の円記号が入力領域の左端で切れている',
    );
  });
}
