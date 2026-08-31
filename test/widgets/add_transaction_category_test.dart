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
import 'package:provider/provider.dart';

Finder _categoryDecorator() => find.byWidgetPredicate(
  (widget) => widget is InputDecorator && widget.decoration.labelText == 'カテゴリ',
);

Finder _categoryField() => find.ancestor(
  of: _categoryDecorator(),
  matching: find.byType(FormField<int>),
);

Finder _categoryChips() =>
    find.descendant(of: _categoryField(), matching: find.byType(ChoiceChip));

Finder _categoryChip(String name) => find.descendant(
  of: _categoryField(),
  matching: find.widgetWithText(ChoiceChip, name),
);

void _expectSelectedCategory(WidgetTester tester, String? name) {
  final selected = tester
      .widgetList<ChoiceChip>(_categoryChips())
      .where((chip) => chip.selected)
      .map((chip) => (chip.label as Text).data);
  expect(selected, name == null ? isEmpty : [name]);
}

Future<void> _selectCategory(WidgetTester tester, String name) async {
  final chip = _categoryChip(name);
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> pumpScreen(
    WidgetTester tester, {
    TransactionView? existing,
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => CategoryProvider(db)),
          ChangeNotifierProvider(create: (_) => MemberProvider(db)),
          ChangeNotifierProvider(
            create:
                (_) =>
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

  testWidgets('カテゴリ未選択では入力欄にエラーを出し、選択すれば保存できる', (tester) async {
    final category = (await db.getCategories()).first;
    await pumpScreen(tester);
    _expectSelectedCategory(tester, null);
    await tester.enterText(find.byType(TextFormField).first, '1200');

    await tester.tap(find.widgetWithText(FilledButton, '保存する'));
    await tester.pumpAndSettle();

    const error = 'カテゴリを選択してください';
    expect(
      tester.state<FormFieldState<int>>(_categoryField()).errorText,
      error,
    );
    expect(
      find.descendant(of: _categoryDecorator(), matching: find.text(error)),
      findsOneWidget,
      reason: 'SnackBar だけでなくカテゴリ欄にエラーを表示する',
    );
    expect(await db.getAllTransactions(), isEmpty);

    await _selectCategory(tester, category.name);
    await tester.tap(find.widgetWithText(FilledButton, '保存する'));
    await tester.pumpAndSettle();

    expect(find.text(error), findsNothing);
    final saved = (await db.getAllTransactions()).single;
    expect(saved.categoryId, category.id);
    expect(saved.amount, 1200);
  });

  testWidgets('カテゴリを切り替えた後に再タップしても単一選択を保ち、選んだIDで保存する', (tester) async {
    final categories = await db.getCategories();
    final first = categories.first;
    final second = categories[1];
    await pumpScreen(tester);
    await tester.enterText(find.byType(TextFormField).first, '2300');

    await _selectCategory(tester, first.name);
    _expectSelectedCategory(tester, first.name);
    await _selectCategory(tester, second.name);
    _expectSelectedCategory(tester, second.name);
    await _selectCategory(tester, second.name);
    _expectSelectedCategory(tester, second.name);

    await tester.tap(find.widgetWithText(FilledButton, '保存する'));
    await tester.pumpAndSettle();

    final saved = (await db.getAllTransactions()).single;
    expect(saved.categoryId, second.id);
    expect(saved.amount, 2300);
  });

  testWidgets('編集では保存済みカテゴリを初期選択し、変更したカテゴリで同じ取引を更新する', (tester) async {
    final categories = await db.getCategories();
    final original = categories[1];
    final replacement = categories.last;
    final memberId = (await db.getMembers()).first.id;
    await db.insertTransaction(
      TransactionInput(
        memberId: memberId,
        categoryId: original.id,
        amount: 3400,
        spentAt: DateTime(2026, 7, 20),
      ),
    );
    final existing = (await db.getAllTransactions()).single;
    await pumpScreen(tester, existing: existing);

    _expectSelectedCategory(tester, original.name);
    await _selectCategory(tester, replacement.name);
    _expectSelectedCategory(tester, replacement.name);
    await tester.tap(find.widgetWithText(FilledButton, '保存する'));
    await tester.pumpAndSettle();

    final saved = (await db.getAllTransactions()).single;
    expect(saved.id, existing.id);
    expect(saved.categoryId, replacement.id);
    expect(saved.amount, existing.amount);
    expect(saved.memberId, existing.memberId);
    expect(saved.spentAt, existing.spentAt);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('360px幅・文字倍率$scaleで50文字のカテゴリ30件を省略表示し、末尾まで選択できる', (
      tester,
    ) async {
      for (final category in await db.getCategories()) {
        await db.deleteCategory(category.id);
      }
      for (var index = 1; index <= 30; index++) {
        await db.insertCategory(
          '${index.toString().padLeft(2, '0')}${'長' * 48}',
        );
      }
      final categories = await db.getCategories();
      await pumpScreen(tester, textScaler: TextScaler.linear(scale));

      expect(tester.takeException(), isNull);
      expect(_categoryChips(), findsNWidgets(30));
      for (final category in categories) {
        final chip = _categoryChip(category.name);
        final label = find.descendant(
          of: chip,
          matching: find.text(category.name),
        );
        final paragraph = tester.renderObject<RenderParagraph>(label);
        expect(paragraph.maxLines, 1);
        expect(paragraph.overflow, TextOverflow.ellipsis);
        expect(
          paragraph.didExceedMaxLines,
          isTrue,
          reason: '50文字のカテゴリ名を1行で省略する',
        );
        expect(tester.widget<ChoiceChip>(chip).tooltip, category.name);
      }

      await tester.enterText(find.byType(TextFormField).first, '4500');
      await tester.pumpAndSettle();
      final saveButton = find.widgetWithText(FilledButton, '保存する');
      final saveRect = tester.getRect(saveButton);
      final last = categories.last;
      final lastChip = _categoryChip(last.name);
      expect(lastChip.hitTestable(), findsNothing);

      await tester.dragUntilVisible(
        lastChip,
        find.byType(SingleChildScrollView),
        const Offset(0, -350),
        maxIteration: 30,
      );
      await tester.pumpAndSettle();

      expect(lastChip.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(tester.getRect(saveButton), saveRect);
      expect(saveButton.hitTestable(), findsOneWidget);
      await tester.tap(lastChip);
      await tester.pumpAndSettle();
      _expectSelectedCategory(tester, last.name);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      final saved = (await db.getAllTransactions()).single;
      expect(saved.categoryId, last.id);
      expect(saved.amount, 4500);
      expect(tester.takeException(), isNull);
    });
  }
}
