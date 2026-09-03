import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/db/database.dart';
import 'package:ledger_app/main.dart';
import 'package:ledger_app/models/transaction.dart';
import 'package:ledger_app/theme/ledger_tokens.dart';
import 'package:ledger_app/widgets/chart_palette.dart';
import 'package:ledger_app/widgets/ledger_card.dart';
import 'package:ledger_app/widgets/page_header.dart';

/// カテゴリ画面で、削除できなかったことがユーザーに伝わるかを確かめる。
///
/// FK 違反そのものは test/database_test.dart が DAO 直叩きで押さえているが、
/// それは「DB が弾く」ところまでしか見ていない。この画面の問題は、例外が
/// Provider を素通りして SnackBar になるまでの経路のほうにある。
/// CategoryProvider.delete を握りつぶしに書き換えても DB のテストは全部通り、
/// 「削除できていないのに成功したように見える」退行を誰も止められない。
void main() {
  late AppDatabase db;

  // 表示月を実時刻から切り離す（seed した取引が「今月」に依存しないように）
  final fixedNow = DateTime(2026, 7, 15);

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  /// アプリを起動して、設定からカテゴリ管理画面へ移動する
  Future<void> pumpCategoriesScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(LedgerApp(db: db, clock: () => fixedNow));
    await tester.pumpAndSettle();

    // 起動直後はホームタブ。設定タブを開いてカテゴリ管理へ進む
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byIcon(Icons.settings_outlined),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('カテゴリ管理'));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing);
    expect(find.widgetWithText(PageHeader, 'カテゴリ'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
  }

  /// [name] の行の削除ボタンを押す。
  ///
  /// delete_outline は行数ぶんあるので、対象の ListTile の中に限って探す
  Future<void> tapDeleteOn(WidgetTester tester, String name) async {
    if (find.widgetWithText(FilledButton, '編集').evaluate().isNotEmpty) {
      await tester.tap(find.widgetWithText(FilledButton, '編集'));
      await tester.pumpAndSettle();
    }
    final row = find.ancestor(
      of: find.text(name),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(
        of: row,
        matching: find.byIcon(Icons.remove_circle_outline),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 確認ダイアログの「削除」を押す
  Future<void> confirmDelete(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, '削除'));
    await tester.pumpAndSettle();
  }

  const failureMessage = '削除できませんでした（取引が残っている可能性があります）';

  // 固定カテゴリは deleteCategory が拒むので、下ごしらえは drift の一括削除で行う
  Future<void> deleteAllCategories() => db.delete(db.categories).go();

  /// シートの見出し。同じ文言が一覧下の追加ボタンにも出るので範囲を絞る
  Finder sheetTitle(String text) =>
      find.descendant(of: find.byType(BottomSheet), matching: find.text(text));

  /// 固定カテゴリ（その他）だけを残して他を消す
  Future<void> keepOnlyFixedCategory() async {
    for (final category in await db.getCategories()) {
      if (!category.isFixed) await db.deleteCategory(category.id);
    }
  }

  bool isEllipsized(WidgetTester tester, String text) =>
      tester.renderObject<RenderParagraph>(find.text(text)).didExceedMaxLines;

  testWidgets('カテゴリ見出しの戻るボタンで設定画面へ戻れる', (tester) async {
    await pumpCategoriesScreen(tester);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(PageHeader, 'カテゴリ'), findsNothing);
    expect(find.text('カテゴリ管理'), findsOneWidget);
  });

  testWidgets('一覧を下までスクロールしても戻るボタンを操作できる', (tester) async {
    await pumpCategoriesScreen(tester);

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -600),
      1200,
    );
    await tester.pumpAndSettle();

    expect(find.byType(BackButton).hitTestable(), findsOneWidget);
  });

  testWidgets('カテゴリ行は色ドット付きで、6文字名が1行の高さに収まる', (tester) async {
    const name = '食費（外食）';
    await deleteAllCategories();
    await db.insertCategory(name);
    final category = (await db.getCategories()).single;

    await pumpCategoriesScreen(tester);

    final tile = find.ancestor(
      of: find.text(name),
      matching: find.byType(ListTile),
    );
    final dot = tester.widget<CircleAvatar>(
      find.descendant(of: tile, matching: find.byType(CircleAvatar)),
    );
    expect(dot.backgroundColor, categoryColor(category.id));
    expect(isEllipsized(tester, name), isFalse);
    expect(tester.getSize(tile).height, 56);
  });

  testWidgets('一覧は1枚のカードに行を並べ、行間を区切り線で分ける', (tester) async {
    const names = ['食費', '日用品', '交通費'];
    await deleteAllCategories();
    for (final name in names) {
      await db.insertCategory(name);
    }

    await pumpCategoriesScreen(tester);

    // 行ごとにカードを分けると影の帯が並ぶ。カードは一覧全体で 1 枚だけ
    final card = find.byType(DecoratedSliver);
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.byType(LedgerCard)),
      findsNothing,
    );
    final scheme = Theme.of(tester.element(find.text(names.first))).colorScheme;
    final decoration =
        tester.widget<DecoratedSliver>(card).decoration as BoxDecoration;
    expect(decoration.color, scheme.surfaceContainerLow);
    expect(
      decoration.borderRadius,
      BorderRadius.circular(LedgerTokens.cardRadius),
    );
    for (final name in names) {
      expect(
        find.ancestor(of: find.text(name), matching: card),
        findsOneWidget,
      );
    }
    // 区切り線は行の間だけで、最後の行の下には引かない
    expect(
      find.descendant(of: card, matching: find.byType(Divider)),
      findsNWidgets(names.length - 1),
    );
  });

  testWidgets('編集中の固定カテゴリは削除も並べ替えもできない', (tester) async {
    await keepOnlyFixedCategory();
    await db.insertCategory('食費');
    final fixed = (await db.getCategories()).last;
    expect(fixed.name, 'その他');
    expect(fixed.isFixed, isTrue);

    await pumpCategoriesScreen(tester);

    // 通常時は他の行と同じで、名前と色は編集シートから変えられる
    await tester.tap(find.text(fixed.name));
    await tester.pumpAndSettle();
    expect(sheetTitle('カテゴリを編集'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'キャンセル'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '編集'));
    await tester.pumpAndSettle();

    final row = find.ancestor(
      of: find.text(fixed.name),
      matching: find.byType(ListTile),
    );
    expect(find.descendant(of: row, matching: find.text('固定')), findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.byIcon(Icons.drag_handle)),
      findsNothing,
    );
    final deleteButton = tester.widget<IconButton>(
      find.descendant(of: row, matching: find.byType(IconButton)),
    );
    expect(deleteButton.onPressed, isNull);
  });

  testWidgets('カテゴリが無くても追加ボタンから追加できる', (tester) async {
    await deleteAllCategories();

    await pumpCategoriesScreen(tester);
    expect(find.text('カテゴリがありません'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-category-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '新しいカテゴリ');
    await tester.tap(find.widgetWithText(FilledButton, '保存する'));
    await tester.pumpAndSettle();

    expect((await db.getCategories()).single.name, '新しいカテゴリ');
    expect(find.text('新しいカテゴリ'), findsOneWidget);
  });

  testWidgets('通常時と編集時で編集シート・削除・並べ替えの操作を切り替える', (tester) async {
    await pumpCategoriesScreen(tester);

    expect(find.byIcon(Icons.chevron_right), findsWidgets);
    expect(find.byIcon(Icons.remove_circle_outline), findsNothing);
    expect(find.byIcon(Icons.drag_handle), findsNothing);

    final first = (await db.getCategories()).first;
    await tester.tap(find.text(first.name));
    await tester.pumpAndSettle();
    expect(find.text('カテゴリを編集'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'キャンセル'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '編集'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '完了'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(find.byIcon(Icons.remove_circle_outline), findsWidgets);
    expect(find.byIcon(Icons.drag_handle), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, '完了'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '編集'), findsOneWidget);
  });

  testWidgets('編集シートで名前と色を一度に保存し一覧へ反映する', (tester) async {
    const originalName = '食費（外食）';
    const updatedName = '休日の外食';
    await deleteAllCategories();
    await db.insertCategory(originalName);
    final original = (await db.getCategories()).single;
    final fallbackColor = categoryColor(original.id);
    final selectedColor = categoryPalette.firstWhere(
      (color) => color != fallbackColor,
    );

    await pumpCategoriesScreen(tester);
    await tester.tap(find.text(originalName));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), updatedName);
    await tester.tap(
      find.byKey(ValueKey('category-color-${selectedColor.toARGB32()}')),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '保存する'));
    await tester.pumpAndSettle();

    final updated = (await db.getCategories()).single;
    expect(updated.id, original.id);
    expect(updated.name, updatedName);
    expect(updated.colorValue, selectedColor.toARGB32());
    final row = find.ancestor(
      of: find.text(updatedName),
      matching: find.byType(ListTile),
    );
    final dot = tester.widget<CircleAvatar>(
      find.descendant(of: row, matching: find.byType(CircleAvatar)),
    );
    expect(dot.backgroundColor, selectedColor);
  });

  testWidgets('新規追加は使用数が最少の先頭色を初期値にして保存する', (tester) async {
    await deleteAllCategories();
    await db.insertCategory(
      '色1-a',
      colorValue: categoryPalette.first.toARGB32(),
    );
    await db.insertCategory(
      '色1-b',
      colorValue: categoryPalette.first.toARGB32(),
    );
    await db.insertCategory('色2', colorValue: categoryPalette[1].toARGB32());

    await pumpCategoriesScreen(tester);
    await tester.tap(find.byKey(const Key('add-category-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '新しいカテゴリ');
    await tester.tap(find.widgetWithText(FilledButton, '保存する'));
    await tester.pumpAndSettle();

    final created = (await db.getCategories()).last;
    expect(created.name, '新しいカテゴリ');
    expect(created.colorValue, categoryPalette[2].toARGB32());
  });

  testWidgets('空・51文字・重複名は理由を示して編集シートを閉じない', (tester) async {
    final existingName = (await db.getCategories()).first.name;
    await pumpCategoriesScreen(tester);
    await tester.tap(find.byKey(const Key('add-category-button')));
    await tester.pumpAndSettle();

    final field = find.byType(TextField);
    final save = find.widgetWithText(FilledButton, '保存する');
    await tester.tap(save);
    await tester.pump();
    expect(find.text('カテゴリ名を入力してください'), findsOneWidget);
    expect(sheetTitle('カテゴリを追加'), findsOneWidget);

    await tester.enterText(field, 'あ' * 51);
    await tester.tap(save);
    await tester.pump();
    expect(find.text('カテゴリ名は50文字以内で入力してください'), findsOneWidget);
    expect(sheetTitle('カテゴリを追加'), findsOneWidget);

    await tester.enterText(field, existingName);
    await tester.tap(save);
    await tester.pump();
    expect(find.text('同じ名前のカテゴリがあります'), findsOneWidget);
    expect(sheetTitle('カテゴリを追加'), findsOneWidget);
  });

  testWidgets('キーボード表示中も保存ボタンが上に残る', (tester) async {
    await pumpCategoriesScreen(tester);
    await tester.tap(find.byKey(const Key('add-category-button')));
    await tester.pumpAndSettle();

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    final save = find.widgetWithText(FilledButton, '保存する');
    expect(save.hitTestable(), findsOneWidget);
    expect(tester.getRect(save).bottom, lessThanOrEqualTo(690 - 300));
  });

  testWidgets('並べ替えハンドルのドラッグで順番を保存する', (tester) async {
    final before = await db.getCategories();
    await pumpCategoriesScreen(tester);
    await tester.tap(find.widgetWithText(FilledButton, '編集'));
    await tester.pumpAndSettle();

    final firstRow = find.ancestor(
      of: find.text(before.first.name),
      matching: find.byType(ListTile),
    );
    final handle = find.descendant(
      of: firstRow,
      matching: find.byIcon(Icons.drag_handle),
    );
    expect(handle.hitTestable(), findsOneWidget);
    // 行の送り幅は 56px + 区切り線 1px。1 つ下の行と入れ替わるぶんだけ動かす
    await tester.timedDrag(
      handle,
      const Offset(0, 60),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();

    final after = await db.getCategories();
    expect(after.first.id, before[1].id);
    expect(after[1].id, before.first.id);
    // 受け皿は並べ替えの対象外で、末尾に据え置く
    expect(after.last.name, 'その他');
    expect(after.last.id, before.last.id);
  });

  testWidgets('DB 上限の50文字名でも描画例外が起きない', (tester) async {
    final name = 'あ' * 50;
    await deleteAllCategories();
    await db.insertCategory(name);

    await pumpCategoriesScreen(tester);

    expect(find.text(name), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('カテゴリが無いときはアイコン付きの空状態を描く', (tester) async {
    await deleteAllCategories();

    await pumpCategoriesScreen(tester);

    final empty = find.ancestor(
      of: find.text('カテゴリがありません'),
      matching: find.byType(Column),
    );
    expect(
      find.descendant(of: empty, matching: find.byIcon(Icons.label_outline)),
      findsOneWidget,
    );
  });

  testWidgets('取引が残っているカテゴリは削除できず、理由が SnackBar に出る', (tester) async {
    // 既定カテゴリは onCreate で 10 件入る。末尾は 690px の画面からはみ出して
    // タップが届かないので、先頭（食費）を対象にする
    final cats = await db.getCategories();
    final members = await db.getMembers();
    await db.insertTransaction(
      TransactionInput(
        memberId: members.first.id,
        categoryId: cats.first.id,
        amount: 1200,
        spentAt: DateTime(fixedNow.year, fixedNow.month, 5),
      ),
    );

    await pumpCategoriesScreen(tester);
    await tapDeleteOn(tester, cats.first.name);
    final deleteButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '削除'),
    );
    expect(
      deleteButton.style?.foregroundColor?.resolve({}),
      Theme.of(tester.element(find.byType(AlertDialog))).colorScheme.error,
    );
    await confirmDelete(tester);

    // 握りつぶし退行を殺すのはこの 1 行。DB が弾いても画面が黙っていたら通らない
    expect(find.text(failureMessage), findsOneWidget);

    // 一覧にも残り続ける
    expect(find.text(cats.first.name), findsOneWidget);
    expect(
      (await db.getCategories()).map((c) => c.name),
      contains(cats.first.name),
    );
  });

  testWidgets('取引のないカテゴリは削除でき、SnackBar は出ない', (tester) async {
    // 失敗ケースだけだと「常に失敗の SnackBar を出す」実装でも緑になるので、
    // 成功パスを対照として固定する
    final cats = await db.getCategories();
    final target = cats[1];

    await pumpCategoriesScreen(tester);
    await tapDeleteOn(tester, target.name);
    await confirmDelete(tester);

    expect(find.text(failureMessage), findsNothing);
    expect(find.text(target.name), findsNothing);
    expect(
      (await db.getCategories()).map((c) => c.name),
      isNot(contains(target.name)),
    );
  });
}
